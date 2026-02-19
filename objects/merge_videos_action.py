import os
import shutil
import subprocess
import tempfile
import time

from .file_ops import ensure_unique_path, get_archive_dir, safe_rename, sanitize_filename
from .user_action import UserAction


class MergeVideosAction(UserAction):
    action_type = "merge"

    def __init__(
        self,
        primary_path,
        paths,
        new_name,
        archive_originals=False,
        merged_path=None,
        archived_paths=None,
    ):
        super().__init__(os.path.dirname(primary_path))
        normalized_paths = [os.path.normpath(str(path)) for path in (paths or []) if str(path).strip()]
        self.primary_path = os.path.normpath(primary_path)
        self.paths = normalized_paths
        self.new_name = str(new_name or "").strip()
        self.archive_originals = bool(archive_originals)
        self.merged_path = os.path.normpath(merged_path) if merged_path else None
        self.archived_paths = (
            [os.path.normpath(path) for path in archived_paths]
            if isinstance(archived_paths, list)
            else None
        )

    def _validate_inputs(self):
        if len(self.paths) < 2:
            raise ValueError("Select at least 2 clips to merge")
        if len(self.paths) > 3:
            raise ValueError("You can merge up to 3 clips")
        if len(set(self.paths)) != len(self.paths):
            raise ValueError("Duplicate clips cannot be merged")
        if not self.new_name:
            raise ValueError("Merged file name cannot be empty")

        folder_paths = {os.path.normpath(os.path.dirname(path)) for path in self.paths}
        if len(folder_paths) != 1:
            raise ValueError("All clips to merge must be in the same folder")
        self.folder_path = folder_paths.pop()

    def _resolve_merged_path(self):
        if self.merged_path:
            return self.merged_path

        ext = os.path.splitext(self.paths[0])[1]
        base = sanitize_filename(self.new_name)
        desired_path = os.path.join(self.folder_path, f"{base}{ext}")
        self.merged_path = os.path.normpath(ensure_unique_path(desired_path))
        return self.merged_path

    def _resolve_archived_paths(self):
        if not self.archive_originals:
            return []

        if self.archived_paths is not None:
            return self.archived_paths

        archive_dir = get_archive_dir(self.folder_path)
        merged_base = sanitize_filename(self.new_name)
        resolved_paths = []
        for source_path in self.paths:
            source_name = os.path.basename(source_path)
            archived_name = f"{merged_base}_archive_{source_name}"
            resolved_paths.append(
                os.path.normpath(
                    ensure_unique_path(os.path.join(archive_dir, archived_name))
                )
            )
        self.archived_paths = resolved_paths
        return self.archived_paths

    def _build_temp_output_path(self):
        ext = os.path.splitext(self.paths[0])[1]
        safe_name = sanitize_filename(self.new_name) or "merge"
        temp_name = f"_temp_merge_{os.getpid()}_{int(time.time() * 1000)}_{safe_name}{ext}"
        return os.path.join(self.folder_path, temp_name)

    def _write_concat_file(self):
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            suffix=".txt",
            prefix="_merge_concat_",
            dir=self.folder_path,
            delete=False,
        ) as concat_file:
            for source_path in self.paths:
                escaped = source_path.replace("'", "'\\''")
                concat_file.write(f"file '{escaped}'\n")
            return concat_file.name

    def apply(self):
        self._validate_inputs()
        for source_path in self.paths:
            if not os.path.isfile(source_path):
                raise FileNotFoundError(f"File not found: {source_path}")

        merged_path = self._resolve_merged_path()
        archived_paths = self._resolve_archived_paths()

        if os.path.exists(merged_path):
            raise FileExistsError(f"Merge destination already exists: {merged_path}")
        for archived_path in archived_paths:
            if os.path.exists(archived_path):
                raise FileExistsError(f"Archive destination already exists: {archived_path}")

        temp_output = self._build_temp_output_path()
        concat_file = ""
        moved_pairs = []
        try:
            concat_file = self._write_concat_file()
            cmd = [
                "ffmpeg",
                "-hide_banner",
                "-loglevel",
                "error",
                "-f",
                "concat",
                "-safe",
                "0",
                "-i",
                concat_file,
                "-c",
                "copy",
                temp_output,
                "-y",
            ]
            subprocess.run(cmd, check=True)
            try:
                shutil.copystat(self.paths[0], temp_output)
            except Exception:
                pass
            safe_rename(temp_output, merged_path)

            if self.archive_originals:
                for source_path, archived_path in zip(self.paths, archived_paths):
                    safe_rename(source_path, archived_path)
                    moved_pairs.append((source_path, archived_path))
        except subprocess.CalledProcessError as exc:
            if os.path.exists(temp_output):
                try:
                    os.remove(temp_output)
                except Exception:
                    pass
            raise RuntimeError(f"FFmpeg error: {exc}") from exc
        except Exception:
            if os.path.exists(temp_output):
                try:
                    os.remove(temp_output)
                except Exception:
                    pass
            for source_path, archived_path in reversed(moved_pairs):
                if os.path.exists(archived_path) and not os.path.exists(source_path):
                    try:
                        safe_rename(archived_path, source_path)
                    except Exception:
                        pass
            if os.path.exists(merged_path):
                try:
                    os.remove(merged_path)
                except Exception:
                    pass
            raise
        finally:
            if concat_file and os.path.exists(concat_file):
                try:
                    os.remove(concat_file)
                except Exception:
                    pass

        return {"new_path": merged_path, "current_path": merged_path}

    def undo(self):
        merged_path = self._resolve_merged_path()
        if not os.path.isfile(merged_path):
            raise FileNotFoundError(f"Merged output not found: {merged_path}")

        archived_merged_path = None
        archive_dir = get_archive_dir(self.folder_path)
        merged_name = os.path.basename(merged_path)
        archived_name = f"undo_archive_{merged_name}"
        archived_merged_path = os.path.normpath(
            ensure_unique_path(os.path.join(archive_dir, archived_name))
        )
        safe_rename(merged_path, archived_merged_path)

        if self.archive_originals:
            archived_paths = self._resolve_archived_paths()
            for source_path, archived_path in zip(self.paths, archived_paths):
                if not os.path.isfile(archived_path):
                    raise FileNotFoundError(f"Archived original not found: {archived_path}")
                if os.path.exists(source_path):
                    raise FileExistsError(f"Original path already exists: {source_path}")
            for source_path, archived_path in zip(self.paths, archived_paths):
                safe_rename(archived_path, source_path)

        current_path = self.paths[0] if self.paths else self.primary_path
        return {
            "current_path": current_path,
            "merged_archived_path": archived_merged_path,
        }

    def to_record(self):
        return {
            "action_type": self.action_type,
            "folder_path": self.folder_path,
            "payload": {
                "primary_path": self.primary_path,
                "paths": self.paths,
                "new_name": self.new_name,
                "archive_originals": self.archive_originals,
                "merged_path": self.merged_path,
                "archived_paths": self.archived_paths,
            },
        }

    @classmethod
    def from_record(cls, record):
        payload = record.get("payload", {})
        return cls(
            primary_path=payload.get("primary_path", ""),
            paths=payload.get("paths", []),
            new_name=payload.get("new_name", ""),
            archive_originals=payload.get("archive_originals", False),
            merged_path=payload.get("merged_path"),
            archived_paths=payload.get("archived_paths"),
        )
