## TOFIX Notes

This document captures the highest-impact bugs and flaws found during a quick
review. It is intended for an engineer to follow up and fix. Each item includes
impact, reproduction ideas, and suggested fixes.

### 1) Data loss on failed trim when renaming to same basename

**Impact**
- If the user trims a clip and keeps the same base name, the original file is
  moved to `TO_BE_DELETED` before ffmpeg runs.
- If ffmpeg fails, the original is already moved and no output is produced.
- Result: the original file is effectively lost from the main directory.

**Where**
- `app.py`, `/api/action`, `action_type == 'trim'` branch.

**Why it happens**
- The code archives the original first when `new_basename == orig_basename` to
  allow writing the trimmed output under the original name.
- On ffmpeg failure, there is no rollback to restore the archived original.

**How to reproduce**
- Use `Trim` with a start/end that triggers ffmpeg error (e.g., invalid time or
  missing ffmpeg binary).
- Keep the new name identical to the original base name.
- Observe original file moved to `TO_BE_DELETED` and no output created.

**Suggested fix**
- Run ffmpeg into a temporary output file first, then swap/rename on success.
- Or, if archiving first is required, add a rollback path that moves the
  archived file back on ffmpeg failure.

---

### 2) Unrestricted filesystem access via API paths

**Impact**
- Any caller with access to the app can list directories, stream files, rename,
  trim, or delete any file the server can access.
- High security risk if the app is ever exposed beyond a trusted local machine.

**Where**
- `app.py`: `/api/files`, `/api/video`, `/api/action`.

**Why it happens**
- Paths from the client are used directly with `os.path.normpath` and not
  constrained to a safe root.

**How to reproduce**
- Pass any absolute path to `/api/video` or `/api/action` and observe it works.

**Suggested fix**
- Restrict access to a configured base directory (whitelist root).
- Enforce that requested paths are within that root after normalization.
- Consider a server-side mapping rather than direct client paths.

---

### 3) Invalid Range header handling can produce negative Content-Length

**Impact**
- A request like `Range: bytes=100-50` yields `length = -49` and invalid headers.
- Some clients may error or fail to play the video.

**Where**
- `app.py`, `/api/video`, range parsing logic.

**Why it happens**
- No validation that `end >= start`.

**How to reproduce**
- Request `/api/video` with `Range: bytes=100-50`.
- Observe headers or client failures.

**Suggested fix**
- Validate range ordering; if `end < start`, return 416 or normalize the range.

---

### 4) Delete action lacks error handling for failed rename

**Impact**
- On `PermissionError` or other rename failures, a 500 error can be raised and
  the response may not be JSON. UI can appear broken or silent.

**Where**
- `app.py`, `/api/action`, `action_type == 'delete'`.

**Why it happens**
- `safe_rename` is not wrapped in try/except here (unlike `keep` and `trim`).

**How to reproduce**
- Attempt to delete a file that is open/locked by another process.

**Suggested fix**
- Wrap `safe_rename` in try/except and return a JSON error.

---

### 5) Frontend clears video source before action and never restores on error

**Impact**
- After a failed save/trim/delete, the player stays blank until the user
  manually navigates to another file.

**Where**
- `static/app.js`: `saveRename`, `trimClip`, `deleteClip`.

**Why it happens**
- `videoPlayer.removeAttribute('src')` is called before the fetch, but errors
  only show an alert and do not reload the current file.

**How to reproduce**
- Trigger a failure (e.g., invalid trim time or server error).
- Video stays blank after the alert.

**Suggested fix**
- On error, reload the current file or restore the previous `src`.

