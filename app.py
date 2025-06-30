import os
import re
import subprocess
from flask import Flask, request, jsonify, send_file, render_template, abort

app = Flask(__name__, template_folder='templates', static_folder='static')

# Pattern to match ShadowPlay filenames like 'Game YYYY.MM.DD - hh.mm.ss.xx.DVR.mp4'
FILENAME_PATTERN = re.compile(r'.*\d{4}\.\d{2}\.\d{2} - \d{2}\.\d{2}\.\d{2}\.\d{2}\.DVR\.mp4$')

# Utility to sanitize filenames on Windows
def sanitize_filename(name):
    # Replace invalid Windows filename characters with '_'
    return re.sub(r'[<>:"/\\|?*\x00-\x1f]', '_', name)

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
    # Collect files with their modification times for sorting (newest first)
    entries = []
    for entry in os.scandir(dir_path):
        if entry.is_file() and FILENAME_PATTERN.match(entry.name):
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
                os.rename(orig_path, new_path)
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
        new_filename = f'{base}{ext}'
        new_path = os.path.join(dir_path, new_filename)
        i = 2
        while os.path.exists(new_path):
            new_filename = f'{base} ({i}){ext}'
            new_path = os.path.join(dir_path, new_filename)
            i += 1
        # Perform trim via ffmpeg; skip end if not provided
        cmd = ['ffmpeg', '-i', orig_path, '-ss', start]
        if end:
            cmd += ['-to', end]
        cmd += ['-c', 'copy', new_path, '-y']
        try:
            subprocess.run(cmd, check=True)
        except subprocess.CalledProcessError as e:
            return jsonify({'error': f'FFmpeg error: {e}'}), 500
        # Archive original file
        tbdd_dir = os.path.join(dir_path, 'TO_BE_DELETED')
        os.makedirs(tbdd_dir, exist_ok=True)
        orig_name = os.path.basename(orig_path)
        archived_name = f'{base}_archive_{orig_name}'
        archived_path = os.path.join(tbdd_dir, archived_name)
        j = 2
        while os.path.exists(archived_path):
            archived_name = f'{base}_archive_{orig_name} ({j})'
            archived_path = os.path.join(tbdd_dir, archived_name)
            j += 1
        os.rename(orig_path, archived_path)
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
        os.rename(orig_path, archived_path)
        return jsonify({'success': True})

    return jsonify({'error': f'Unsupported action: {action_type}'}), 400

if __name__ == '__main__':
    app.run(debug=True) 