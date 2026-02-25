import json
import os
import threading
from pathlib import Path
from typing import Optional, List, Dict, Any, Union, TYPE_CHECKING
from filelock import FileLock

from objects.Video import Video
from config.config import * 
if TYPE_CHECKING:
    from objects.Context import Context

class _DirectoryRecord:

    # A single instance of a directory's record

    """

    json stored as such:

    {
        "directory" : "path/to/directory",
        "count" : int,
        "processed" : [
            {json of an individual Video document},
        ]
    }

    """

    def __init__(self, path : Path) -> None:

        # check for an existing directory record
        # if there is one, load it and lock the file
        # if there isn't, create a new one using DIRECTORY_RECORD_NAME
        # from directory_record_config

        # Save/Create Path objects
        self.directory_path = path
        self.record_file = path / DIRECTORY_RECORD_NAME # Path overloads the / operator to make path construction more intuitive and readable
        self.lock_file = path / f"{DIRECTORY_RECORD_NAME}.lock"
        self.lock = FileLock(self.lock_file, timeout=10)

        # Lock during initialization to prevent race conditions
        with self.lock:
            if self.record_file.exists():
                # load record file
                self.__load_record_file()
            else:
                # Initialize record file
                self.directory = str(path)
                self.count = 0
                self.processed = []
                # Save initial structure
                self.__save_unlocked()
        

    def __load_record_file(self):
        """ Load existing record """
        with open(self.record_file, 'r') as f:
            data = json.load(f)
            self.directory = data.get("directory", str(self.directory_path))
            self.count = data.get("count", 0)
            self.processed = data.get("processed", [])
        

    def add_processed_video(self, video_data: Video) -> None:
        """
        Atomically add a video to the processed list.
        Uses read-modify-write pattern to prevent data loss.
        
        Args:
            video_data: Video object to add
        """
        with self.lock:
            # Reload latest data from file to prevent desync
            if self.record_file.exists():
                self.__load_record_file()
            
            # Check if video_guid already exists (prevent duplicates)
            video_dict = video_data.to_dict()
            existing_guids = [v.get('video_guid') for v in self.processed]
            
            if video_dict['video_guid'] not in existing_guids:
                # Add new video
                self.processed.append(video_dict)
                self.count = len(self.processed)
                
                # Save immediately
                self.__save_unlocked()
    
    def update_processed_video(self, video_data: Video) -> bool:
        """
        Atomically update an existing video in the processed list based on video_guid.
        Uses read-modify-write pattern to prevent data loss.
        
        Args:
            video_data: Video object with updated data
            
        Returns:
            True if video was found and updated, False if not found
        """
        with self.lock:
            # Reload latest data from file to prevent desync
            if self.record_file.exists():
                self.__load_record_file()
            
            # Find and update video by video_guid
            video_dict = video_data.to_dict()
            video_guid = video_dict['video_guid']
            
            for i, existing_video in enumerate(self.processed):
                if existing_video.get('video_guid') == video_guid:
                    # Update the existing entry
                    self.processed[i] = video_dict
                    
                    # Save immediately
                    self.__save_unlocked()
                    return True
            
            # Video not found
            return False
    
    def get_video_dict_by_guid(self, video_guid: str) -> Optional[dict]:
        """
        Retrieve a video from the processed list by its GUID.
        
        Args:
            video_guid: The unique identifier for the video
            
        Returns:
            dict object if found, None otherwise
        """
        with self.lock:
            # Reload to get latest data
            if self.record_file.exists():
                self.__load_record_file()
            
            for video in self.processed:
                if video.get('video_guid') == video_guid:
                    return video # YouTubeUpload.from_json(video)
            
            return None
    
    def get_video_dict_by_path(self, video_path: Union[str, Path]) -> Optional[dict]:
        """
        Retrieve a video from the processed list by its original file path.
        
        Args:
            video_path: The original path for the target video
            
        Returns:
            dict object if found, None otherwise
        """
        with self.lock:
            # Reload to get latest data
            if self.record_file.exists():
                self.__load_record_file()
            
            target_path = self._normalize_path(video_path)
            matches: List[dict] = []
            for video in self.processed:
                existing_path = video.get('original_path')
                if existing_path is None:
                    continue
                if self._normalize_path(existing_path) == target_path:
                    matches.append(video)
            
            if not matches:
                return None
            
            # Prefer an uploaded entry when duplicate path records exist.
            for video in matches:
                youtube_url = video.get('youtube_url')
                if isinstance(youtube_url, str) and youtube_url.strip() != "":
                    return video
            
            return matches[0]
    
    def set_keep_local_by_guid(self, video_guid: str, keep_local: bool) -> bool:
        """
        Set keep_local flag for a tracked video.
        
        Args:
            video_guid: The unique identifier for the video
            keep_local: Desired keep_local value
            
        Returns:
            True if video was found and updated, False otherwise
        """
        with self.lock:
            # Reload to get latest data
            if self.record_file.exists():
                self.__load_record_file()
            
            for video in self.processed:
                if video.get('video_guid') == video_guid:
                    video['keep_local'] = bool(keep_local)
                    self.__save_unlocked()
                    return True
            
            return False
    
    def get_keep_local_by_guid(self, video_guid: str) -> Optional[bool]:
        """
        Get keep_local flag for a tracked video.
        
        Args:
            video_guid: The unique identifier for the video
            
        Returns:
            keep_local value if video exists, None otherwise
        """
        with self.lock:
            # Reload to get latest data
            if self.record_file.exists():
                self.__load_record_file()
            
            for video in self.processed:
                if video.get('video_guid') == video_guid:
                    return bool(video.get('keep_local', False))
            
            return None
    
    def _normalize_path(self, path: Union[str, Path]) -> str:
        """Normalize path for robust string comparison."""
        path_obj = path if type(path) == Path else Path(path)
        return os.path.normcase(os.path.normpath(str(path_obj.resolve())))
    
    def set_keep_local_by_path(self, video_path: Union[str, Path], keep_local: bool) -> bool:
        """
        Set keep_local flag for a tracked video using original_path matching.
        
        Args:
            video_path: The path to the target video
            keep_local: Desired keep_local value
            
        Returns:
            True if video was found and updated, False otherwise
        """
        with self.lock:
            # Reload to get latest data
            if self.record_file.exists():
                self.__load_record_file()
            
            target_path = self._normalize_path(video_path)
            for video in self.processed:
                existing_path = video.get('original_path')
                if existing_path is None:
                    continue
                if self._normalize_path(existing_path) == target_path:
                    video['keep_local'] = bool(keep_local)
                    self.__save_unlocked()
                    return True
            return False
    
    def get_keep_local_by_path(self, video_path: Union[str, Path]) -> Optional[bool]:
        """
        Get keep_local flag for a tracked video using original_path matching.
        
        Args:
            video_path: The path to the target video
            
        Returns:
            keep_local value if video exists, None otherwise
        """
        with self.lock:
            # Reload to get latest data
            if self.record_file.exists():
                self.__load_record_file()
            
            target_path = self._normalize_path(video_path)
            for video in self.processed:
                existing_path = video.get('original_path')
                if existing_path is None:
                    continue
                if self._normalize_path(existing_path) == target_path:
                    return bool(video.get('keep_local', False))
            
            return None
    
    def _save(self):
        """Save the current record to the JSON file with file locking"""
        with self.lock:
            self.__save_unlocked()
    
    def __save_unlocked(self):
        """Internal save method without locking (use when lock is already acquired)"""
        data = {
            "directory": self.directory,
            "count": self.count,
            "processed": self.processed
        }
        with open(self.record_file, 'w') as f:
            json.dump(data, f, indent=4)



class DirectoryRecordService:

    """

        Tracks the DirectoryRecord objects, and acts as the
        Interface between other code and Directory Record files.

    """

    # TODO we need to be able to handle if a file is uploaded and deleted
    # and then a new file is given the same name. Maybe don't delete,
    # but instead leave a ghost file behind
    _SUPPORTED_VIDEO_EXTENSIONS = {".mp4", ".avi", ".mkv", ".mov"}

    def __init__(self) -> None:
        """
        Initialize the DirectoryRecordService.
        Manages DirectoryRecord instances as singletons per directory.
        """
        self.records_cache : Dict[str, _DirectoryRecord] = {
            # "path/to/directory" : DirectoryRecord instance
        }
        self._records_cache_lock = threading.Lock()

    def get_record(self, directory_path: Path) -> _DirectoryRecord:
        """
        Get or create a DirectoryRecord for the specified directory.
        Ensures only one instance per directory exists (singleton pattern).
        
        Args:
            directory_path: Path to the directory
            
        Returns:
            DirectoryRecord instance for that directory
        """
        path_str = str(directory_path.resolve())
        
        # Add if it doesn't already exist
        with self._records_cache_lock:
            if path_str not in self.records_cache:
                self.records_cache[path_str] = _DirectoryRecord(directory_path)
        
        return self.records_cache[path_str]

    # def file_is_tracked(self, file_path : Path):

    #     """

    #         Takes in the file_path of a particular file. 
    #         Returns true if that file is already exists,
    #         false if it doesn't

    #     """

    #     status = self.get_video_by_path(Path)
    #     if status == None:
    #         return False
    #     else:
    #         return True


    def update_record(self, video_data: Video) -> bool:
        """
        Takes in Video object, finds relevant DirectoryRecord,
        and updates/adds that data to the directory record.
        
        If video_guid already exists, updates it. Otherwise, adds it.
        
        Args:
            video_data: Video object to add or update
            
        Returns:
            True if successful
        """
        # Get directory based on original_path
        directory = Path(video_data.original_path).parent
        
        # Get or create the DirectoryRecord (singleton)
        record = self.get_record(directory)
        
        # Try to update first
        if not record.update_processed_video(video_data):
            # If update failed (video not found), add it as new
            record.add_processed_video(video_data)
        
        return True

    def add_record(self, video_data: Video) -> bool:
        """
        Add a new video record. If it already exists (by video_guid), it will be skipped.
        
        Args:
            video_data: Video object to add
            
        Returns:
            True if successful
        """
        directory = Path(video_data.original_path).parent
        record = self.get_record(directory)
        record.add_processed_video(video_data)
        return True
    
    def _is_supported_video_path(self, video_path: Path) -> bool:
        """Returns True when path points to a supported video file."""
        if not video_path.exists() or video_path.is_dir():
            return False
        
        return video_path.suffix.lower() in self._SUPPORTED_VIDEO_EXTENSIONS
    
    def get_video_json_by_path(self, video_path: Union[str, Path]) -> Optional[dict]:
        """
        Retrieve video data by its file path.
        
        Args:
            video_path: Path to the video file
            
        Returns:
            Video object if found, None otherwise
        """
        video_path = video_path if type(video_path) == Path else Path(video_path)
        directory = video_path.parent
        
        # Get the record for this directory
        record = self.get_record(directory)
        
        if not video_path.exists():
            return None
        
        return record.get_video_dict_by_path(video_path)
    
    def get_video_by_path(self, video_path: Union[str, Path], context: "Context") -> Optional[Video]:
        """
        Retrieve a tracked Video object by file path.
        
        Args:
            video_path: Path to the target video file
            context: Shared application context required to construct Video
            
        Returns:
            Video object if path is a tracked video, None otherwise
        """
        video_path = video_path if type(video_path) == Path else Path(video_path)
        
        # Return None when the path is not a supported video file
        if not self._is_supported_video_path(video_path):
            return None
        
        # Constructing Video will load tracked data or create/index a new record.
        return Video(video_path=video_path, context=context)

    def is_uploaded(self, video_path: Union[str, Path]) -> bool:
        """
        Check if a specific video file has been uploaded to YouTube.
        
        Args:
            video_path: Path to the video file
            
        Returns:
            True if the video has been uploaded (has a valid YouTube URL), False otherwise
            
        Raises:
            ValueError: If the path is not a specific file (is a directory or doesn't exist)
        """
        video_path = video_path if type(video_path) == Path else Path(video_path)
        
        # Check if path is a specific file
        if not video_path.exists():
            raise ValueError(f"Path does not exist: {video_path  }")
        
        if video_path.is_dir():
            raise ValueError(f"Path is a directory, not a file: {video_path}")
        
        # Get video data from records
        video_data = self.get_video_json_by_path(video_path)
        
        # Check if video exists in records AND has a valid YouTube URL
        if video_data is None:
            return False
        
        youtube_url = video_data.get('youtube_url')
        
        # Check that youtube_url is not None, not empty string, and not just whitespace
        return youtube_url is not None and isinstance(youtube_url, str) and youtube_url.strip() != ""
    
    def set_keep_local(self, video_path: Union[str, Path], keep_local: bool) -> bool:
        """
        Set keep_local value for a tracked video path.
        
        Args:
            video_path: Path to the target video file
            keep_local: Desired keep_local value
            
        Returns:
            True if updated, False if file is not currently tracked
            
        Raises:
            ValueError: If the path is not a specific file (is a directory or doesn't exist)
        """
        video_path = video_path if type(video_path) == Path else Path(video_path)
        
        # Check if path is a specific file
        if not video_path.exists():
            raise ValueError(f"Path does not exist: {video_path  }")
        
        if video_path.is_dir():
            raise ValueError(f"Path is a directory, not a file: {video_path}")
        
        record = self.get_record(video_path.parent)
        return record.set_keep_local_by_path(video_path, keep_local)
    
    def should_keep_local(self, video_path: Union[str, Path]) -> bool:
        """
        Get keep_local value for a video path.
        
        Args:
            video_path: Path to the target video file
            
        Returns:
            keep_local value for tracked videos, otherwise False
        """
        video_path = video_path if type(video_path) == Path else Path(video_path)
        
        if not video_path.exists() or video_path.is_dir():
            return False
        
        record = self.get_record(video_path.parent)
        keep_local = record.get_keep_local_by_path(video_path)
        
        return keep_local if keep_local is not None else False

