import os
import re
import time


def sanitize_filename(name):
    # Replace invalid Windows filename characters with '_'
    return re.sub(r'[<>:"/\\|?*\x00-\x1f]', '_', name)


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


def ensure_unique_path(path):
    if not os.path.exists(path):
        return path

    folder = os.path.dirname(path)
    name, ext = os.path.splitext(os.path.basename(path))
    index = 2
    while True:
        candidate = os.path.join(folder, f"{name} ({index}){ext}")
        if not os.path.exists(candidate):
            return candidate
        index += 1


def get_archive_dir(folder_path):
    archive_dir = os.path.join(folder_path, "TO_BE_DELETED")
    os.makedirs(archive_dir, exist_ok=True)
    return archive_dir

