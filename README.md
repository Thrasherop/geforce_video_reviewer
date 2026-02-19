# Video Reviewer (ShadowPlay Reviewer)

A lightweight Flask app for reviewing MP4 clips, quickly renaming/trimming/deleting them, and undoing or redoing actions per folder.

## What It Does

- Loads videos from a folder and sorts them newest-first.
- Filters to ShadowPlay-style filenames by default, with an option to include all `.mp4` files.
- Plays clips in-browser with keyboard controls.
- Supports three actions:
  - Rename a clip
  - Trim a clip using FFmpeg stream copy
  - "Delete" a clip by moving it to an archive folder
- Tracks action history per folder so you can undo/redo changes.

## Future Improvements
- Configuration screen (maybe settings icon?) that lets a user change: keybinds, time skip amounts, default start %, whether or not to confirm before delete
- Merge 2 clips together 
- Integrate with youtube clip migration
- Upgrade UX
  - Needs to be able to merge clips, edit clips, migrate clips, etc. 
  - Maybe have a seperate tab like UX, where you can swap between modes
- Add meaningful errors for the FE
- Enable browsing of youtube clips locally

## Tech Stack

- Python + Flask backend
- Vanilla HTML/CSS/JavaScript frontend
- FFmpeg for trimming

## Requirements

- Python 3.10+ (recommended)
- FFmpeg available on your `PATH`
- Windows PowerShell (project includes a helper script for Windows)

## Install

From the project root:

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

## Run

### Option 1: Helper script (opens Chrome + starts app)

```powershell
.\start_video_review.ps1
```

### Option 2: Manual

```powershell
.\.venv\Scripts\Activate.ps1
python app.py
```

Then open:

- `http://127.0.0.1:5000`

## How To Use

1. Enter a directory in **Enter directory to review**.
2. (Optional) Enable **Include Reviewed** to include all `.mp4` files.
3. Click **Load**.
4. Use the action controls:
   - **Just Save rename**
   - **Trim**
   - **Delete**
5. Use **Previous/Next** or jump to an index.
6. Use undo/redo hotkeys if needed.

## Hotkeys

- `k` -> toggle play/pause
- `j` -> rewind 10 seconds
- `l` -> forward 3 seconds
- `Delete` -> delete current clip (moves to archive)
- `Ctrl+Z` -> undo last action (for current folder)
- `Ctrl+Shift+Z` -> redo

Hotkeys are disabled while typing in an input field.

## File and History Behavior

- "Delete" does not permanently remove files immediately.
  - Files are moved into a `TO_BE_DELETED` folder inside the reviewed directory.
- Trim operations:
  - Create a trimmed output file in the current folder.
  - Move the original to `TO_BE_DELETED`.
- Undo/redo state is stored per folder in:
  - `.video_reviewer/history.json`
- A lock file is used to prevent concurrent history corruption:
  - `.video_reviewer/history.lock`

## API Endpoints

- `GET /` -> UI page
- `GET /api/files?dir=<path>&include_reviewed=<bool>` -> list files
- `GET /api/video?path=<file>` -> stream video (supports Range requests)
- `GET /api/thumbnail?path=<file>` -> generate and return a video thumbnail image
- `POST /api/action` -> perform `rename`, `trim`, or `delete`
- `POST /api/undo` -> undo last action for a folder
- `POST /api/redo` -> redo action for a folder

Example action payload:

```json
{
  "action": "trim",
  "path": "C:/clips/Game 2026.02.16 - 21.30.10.55.DVR.mp4",
  "new_name": "nice_play",
  "start": "00:10.000",
  "end": "00:25.000"
}
```

## Project Structure

- `app.py` - Flask routes and API layer
- `templates/index.html` - App UI
- `static/app.js` - Frontend behavior and hotkeys
- `objects/` - Action classes (`rename`, `trim`, `delete`) and shared file ops
- `services/action_history_service.py` - undo/redo persistence
- `services/folder_lock.py` - per-folder file lock
- `start_video_review.ps1` - convenience startup script

## Notes

- Trimming uses FFmpeg copy mode for speed (`-c copy`) and may depend on keyframe boundaries.
- If FFmpeg is not installed or not on `PATH`, trim requests will fail.
