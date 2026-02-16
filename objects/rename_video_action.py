import os

from .file_ops import ensure_unique_path, safe_rename, sanitize_filename
from .user_action import UserAction


class RenameVideoAction(UserAction):
    action_type = "rename"

    def __init__(self, old_path, new_name, new_path=None):
        super().__init__(os.path.dirname(old_path))
        self.old_path = os.path.normpath(old_path)
        self.new_name = new_name.strip()
        self.new_path = os.path.normpath(new_path) if new_path else None

    def _resolve_new_path(self):
        if self.new_path:
            return self.new_path

        if not self.new_name:
            raise ValueError("New name cannot be empty")

        base = sanitize_filename(self.new_name)
        ext = os.path.splitext(self.old_path)[1]
        desired_path = os.path.join(self.folder_path, f"{base}{ext}")
        self.new_path = os.path.normpath(ensure_unique_path(desired_path))
        return self.new_path

    def apply(self):
        if not os.path.isfile(self.old_path):
            raise FileNotFoundError(f"File not found: {self.old_path}")

        target_path = self._resolve_new_path()
        if os.path.abspath(target_path) == os.path.abspath(self.old_path):
            return {"new_path": target_path, "current_path": target_path}

        if os.path.exists(target_path):
            raise FileExistsError(f"Destination already exists: {target_path}")

        safe_rename(self.old_path, target_path)
        return {"new_path": target_path, "current_path": target_path}

    def undo(self):
        target_path = self._resolve_new_path()
        if os.path.abspath(target_path) == os.path.abspath(self.old_path):
            return {"current_path": self.old_path}

        if not os.path.isfile(target_path):
            raise FileNotFoundError(f"Renamed file not found: {target_path}")

        if os.path.exists(self.old_path):
            raise FileExistsError(f"Original path already exists: {self.old_path}")

        safe_rename(target_path, self.old_path)
        return {"current_path": self.old_path}

    def to_record(self):
        return {
            "action_type": self.action_type,
            "folder_path": self.folder_path,
            "payload": {
                "old_path": self.old_path,
                "new_name": self.new_name,
                "new_path": self.new_path,
            },
        }

    @classmethod
    def from_record(cls, record):
        payload = record.get("payload", {})
        return cls(
            old_path=payload.get("old_path", ""),
            new_name=payload.get("new_name", ""),
            new_path=payload.get("new_path"),
        )

