import json
import os
from datetime import datetime, timezone
from uuid import uuid4

from objects.action_factory import create_action_from_record
from services.folder_lock import FolderLock


class ActionHistoryService:
    def __init__(self, meta_dir_name=".video_reviewer", state_file_name="history.json"):
        self.meta_dir_name = meta_dir_name
        self.state_file_name = state_file_name

    def execute(self, action):
        folder_path = action.folder_path
        with FolderLock(folder_path, meta_dir_name=self.meta_dir_name):
            state = self._load_state(folder_path)
            self._truncate_redo_tail(state)

            result = action.apply()
            record = action.to_record()
            record["id"] = str(uuid4())
            record["created_at"] = datetime.now(timezone.utc).isoformat()

            state["actions"].append(record)
            state["cursor"] = len(state["actions"]) - 1
            self._save_state(folder_path, state)
            return result

    def undo(self, folder_path):
        normalized_folder = os.path.normpath(folder_path)
        with FolderLock(normalized_folder, meta_dir_name=self.meta_dir_name):
            state = self._load_state(normalized_folder)
            cursor = state.get("cursor", -1)
            actions = state.get("actions", [])
            if cursor < 0 or cursor >= len(actions):
                raise ValueError("No actions to undo for this folder")

            record = actions[cursor]
            action = create_action_from_record(record)
            result = action.undo()

            state["cursor"] = cursor - 1
            self._save_state(normalized_folder, state)
            return {
                "action_type": record.get("action_type"),
                **result,
            }

    def redo(self, folder_path):
        normalized_folder = os.path.normpath(folder_path)
        with FolderLock(normalized_folder, meta_dir_name=self.meta_dir_name):
            state = self._load_state(normalized_folder)
            cursor = state.get("cursor", -1)
            actions = state.get("actions", [])
            next_index = cursor + 1
            if next_index < 0 or next_index >= len(actions):
                raise ValueError("No actions to redo for this folder")

            record = actions[next_index]
            action = create_action_from_record(record)
            result = action.redo()

            state["cursor"] = next_index
            self._save_state(normalized_folder, state)
            return {
                "action_type": record.get("action_type"),
                **result,
            }

    def _truncate_redo_tail(self, state):
        cursor = state.get("cursor", -1)
        actions = state.get("actions", [])
        if cursor < len(actions) - 1:
            state["actions"] = actions[: cursor + 1]

    def _state_file_path(self, folder_path):
        meta_dir = os.path.join(folder_path, self.meta_dir_name)
        os.makedirs(meta_dir, exist_ok=True)
        return os.path.join(meta_dir, self.state_file_name)

    def _load_state(self, folder_path):
        path = self._state_file_path(folder_path)
        if not os.path.exists(path):
            return {"version": 1, "cursor": -1, "actions": []}

        with open(path, "r", encoding="utf-8") as file_handle:
            raw = json.load(file_handle)
        return {
            "version": raw.get("version", 1),
            "cursor": raw.get("cursor", -1),
            "actions": raw.get("actions", []),
        }

    def _save_state(self, folder_path, state):
        path = self._state_file_path(folder_path)
        temp_path = f"{path}.tmp"
        with open(temp_path, "w", encoding="utf-8") as file_handle:
            json.dump(state, file_handle, indent=2)
            file_handle.flush()
            os.fsync(file_handle.fileno())
        os.replace(temp_path, path)

