import os
import shutil
import subprocess
import time

from .file_ops import ensure_unique_path, get_archive_dir, safe_rename, sanitize_filename
from .user_action import UserAction


class TrimVideoAction(UserAction):
    action_type = "trim"

    def __init__(
        self,
        original_path,
        new_name,
        start,
        end="",
        trimmed_path=None,
        archived_original_path=None,
    ):
        super().__init__(os.path.dirname(original_path))
        self.original_path = os.path.normpath(original_path)
        self.new_name = new_name.strip()
        self.start = str(start).strip()
        self.end = str(end).strip()
        self.trimmed_path = os.path.normpath(trimmed_path) if trimmed_path else None
        self.archived_original_path = (
            os.path.normpath(archived_original_path) if archived_original_path else None
        )

    def _validate_inputs(self):
        if not self.new_name:
            raise ValueError("New name cannot be empty for trim")
        if not self.start:
            raise ValueError("Start time required for trim")

    def _resolve_trimmed_path(self):
        if self.trimmed_path:
            return self.trimmed_path

        base = sanitize_filename(self.new_name)
        ext = os.path.splitext(self.original_path)[1]
        desired_path = os.path.join(self.folder_path, f"{base}{ext}")
        self.trimmed_path = os.path.normpath(ensure_unique_path(desired_path))
        return self.trimmed_path

    def _resolve_archived_original_path(self):
        if self.archived_original_path:
            return self.archived_original_path

        base = sanitize_filename(self.new_name)
        archive_dir = get_archive_dir(self.folder_path)
        original_basename = os.path.basename(self.original_path)
        archived_name = f"{base}_archive_{original_basename}"
        self.archived_original_path = os.path.normpath(
            ensure_unique_path(os.path.join(archive_dir, archived_name))
        )
        return self.archived_original_path

    def _build_temp_output_path(self):
        ext = os.path.splitext(self.original_path)[1]
        safe_name = sanitize_filename(self.new_name) or "trim"
        temp_name = f"_temp_trim_{os.getpid()}_{int(time.time() * 1000)}_{safe_name}{ext}"
        return os.path.join(self.folder_path, temp_name)

    def apply(self):
        self._validate_inputs()
        if not os.path.isfile(self.original_path):
            raise FileNotFoundError(f"File not found: {self.original_path}")

        trimmed_path = self._resolve_trimmed_path()
        archived_original_path = self._resolve_archived_original_path()
        if os.path.exists(trimmed_path):
            raise FileExistsError(f"Trim destination already exists: {trimmed_path}")
        if os.path.exists(archived_original_path):
            raise FileExistsError(f"Archive destination already exists: {archived_original_path}")

        temp_output = self._build_temp_output_path()
        cmd = ["ffmpeg", "-ss", self.start, "-i", self.original_path]
        if self.end:
            cmd += ["-to", self.end]
        cmd += ["-c", "copy", "-copyts", "-avoid_negative_ts", "make_zero", temp_output, "-y"]

        try:
            subprocess.run(cmd, check=True)
            try:
                shutil.copystat(self.original_path, temp_output)
            except Exception:
                pass
            safe_rename(temp_output, trimmed_path)
            safe_rename(self.original_path, archived_original_path)
        except subprocess.CalledProcessError as exc:
            if os.path.exists(temp_output):
                try:
                    os.remove(temp_output)
                except Exception:
                    pass
            raise RuntimeError(f"FFmpeg error: {exc}") from exc
        except Exception:
            # Best-effort cleanup to avoid partial state if archive rename fails after trim output creation.
            if os.path.exists(temp_output):
                try:
                    os.remove(temp_output)
                except Exception:
                    pass
            if os.path.exists(trimmed_path):
                try:
                    os.remove(trimmed_path)
                except Exception:
                    pass
            raise

        return {"new_path": trimmed_path, "current_path": trimmed_path}

    def undo(self):
        archived_original_path = self._resolve_archived_original_path()
        if not os.path.isfile(archived_original_path):
            raise FileNotFoundError(f"Archived original not found: {archived_original_path}")

        if os.path.exists(self.original_path):
            raise FileExistsError(f"Original path already exists: {self.original_path}")

        trimmed_archive_path = None
        if self.trimmed_path and os.path.exists(self.trimmed_path):
            archive_dir = get_archive_dir(self.folder_path)
            trimmed_name = os.path.basename(self.trimmed_path)
            trimmed_archive_name = f"undo_archive_{trimmed_name}"
            trimmed_archive_path = os.path.normpath(
                ensure_unique_path(os.path.join(archive_dir, trimmed_archive_name))
            )
            safe_rename(self.trimmed_path, trimmed_archive_path)

        safe_rename(archived_original_path, self.original_path)
        return {
            "current_path": self.original_path,
            "trimmed_archived_path": trimmed_archive_path,
        }

    def to_record(self):
        return {
            "action_type": self.action_type,
            "folder_path": self.folder_path,
            "payload": {
                "original_path": self.original_path,
                "new_name": self.new_name,
                "start": self.start,
                "end": self.end,
                "trimmed_path": self.trimmed_path,
                "archived_original_path": self.archived_original_path,
            },
        }

    @classmethod
    def from_record(cls, record):
        payload = record.get("payload", {})
        return cls(
            original_path=payload.get("original_path", ""),
            new_name=payload.get("new_name", ""),
            start=payload.get("start", ""),
            end=payload.get("end", ""),
            trimmed_path=payload.get("trimmed_path"),
            archived_original_path=payload.get("archived_original_path"),
        )

