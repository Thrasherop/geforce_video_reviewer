import os
import re
import subprocess
import tempfile
import threading
import time
from flask import Flask, request, jsonify, send_file, render_template, abort, Response, stream_with_context

from objects.action_factory import create_action_from_request
from services.action_history_service import ActionHistoryService

USE_FLUTTER_FE = True
WEB_BUILD_DIR = os.path.join(os.path.dirname(__file__), 'frontend', 'build', 'web')
ALLOWED_CORS_ORIGINS = {
    'http://localhost:5173',
    'http://127.0.0.1:5173',
}

if USE_FLUTTER_FE:
    app = Flask(__name__, static_folder=WEB_BUILD_DIR, static_url_path='')
else:
    app = Flask(__name__, template_folder='templates', static_folder='static')
history_service = ActionHistoryService()
_active_video_stream_counts = {}
_active_video_stream_counts_lock = threading.Lock()
_active_video_stream_counts_condition = threading.Condition(_active_video_stream_counts_lock)


@app.after_request
def add_cors_headers(response):
    origin = request.headers.get('Origin')
    if origin in ALLOWED_CORS_ORIGINS:
        response.headers['Access-Control-Allow-Origin'] = origin
        response.headers['Vary'] = 'Origin'
        response.headers['Access-Control-Allow-Methods'] = 'GET, POST, OPTIONS'
        response.headers['Access-Control-Allow-Headers'] = 'Content-Type'
    return response

# Pattern to match ShadowPlay filenames like 'Game YYYY.MM.DD - hh.mm.ss.xx.DVR.mp4'
FILENAME_PATTERN = re.compile(r'.*\d{4}\.\d{2}\.\d{2} - \d{2}\.\d{2}\.\d{2}\.\d{2}\.DVR\.mp4$')

@app.route('/api/files')
def list_files():
    dir_path = request.args.get('dir')
    if not dir_path:
        return jsonify({'error': 'No directory provided'}), 400
    dir_path = os.path.normpath(dir_path)
    if not os.path.isdir(dir_path):
        return jsonify({'error': f'Directory does not exist: {dir_path}'}), 400
    # Determine whether to include previously reviewed (all .mp4) or only ShadowPlay filenames
    include_reviewed = request.args.get('include_reviewed', 'false').lower() in ('1', 'true', 'yes', 'on')
    entries = []
    for entry in os.scandir(dir_path):
        if not entry.is_file():
            continue
        name = entry.name
        if include_reviewed:
            # include any mp4
            if not name.lower().endswith('.mp4'):
                continue
        else:
            # only include shadowplay-format
            if not FILENAME_PATTERN.match(name):
                continue
        mtime = entry.stat().st_mtime
        entries.append((entry.path, mtime))
    # Sort by modification time descending (newest first)
    entries.sort(key=lambda x: x[1], reverse=True)
    files = [path for path, _ in entries]
    return jsonify({'files': files})

@app.route('/api/video')
def get_video():
    path = request.args.get('path')
    if not path:
        abort(400)
    path = os.path.normpath(path)
    if not os.path.isfile(path):
        abort(404)
    file_size = os.path.getsize(path)
    range_header = request.headers.get('Range', None)
    if range_header:
        # Parse Range header
        m = re.match(r"bytes=(\d+)-(\d*)", range_header)
        if m:
            start = int(m.group(1))
            end = int(m.group(2)) if m.group(2) else file_size - 1
        else:
            start = 0
            end = file_size - 1
        if start >= file_size:
            # Requested range not satisfiable
            abort(416)
        end = min(end, file_size - 1)
        # Validate that end >= start to avoid negative content length
        if end < start:
            abort(416)
        length = end - start + 1
        def generate():
            file_opened = False
            try:
                with open(path, 'rb') as f:
                    file_opened = True
                    with _active_video_stream_counts_lock:
                        current_count = _active_video_stream_counts.get(path, 0) + 1
                        _active_video_stream_counts[path] = current_count
                    f.seek(start)
                    remaining = length
                    chunk_size = 8192
                    while remaining > 0:
                        read_length = min(chunk_size, remaining)
                        data = f.read(read_length)
                        if not data:
                            break
                        remaining -= len(data)
                        yield data
            finally:
                if file_opened:
                    with _active_video_stream_counts_lock:
                        next_count = max(0, _active_video_stream_counts.get(path, 1) - 1)
                        if next_count == 0:
                            _active_video_stream_counts.pop(path, None)
                        else:
                            _active_video_stream_counts[path] = next_count
                        _active_video_stream_counts_condition.notify_all()
        rv = Response(stream_with_context(generate()), status=206, mimetype='video/mp4')
        rv.headers['Content-Range'] = f'bytes {start}-{end}/{file_size}'
        rv.headers['Accept-Ranges'] = 'bytes'
        rv.headers['Content-Length'] = str(length)
        return rv
    # No Range header, serve full file
    return send_file(path, mimetype='video/mp4')

@app.route('/api/thumbnail')
def get_thumbnail():
    path = request.args.get('path')
    if not path:
        return jsonify({'error': 'No file path provided'}), 400
    path = os.path.normpath(path)
    if not os.path.isfile(path):
        return jsonify({'error': f'File does not exist: {path}'}), 404

    temp_thumbnail_path = ''
    try:
        with tempfile.NamedTemporaryFile(suffix='.jpg', delete=False) as tmp_file:
            temp_thumbnail_path = tmp_file.name

        # Use ffmpeg to grab a frame near the start of the video.
        command = [
            'ffmpeg',
            '-hide_banner',
            '-loglevel',
            'error',
            '-y',
            '-ss',
            '00:00:01.000',
            '-i',
            path,
            '-frames:v',
            '1',
            '-q:v',
            '2',
            temp_thumbnail_path,
        ]
        completed = subprocess.run(command, capture_output=True, text=True, check=False)
        if completed.returncode != 0 or not os.path.isfile(temp_thumbnail_path):
            error_text = (completed.stderr or completed.stdout or 'unknown ffmpeg error').strip()
            return jsonify({'error': f'Unable to generate thumbnail: {error_text}'}), 500

        with open(temp_thumbnail_path, 'rb') as thumbnail_file:
            image_bytes = thumbnail_file.read()
        return Response(image_bytes, mimetype='image/jpeg')
    except FileNotFoundError:
        return jsonify({'error': 'ffmpeg is not installed or not on PATH'}), 500
    except Exception as exc:
        return jsonify({'error': str(exc)}), 500
    finally:
        if temp_thumbnail_path and os.path.isfile(temp_thumbnail_path):
            os.remove(temp_thumbnail_path)

@app.route('/api/action', methods=['POST'])
def action():
    data = request.get_json() or {}
    action_type = data.get('action')
    if str(action_type or "").strip().lower() == "delete":
        delete_path = os.path.normpath(str(data.get('path') or ""))
        with _active_video_stream_counts_condition:
            active_count_for_delete_path = _active_video_stream_counts.get(delete_path, 0)
            wait_timeout_seconds = 15.0
            wait_started = time.time()
            while active_count_for_delete_path > 0:
                elapsed = time.time() - wait_started
                remaining = wait_timeout_seconds - elapsed
                if remaining <= 0:
                    break
                _active_video_stream_counts_condition.wait(timeout=remaining)
                active_count_for_delete_path = _active_video_stream_counts.get(delete_path, 0)
    try:
        action_object = create_action_from_request(action_type, data)
        result = history_service.execute(action_object)
        return jsonify({'success': True, **result})
    except ValueError as exc:
        return jsonify({'error': str(exc)}), 400
    except FileNotFoundError as exc:
        return jsonify({'error': str(exc)}), 404
    except (FileExistsError, TimeoutError) as exc:
        return jsonify({'error': str(exc)}), 409
    except RuntimeError as exc:
        return jsonify({'error': str(exc)}), 500
    except Exception as exc:
        return jsonify({'error': str(exc)}), 500


@app.route('/api/undo', methods=['POST'])
def undo_action():
    data = request.get_json() or {}
    folder_path = (data.get('dir') or '').strip()
    fallback_path = (data.get('path') or '').strip()

    if not folder_path and fallback_path:
        folder_path = os.path.dirname(fallback_path)
    if not folder_path:
        return jsonify({'error': 'Missing directory for undo'}), 400

    folder_path = os.path.normpath(folder_path)
    if not os.path.isdir(folder_path):
        return jsonify({'error': f'Directory does not exist: {folder_path}'}), 400

    try:
        result = history_service.undo(folder_path)
        return jsonify({'success': True, **result})
    except ValueError as exc:
        return jsonify({'error': str(exc)}), 400
    except FileNotFoundError as exc:
        return jsonify({'error': str(exc)}), 404
    except (FileExistsError, TimeoutError) as exc:
        return jsonify({'error': str(exc)}), 409
    except Exception as exc:
        return jsonify({'error': str(exc)}), 500


@app.route('/api/redo', methods=['POST'])
def redo_action():
    data = request.get_json() or {}
    folder_path = (data.get('dir') or '').strip()
    fallback_path = (data.get('path') or '').strip()

    if not folder_path and fallback_path:
        folder_path = os.path.dirname(fallback_path)
    if not folder_path:
        return jsonify({'error': 'Missing directory for redo'}), 400

    folder_path = os.path.normpath(folder_path)
    if not os.path.isdir(folder_path):
        return jsonify({'error': f'Directory does not exist: {folder_path}'}), 400

    try:
        result = history_service.redo(folder_path)
        return jsonify({'success': True, **result})
    except ValueError as exc:
        return jsonify({'error': str(exc)}), 400
    except FileNotFoundError as exc:
        return jsonify({'error': str(exc)}), 404
    except (FileExistsError, TimeoutError) as exc:
        return jsonify({'error': str(exc)}), 409
    except Exception as exc:
        return jsonify({'error': str(exc)}), 500


if USE_FLUTTER_FE:
    @app.route('/', defaults={'path': ''})
    @app.route('/<path:path>')
    def serve_spa(path):
        # Serve built frontend assets directly when present.
        if path:
            asset_path = os.path.join(app.static_folder, path)
            if os.path.isfile(asset_path):
                return app.send_static_file(path)
        # Fall back to index for SPA routing.
        return app.send_static_file('index.html')
else:
    @app.route('/')
    def index():
        return render_template('index.html')

if __name__ == '__main__':
    app.run(debug=True) 