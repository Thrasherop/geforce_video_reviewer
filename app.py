import os
import re
import subprocess
import shutil
import time
from flask import Flask, request, jsonify, send_file, render_template, abort, Response, stream_with_context

app = Flask(__name__, template_folder='templates', static_folder='static')

# Pattern to match ShadowPlay filenames like 'Game YYYY.MM.DD - hh.mm.ss.xx.DVR.mp4'
FILENAME_PATTERN = re.compile(r'.*\d{4}\.\d{2}\.\d{2} - \d{2}\.\d{2}\.\d{2}\.\d{2}\.DVR\.mp4$')

# Utility to sanitize filenames on Windows
def sanitize_filename(name):
    # Replace invalid Windows filename characters with '_'
    return re.sub(r'[<>:"/\\|?*\x00-\x1f]', '_', name)

# Utility: rename with retries to handle Windows file locks
def safe_rename(src, dst, retries=5, delay=0.1):
    for i in range(retries):
        try:
            os.rename(src, dst)
            return
        except PermissionError:
            if i < retries - 1:
                time.sleep(delay)
            else:
                raise

@app.route('/')
def index():
    return render_template('index.html')

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
    data = request.get_json()
    action_type = data.get('action')
    orig_path = data.get('path')
    if not action_type or not orig_path:
        return jsonify({'error': 'Missing action or path'}), 400
    orig_path = os.path.normpath(orig_path)
    if not os.path.isfile(orig_path):
        return jsonify({'error': f'File not found: {orig_path}'}), 404

    if action_type == 'keep':
        raw_name = data.get('new_name', '').strip()
        if not raw_name:
            return jsonify({'error': 'New name cannot be empty'}), 400
        # Sanitize user-provided name
        base = sanitize_filename(raw_name)
        dir_path = os.path.dirname(orig_path)
        ext = os.path.splitext(orig_path)[1]
        new_filename = f'{base}{ext}'
        new_path = os.path.join(dir_path, new_filename)
        i = 2
        while os.path.exists(new_path):
            new_filename = f'{base} ({i}){ext}'
            new_path = os.path.join(dir_path, new_filename)
            i += 1
        # Only rename if different path
        if os.path.abspath(new_path) != os.path.abspath(orig_path):
            try:
                safe_rename(orig_path, new_path)
            except Exception as e:
                return jsonify({'error': str(e)}), 500
        return jsonify({'success': True, 'new_path': new_path})

    elif action_type == 'trim':
        raw_name = data.get('new_name', '').strip()
        if not raw_name:
            return jsonify({'error': 'New name cannot be empty for trim'}), 400
        # Sanitize user-provided name
        base = sanitize_filename(raw_name)
        # Parse times
        start = data.get('start', '').strip()
        if not start:
            return jsonify({'error': 'Start time required for trim'}), 400
        end = data.get('end', '').strip()
        dir_path = os.path.dirname(orig_path)
        ext = os.path.splitext(orig_path)[1]
        orig_basename = os.path.basename(orig_path)
        new_basename = f'{base}{ext}'
        tbdd_dir = os.path.join(dir_path, 'TO_BE_DELETED')
        os.makedirs(tbdd_dir, exist_ok=True)
        # Determine final output path
        new_filename = new_basename
        new_path = os.path.join(dir_path, new_filename)
        i = 2
        while os.path.exists(new_path):
            new_filename = f'{base} ({i}){ext}'
            new_path = os.path.join(dir_path, new_filename)
            i += 1
        # Always use a temporary output file to avoid data loss on ffmpeg failure
        temp_output = os.path.join(dir_path, f'_temp_trim_{os.getpid()}_{base}{ext}')
        # Perform trim via ffmpeg; skip end if not provided
        # Using -ss before -i for fast seek
        # When -ss is before -i, -to is still in input time base (absolute timestamp)
        # Using -copyts preserves original timestamps, and -avoid_negative_ts make_zero 
        # shifts them to start from 0 in the output
        cmd = ['ffmpeg', '-ss', start, '-i', orig_path]
        if end:
            cmd += ['-to', end]
        cmd += ['-c', 'copy', '-copyts', '-avoid_negative_ts', 'make_zero', temp_output, '-y']
        try:
            subprocess.run(cmd, check=True)
        except subprocess.CalledProcessError as e:
            # Clean up temp file if it was created
            if os.path.exists(temp_output):
                try:
                    os.remove(temp_output)
                except Exception:
                    pass
            return jsonify({'error': f'FFmpeg error: {e}'}), 500
        # Copy timestamps from the source file
        try:
            shutil.copystat(orig_path, temp_output)
        except Exception:
            pass
        # Move temp file to final output path
        try:
            safe_rename(temp_output, new_path)
        except Exception as e:
            # Clean up temp file
            if os.path.exists(temp_output):
                try:
                    os.remove(temp_output)
                except Exception:
                    pass
            return jsonify({'error': f'Failed to move trimmed file: {e}'}), 500
        # Archive the original
        archived_name = f'{base}_archive_{orig_basename}'
        archived_path = os.path.join(tbdd_dir, archived_name)
        j = 2
        while os.path.exists(archived_path):
            archived_name = f'{base}_archive_{orig_basename} ({j})'
            archived_path = os.path.join(tbdd_dir, archived_name)
            j += 1
        try:
            safe_rename(orig_path, archived_path)
        except Exception as e:
            return jsonify({'error': f'Failed to archive original: {e}'}), 500
        return jsonify({'success': True, 'new_path': new_path})

    elif action_type == 'delete':
        dir_path = os.path.dirname(orig_path)
        tbdd_dir = os.path.join(dir_path, 'TO_BE_DELETED')
        os.makedirs(tbdd_dir, exist_ok=True)
        orig_name = os.path.basename(orig_path)
        orig_base = os.path.splitext(orig_name)[0]
        archived_name = f'{orig_base}_archive_{orig_name}'
        archived_path = os.path.join(tbdd_dir, archived_name)
        j = 2
        while os.path.exists(archived_path):
            archived_name = f'{orig_base}_archive_{orig_name} ({j})'
            archived_path = os.path.join(tbdd_dir, archived_name)
            j += 1
        try:
            safe_rename(orig_path, archived_path)
        except Exception as e:
            return jsonify({'error': str(e)}), 500
        return jsonify({'success': True})

    return jsonify({'error': f'Unsupported action: {action_type}'}), 400

if __name__ == '__main__':
    app.run(debug=True) 