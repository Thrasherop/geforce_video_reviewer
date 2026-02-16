import os
import time


class FolderLock:
    def __init__(self, folder_path, meta_dir_name=".video_reviewer", timeout_seconds=10.0):
        self.folder_path = os.path.normpath(folder_path)
        self.meta_dir_name = meta_dir_name
        self.timeout_seconds = timeout_seconds
        self.lock_file_handle = None

    def __enter__(self):
        meta_dir = os.path.join(self.folder_path, self.meta_dir_name)
        os.makedirs(meta_dir, exist_ok=True)
        lock_path = os.path.join(meta_dir, "history.lock")
        self.lock_file_handle = open(lock_path, "a+")
        self.lock_file_handle.seek(0)
        if self.lock_file_handle.read(1) == "":
            self.lock_file_handle.seek(0)
            self.lock_file_handle.write("0")
            self.lock_file_handle.flush()
        self.lock_file_handle.seek(0)
        self._acquire()
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        self._release()
        if self.lock_file_handle:
            self.lock_file_handle.close()
            self.lock_file_handle = None

    def _acquire(self):
        started = time.time()
        if os.name == "nt":
            import msvcrt

            while True:
                try:
                    self.lock_file_handle.seek(0)
                    msvcrt.locking(self.lock_file_handle.fileno(), msvcrt.LK_NBLCK, 1)
                    return
                except OSError:
                    if time.time() - started >= self.timeout_seconds:
                        raise TimeoutError("Timed out waiting for folder lock")
                    time.sleep(0.05)
        else:
            import fcntl

            while True:
                try:
                    fcntl.flock(self.lock_file_handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                    return
                except BlockingIOError:
                    if time.time() - started >= self.timeout_seconds:
                        raise TimeoutError("Timed out waiting for folder lock")
                    time.sleep(0.05)

    def _release(self):
        if not self.lock_file_handle:
            return

        if os.name == "nt":
            import msvcrt

            self.lock_file_handle.seek(0)
            msvcrt.locking(self.lock_file_handle.fileno(), msvcrt.LK_UNLCK, 1)
        else:
            import fcntl

            fcntl.flock(self.lock_file_handle.fileno(), fcntl.LOCK_UN)

