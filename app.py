import os
import re
import subprocess
import tempfile
import threading
import time
import json
import uuid

from flask import Flask, request, jsonify, send_file, render_template, abort, Response, stream_with_context

from objects.action_factory import create_action_from_request
from objects.Video import Video
from services.action_history_service import ActionHistoryService
from objects.Context import Context
from services.DirectoryRecordService import DirectoryRecordService
from services.FileSelectionService import FileSelectionService
from services.YouTubeService import YouTubeService

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
_upload_jobs = {}
_upload_jobs_lock = threading.Lock()
_upload_jobs_condition = threading.Condition(_upload_jobs_lock)
_upload_job_retention_seconds = 60 * 60

# Create runtime context
global_context = Context(
    DirectoryRecordService(),
    FileSelectionService(),
    YouTubeService()
)

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

def _cleanup_stale_upload_jobs_locked() -> None:
    now = time.time()
    stale_ids = []
    for job_id, job_data in _upload_jobs.items():
        if not job_data.get('is_complete'):
            continue
        if now - job_data.get('updated_at', now) >= _upload_job_retention_seconds:
            stale_ids.append(job_id)

    for job_id in stale_ids:
        _upload_jobs.pop(job_id, None)

def _append_upload_job_event(job_id: str, event_payload: dict) -> None:
    with _upload_jobs_condition:
        job_data = _upload_jobs.get(job_id)
        if not job_data:
            return

        job_data['events'].append(event_payload)
        job_data['updated_at'] = time.time()
        _upload_jobs_condition.notify_all()


@app.route('/api/migration/mark_to_keep_local', methods=['POST'])
def mark_to_keep_local():

    """

        Marks file(s) to be kept local, or unmarks file(s).

        Such files will be protected against archiving. Files
        may still be uploaded, just not archived.

        Takes in an array of file path(s) in parameter 'target_files'.
        Takes in a bool of whether to mark these files as keep or not in
        parameter 'designation'.

        Returns an dict of success/failure counts, and lists of the paths
        that succeeeded/failed

    """

    # Extract and validate parameters
    request_json = request.get_json(silent=True) or {}
    target_files : list[str] = request_json.get('target_files')  # list of files to set designation
    designation_raw = request_json.get('designation', False)
    if type(designation_raw) == bool:
        designation : bool = designation_raw
    elif type(designation_raw) == str:
        designation : bool = designation_raw.lower() in ('1', 'true', 'yes', 'on')  # bool value to make files
    else:
        designation = None

    if target_files == None or len(target_files) < 1:
        return jsonify({"error" : "target_files is a required parameter and must be a list of paths"}), 400
    if designation == None or type(designation) != bool:
        return jsonify({"error" : "designation iss a required parameter and must be a bool"})


    # Apply the changes, record the results
    results = {
        "success_count" : 0,
        "success_paths" : [],
        "failure_count" : 0,
        "failure_paths" : [] 
    }
    for file in target_files:
        this_result = global_context.directory_record_service.set_keep_local(video_path = file, keep_local = designation)
        if not this_result:
            try:
                # Index the file so we can modify it
                Video(file, global_context)
                this_result = global_context.directory_record_service.set_keep_local(video_path = file, keep_local = designation)
            except Exception as exc:
                this_result = False

        if this_result:
            results['success_count'] += 1
            results['success_paths'].append(file)
        else:
            results['failure_count'] += 1
            results['failure_paths'].append(file)


    return jsonify(results)


@app.route('/api/migration/are_files_marked_to_keep_local', methods=['POST'])
def are_files_marked_to_keep_local():


    """

        Takes in list of file paths and returns
        a dict of the markings for each file

        PARAMS:
           - target_files : List[str] - list of filepaths for the query     

        return:
           - data {"path_name" : true}
    """

    # extract and validate parameters
    request_json = request.get_json(silent=True) or {}
    target_files : list[str] = request_json.get('target_files')

    if target_files == None or len(target_files) < 1:
        return jsonify({"error" : "target_files is a required parameter and must be a list of strings"}), 400

    # Loop through and grab data 
    statuses = {}
    for file in target_files:

        designation = global_context.directory_record_service.should_keep_local(file)
        statuses[file] = designation

    return statuses


@app.route('/api/migration/upload_file_paths', methods=["POST"])
def upload_file_paths():

    """

        Requests a set of files to be uploaded to
        youtube. 

        Parameters:

            - target_files : list of file paths to be uploaded
            - migrate_files : bool whether or not to archive files
            - visibility_setting : str of unlisted, private, or public
            - made_for_kids : bool of whethger or not to mark video as for kids

        

    """

    # extract and deduplicate files
    request_json = request.get_json(silent=True) or {}
    raw_files = request_json.get('target_files') or []
    if type(raw_files) != list or len(raw_files) == 0:
        return jsonify({"error": "target_files is required and must be a non-empty list"}), 400

    file_set = sorted(set(raw_files))
    migrate_files = request_json.get('migrate_files', True)
    if type(migrate_files) == str:
        migrate_files = migrate_files.lower() in ('1', 'true', 'yes', 'on')
    made_for_kids = request_json.get('made_for_kids')
    if type(made_for_kids) == str:
        made_for_kids = made_for_kids.lower() in ('1', 'true', 'yes', 'on')
    elif type(made_for_kids) != bool:
        made_for_kids = None
    upload_name = request_json.get('upload_name')
    if type(upload_name) != str:
        upload_name = None
    elif upload_name.strip() == '':
        upload_name = None
    else:
        upload_name = upload_name.strip()
    if len(file_set) != 1:
        upload_name = None

    upload_job_id = str(uuid.uuid4())

    with _upload_jobs_condition:
        _cleanup_stale_upload_jobs_locked()
        _upload_jobs[upload_job_id] = {
            "created_at": time.time(),
            "updated_at": time.time(),
            "events": [],
            "is_complete": False,
            "total_files": len(file_set),
            "finished_files": 0
        }

    def worker(file_path: str):
        from objects.Video import Video

        def emit(state: str, percent: int, message: str, error: str = None, result: dict = None):
            payload = {
                "job_id": upload_job_id,
                "file_path": file_path,
                "state": state,
                "percent": max(0, min(100, int(percent))),
                "message": message
            }
            if error is not None:
                payload["error"] = error
            if result is not None:
                payload["result"] = result
            _append_upload_job_event(upload_job_id, payload)

        try:
            emit("uploading", 0, "Queued")
            video = Video(file_path, global_context)
            result = video.upload_to_youtube_sse(
                made_for_kids=made_for_kids,
                migrate_to_youtube=migrate_files,
                upload_name=upload_name,
                on_progress=lambda state, percent, message: emit(state, percent, message)
            )

            if result and result.get("overall_status"):
                emit("success", 100, "Upload complete", result=result)
            else:
                emit("error", 100, "Upload failed", error="Upload operation returned failure", result=result)
        except Exception as exc:
            emit("error", 100, "Upload failed", error=str(exc))
        finally:
            with _upload_jobs_condition:
                job_data = _upload_jobs.get(upload_job_id)
                if not job_data:
                    return

                job_data["finished_files"] += 1
                job_data["updated_at"] = time.time()
                if job_data["finished_files"] >= job_data["total_files"]:
                    job_data["is_complete"] = True
                    job_data["events"].append({
                        "job_id": upload_job_id,
                        "state": "complete",
                        "percent": 100,
                        "message": "All files finished",
                        "finished_files": job_data["finished_files"],
                        "total_files": job_data["total_files"]
                    })
                _upload_jobs_condition.notify_all()

    for file in file_set:
        _append_upload_job_event(upload_job_id, {
            "job_id": upload_job_id,
            "file_path": file,
            "state": "queued",
            "percent": 0,
            "message": "Queued for upload"
        })
        this_thread = threading.Thread(target=worker, args=(file,))
        this_thread.start()

    return jsonify({
        "job_id": upload_job_id,
        "total_files": len(file_set)
    })

@app.route('/api/migration/upload_status_stream')
def upload_status_stream():
    job_id = request.args.get('job_id')
    if not job_id:
        return jsonify({"error": "job_id is required"}), 400

    with _upload_jobs_lock:
        if job_id not in _upload_jobs:
            return jsonify({"error": f"Unknown job_id: {job_id}"}), 404

    def generate():
        next_index = 0
        while True:
            event_to_send = None
            with _upload_jobs_condition:
                while True:
                    job_data = _upload_jobs.get(job_id)
                    if not job_data:
                        event_to_send = {"job_id": job_id, "state": "error", "message": "Upload job no longer exists"}
                        break

                    if next_index < len(job_data["events"]):
                        event_to_send = job_data["events"][next_index]
                        next_index += 1
                        break

                    if job_data["is_complete"]:
                        return

                    _upload_jobs_condition.wait(timeout=15.0)

            if event_to_send is None:
                continue

            yield f"event: upload_status\ndata: {json.dumps(event_to_send)}\n\n"

    response = Response(stream_with_context(generate()), mimetype='text/event-stream')
    response.headers['Cache-Control'] = 'no-cache'
    response.headers['X-Accel-Buffering'] = 'no'
    return response

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