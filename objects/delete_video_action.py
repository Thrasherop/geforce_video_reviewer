import os

from .file_ops import ensure_unique_path, get_archive_dir, safe_rename
from .user_action import UserAction


class DeleteVideoAction(UserAction):
    action_type = "delete"

    def __init__(self, original_path, archived_path=None):
        super().__init__(os.path.dirname(original_path))
        self.original_path = os.path.normpath(original_path)
        self.archived_path = os.path.normpath(archived_path) if archived_path else None

    def _resolve_archived_path(self):
        if self.archived_path:
            return self.archived_path

        archive_dir = get_archive_dir(self.folder_path)
        original_name = os.path.basename(self.original_path)
        original_base = os.path.splitext(original_name)[0]
        default_name = f"{original_base}_archive_{original_name}"
        self.archived_path = os.path.normpath(
            ensure_unique_path(os.path.join(archive_dir, default_name))
        )
        return self.archived_path

    def apply(self):
        if not os.path.isfile(self.original_path):
            raise FileNotFoundError(f"File not found: {self.original_path}")

        archived_path = self._resolve_archived_path()
        if os.path.exists(archived_path):
            raise FileExistsError(f"Archive destination already exists: {archived_path}")

        safe_rename(self.original_path, archived_path)
        return {"archived_path": archived_path}

    def undo(self):
        archived_path = self._resolve_archived_path()
        if not os.path.isfile(archived_path):
            raise FileNotFoundError(f"Archived file not found: {archived_path}")

        if os.path.exists(self.original_path):
            raise FileExistsError(f"Original path already exists: {self.original_path}")

        safe_rename(archived_path, self.original_path)
        return {"current_path": self.original_path}

    def to_record(self):
        return {
            "action_type": self.action_type,
            "folder_path": self.folder_path,
            "payload": {
                "original_path": self.original_path,
                "archived_path": self.archived_path,
            },
        }

    @classmethod
    def from_record(cls, record):
        payload = record.get("payload", {})
        return cls(
            original_path=payload.get("original_path", ""),
            archived_path=payload.get("archived_path"),
        )

