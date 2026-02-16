from .delete_video_action import DeleteVideoAction
from .rename_video_action import RenameVideoAction
from .trim_video_action import TrimVideoAction


ACTION_CLASSES = {
    "rename": RenameVideoAction,
    "trim": TrimVideoAction,
    "delete": DeleteVideoAction,
}


def create_action_from_request(action_type, data):
    normalized_type = str(action_type or "").strip().lower()
    path = data.get("path")
    if not normalized_type or not path:
        raise ValueError("Missing action or path")

    if normalized_type == "rename":
        return RenameVideoAction(
            old_path=path,
            new_name=data.get("new_name", ""),
        )

    if normalized_type == "trim":
        return TrimVideoAction(
            original_path=path,
            new_name=data.get("new_name", ""),
            start=data.get("start", ""),
            end=data.get("end", ""),
        )

    if normalized_type == "delete":
        return DeleteVideoAction(
            original_path=path,
        )

    raise ValueError(f"Unsupported action: {normalized_type}")


def create_action_from_record(record):
    action_type = record.get("action_type")
    action_cls = ACTION_CLASSES.get(action_type)
    if not action_cls:
        raise ValueError(f"Unsupported action type in history: {action_type}")
    return action_cls.from_record(record)

