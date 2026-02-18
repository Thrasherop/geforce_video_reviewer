import os
import re
from flask import Flask, request, jsonify, send_file, render_template, abort, Response, stream_with_context

from objects.action_factory import create_action_from_request
from services.action_history_service import ActionHistoryService

USE_FLUTTER_FE = True
WEB_BUILD_DIR = os.path.join(os.path.dirname(__file__), 'frontend', 'build', 'web')

if USE_FLUTTER_FE:
    app = Flask(__name__, static_folder=WEB_BUILD_DIR, static_url_path='')
else:
    app = Flask(__name__, template_folder='templates', static_folder='static')
history_service = ActionHistoryService()

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
            with open(path, 'rb') as f:
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
        rv = Response(stream_with_context(generate()), status=206, mimetype='video/mp4')
        rv.headers['Content-Range'] = f'bytes {start}-{end}/{file_size}'
        rv.headers['Accept-Ranges'] = 'bytes'
        rv.headers['Content-Length'] = str(length)
        return rv
    # No Range header, serve full file
    return send_file(path, mimetype='video/mp4')

@app.route('/api/action', methods=['POST'])
def action():
    data = request.get_json() or {}
    action_type = data.get('action')
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