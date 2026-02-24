import os
import hashlib
from pathlib import Path
from datetime import datetime
from typing import Union, Dict, Any

from enums.VideoStatus import VideoStatus

class YouTubeUpload:

    """

        Data class that records a youtube
        upload, including matching it to a local file. 

    """

    @staticmethod
    def compute_file_hash(file_path: Union[str, Path]) -> str:
        """
        Compute SHA256 hash of a file to create a unique video GUID
        
        Args:
            file_path: Path to the video file
            
        Returns:
            SHA256 hash string (64 hex characters)
        """
        sha256_hash = hashlib.sha256()
        
        # Read file in chunks to handle large video files efficiently
        with open(file_path, "rb") as f:
            # Read in 8KB chunks
            for byte_block in iter(lambda: f.read(8192), b""):
                sha256_hash.update(byte_block)
        
        return sha256_hash.hexdigest()

    def __init__(self, 
                 youtube_response: Dict[str, Any],
                 video_file: Union[str, Path],
                 title: str,
                 description: str,
                 category_id: str,
                 privacy_status: str) -> None:

        """ 
        Create YouTubeUpload from upload_video response
        
        Args:
            youtube_response: Raw response from YouTube API
            video_file: Path to the uploaded video file
            title: Video title used for upload
            description: Video description used for upload
            category_id: Category ID used for upload
            privacy_status: Privacy status used for upload
        """

        raise DeprecationWarning("This class is deprecated. DO NOT USE")

        # Build unified data dictionary
        data = {
            # Unique identifier (hash-based GUID)
            'video_guid': self.compute_file_hash(video_file) if os.path.exists(str(video_file)) else "",
            
            # Original video data
            'original_path': str(video_file),
            'filename': os.path.basename(str(video_file)),
            'filesize': os.path.getsize(str(video_file)) // 1024 if os.path.exists(str(video_file)) else 0,  # kb
            'original_creation_date': datetime.fromtimestamp(os.path.getctime(str(video_file))).isoformat() if os.path.exists(str(video_file)) else "",
            
            # Youtube video data from response
            'youtube_url': f"https://www.youtube.com/watch?v={youtube_response['id']}",
            'youtube_video_id': youtube_response['id'],
            'upload_date': youtube_response['snippet']['publishedAt'],
            'youtube_title': youtube_response['snippet']['title'],
            'youtube_description': youtube_response['snippet']['description'],
            'channel_id': youtube_response['snippet']['channelId'],
            'channel_title': youtube_response['snippet']['channelTitle'],
            'category_id': youtube_response['snippet']['categoryId'],
            'privacy_status': youtube_response['status']['privacyStatus'],
            
            # Synthetic features
            'status': VideoStatus.UPLOADED.value
        }
        
        # Populate instance from unified data
        self._populate_from_dict(data)

    @staticmethod
    def from_json(data: Dict[str, Any]) -> 'YouTubeUpload':
        """
        Create YouTubeUpload from saved JSON data
        
        Args:
            data: Dictionary containing saved upload data
            
        Returns:
            YouTubeUpload instance
        """
        instance = YouTubeUpload.__new__(YouTubeUpload)
        instance._populate_from_dict(data)
        return instance

    def _populate_from_dict(self, data: Dict[str, Any]) -> None:
        """
        Unified method to populate instance fields from dictionary
        
        Args:
            data: Dictionary containing all upload data
        """
        # Unique identifier
        self.video_guid = data.get('video_guid', "")
        
        # Original video data
        self.original_path = data.get('original_path', "")
        self.filename = data.get('filename', "")
        self.filesize = data.get('filesize', "")  # kb
        self.original_creation_date = data.get('original_creation_date', "")

        # Youtube video data
        self.youtube_url = data.get('youtube_url', "")
        self.youtube_video_id = data.get('youtube_video_id', "")
        self.upload_date = data.get('upload_date', "")
        self.youtube_title = data.get('youtube_title', "")
        self.youtube_description = data.get('youtube_description', "")
        self.channel_id = data.get('channel_id', "")
        self.channel_title = data.get('channel_title', "")
        self.category_id = data.get('category_id', "")
        self.privacy_status = data.get('privacy_status', "")

        # Synthetic features
        status_value = data.get('status', VideoStatus.UPLOADED.value)
        if isinstance(status_value, VideoStatus):
            self.status = status_value
        else:
            # Convert string to enum
            self.status = VideoStatus(status_value) if status_value else VideoStatus.UNKNOWN

    def to_dict(self) -> Dict[str, Any]:
        """
        Convert YouTubeUpload instance to dictionary for JSON serialization
        
        Returns:
            Dictionary containing all upload data
        """
        return {
            # Unique identifier
            'video_guid': self.video_guid,
            
            # Original video data
            'original_path': self.original_path,
            'filename': self.filename,
            'filesize': self.filesize,
            'original_creation_date': self.original_creation_date,
            
            # Youtube video data
            'youtube_url': self.youtube_url,
            'youtube_video_id': self.youtube_video_id,
            'upload_date': self.upload_date,
            'youtube_title': self.youtube_title,
            'youtube_description': self.youtube_description,
            'channel_id': self.channel_id,
            'channel_title': self.channel_title,
            'category_id': self.category_id,
            'privacy_status': self.privacy_status,
            
            # Synthetic features
            'status': self.status.value if isinstance(self.status, VideoStatus) else self.status
        }

