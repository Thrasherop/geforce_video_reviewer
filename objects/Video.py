import os
from pathlib import Path, WindowsPath
import hashlib
from pathlib import Path
from datetime import datetime, timedelta
from typing import Union, Dict, Any, Callable, Optional

from config.config import CTIME_OFFSET_FOR_GAMERS, DEFAULT_MADE_FOR_KIDS
from helpers.make_video_ghost_file import make_video_ghost_file, file_is_ghost_file
from enums.YoutubeCategory import YouTubeCategory
from enums.VideoStatus import VideoStatus

from enums.YoutubePrivacySetting import YoutubePrivacySetting
from objects.Context import Context


class Video:

    @staticmethod
    def garauntee_path_object(path : Union[str, Path]) -> Path:

        if type(path) == Path:
            return path
        else:
            path_obj = Path(path)
            return path_obj

    @staticmethod
    def garauntee_datetime_object(date : Union[str, datetime]) -> datetime:

        if type(date) == datetime:
            return date
        else:
            datetime_obj = datetime.fromisoformat(date)
            return datetime_obj

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


    def __init__(self, video_path : Union[Path, str], context : Context) -> None:

        # Save context
        self._context = context

        # Check if record is already tracked (returns None if not)
        video_json = context.directory_record_service.get_video_json_by_path(video_path)

        if video_json == None:
            # Create new record

            # Original video data
            self.original_path : Path = Video.garauntee_path_object(video_path)
            self.filename = os.path.basename(str(self.original_path))
            self.filesize = os.path.getsize(str(self.original_path)) // 1024 if os.path.exists(str(self.original_path)) else 0
            # self.original_creation_date = datetime.fromtimestamp(os.path.getctime(str(self.original_path))).isoformat() if os.path.exists(str(self.original_path)) else ""
            self.original_creation_date : datetime = Video.garauntee_datetime_object(self._get_creation_date_object())

            # Initialize Youtube video data with None
            self.youtube_url = None
            self.youtube_video_id = None
            self.upload_date = None
            self.youtube_title = None
            self.youtube_description = None
            self.channel_id = None
            self.channel_title = None
            self.category_id = None
            self.privacy_status = None

            # synthetic features
            self.status : VideoStatus = VideoStatus.NOT_UPLOADED
            self.video_guid = self.compute_file_hash(self.original_path) # Unique identifier
            self.keep_local = False

            # Save
            self.save()

        else:
            # Load in record
            self._populate_from_dict(video_json)
    
    def _get_creation_date_object(self) -> datetime:

        # reference:
        # datetime.fromtimestamp(os.path.getctime(str(self.original_path))).isoformat() if os.path.exists(str(self.original_path)) else ""

        # Verify we exist
        if not os.path.exists(str(self.original_path)):
            raise ValueError("_get_creation_date called with a path that doesn't exist.")

        time = os.path.getctime(str(self.original_path))
        dt_time = datetime.fromtimestamp(time)

        return dt_time


    def is_uploaded(self) -> bool:

        if self.status == VideoStatus.UNPROCESSED or self.status == VideoStatus.UNKNOWN or self.status == VideoStatus.NOT_UPLOADED:
            return False
        else:
            return True

    def save(self) -> bool:
        """ Save this video's data to DirectoryRecordService """

        result = self._context.directory_record_service.update_record(self)
        return result

    def should_keep_local(self) -> bool:
        return self.keep_local

    def set_keep_local(self, new_value : bool) -> bool:

        old_value = self.keep_local # remember in case we need to revert
        self.keep_local = new_value
        result = self.save()

        # revert if failed to keep valid state
        if not result:
            self.keep_local = old_value

        return result
    
    def _populate_from_dict(self, data: Dict[str, Any]) -> None:
        """
        Unified method to populate instance fields from dictionary
        
        Args:
            data: Dictionary containing all upload data
        """

        # Unique identifier
        self.video_guid = data.get('video_guid', "")
        
        # Original video data
        self.original_path = Video.garauntee_path_object(data.get('original_path', ""))
        self.filename = data.get('filename', "")
        self.filesize = data.get('filesize', "")  # kb
        self.original_creation_date = Video.garauntee_datetime_object(data.get('original_creation_date', ""))

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

            # Throw error if its unknown
            if self.status == VideoStatus.UNKNOWN:
                raise ValueError("Video was initialized, but status was UNKNOWN. Throwing error")

        self.keep_local = data.get('keep_local', False)
        if self.keep_local == "": # TODO make the default "" after catching up so we detect errors
            raise ValueError("Video was initialized, but keep_local wasn't included")
        
    def upload_to_youtube(
            self, 
            force : bool = False, 
            made_for_kids : bool = DEFAULT_MADE_FOR_KIDS,
            sort_playlists : bool = True,
            migrate_to_youtube : bool = True,
            upload_name : Optional[str] = None
        ) -> dict[str, Any]:

        """ 
            Uploads self to youtube, sorts playlists and/or migrates files if requested.
            If an extra operation (e.g. sort playlists) isn't requested, then returned
            status is success (True)
        
        """

        # Perform upload
        upload_status = self.__upload_to_youtube(
            force=force,
            made_for_kids=made_for_kids,
            upload_name=upload_name
        )

        # Return failure if failed
        if not upload_status:
            return {"status" : False, "error" : "Failed video upload to youtube"}

        # Add to playlists
        touched_playlists = self.update_playlists()

        # Sort playlists
        if sort_playlists:
            sort_status = self._context.youtube_service.sort_playlists_by_name_and_description()
        else:
            sort_status = True

        # Perform migration
        if migrate_to_youtube:
            migrate_status = self.__migrate_self()
        else:
            migrate_status = True

        # Compile results and return
        overall_status = (upload_status and sort_status and migrate_status)
        final_statuses = {
            "overall_status" : overall_status,
            "upload_status" : upload_status,
            "sort_status" : sort_status,
            "migrate_status" : migrate_status,
            "touched_playlists" : touched_playlists,
        }

        return final_statuses

    def upload_to_youtube_sse(
            self,
            force : bool = False,
            made_for_kids : bool = DEFAULT_MADE_FOR_KIDS,
            sort_playlists : bool = True,
            migrate_to_youtube : bool = True,
            upload_name : Optional[str] = None,
            on_progress: Optional[Callable[[str, int, str], None]] = None
        ) -> dict[str, Any]:

        """
            SSE-friendly upload flow that emits state/percentage updates while
            preserving the existing upload -> playlist -> migrate flow.
        """

        # Perform upload
        upload_status = self.__upload_to_youtube_sse(
            force=force,
            made_for_kids=made_for_kids,
            upload_name=upload_name,
            on_progress=on_progress
        )

        # Return failure if failed
        if not upload_status:
            return {"status" : False, "error" : "Failed video upload to youtube"}

        # Add to playlists
        if on_progress:
            on_progress("playlist_updating", 100, "Updating playlists")
        touched_playlists = self.update_playlists()

        # Sort playlists    
        if sort_playlists:
              sort_status = self._context.youtube_service.sort_playlists_by_name_and_description(touched_playlists)
        else:
            sort_status = True

        # Perform migration
        if migrate_to_youtube:
            if on_progress:
                on_progress("migrating", 100, "Migrating to ghost file")
            migrate_status = self.__migrate_self()
        else:
            migrate_status = True

        # Compile results and return
        overall_status = (upload_status and sort_status and migrate_status)
        final_statuses = {
            "overall_status" : overall_status,
            "upload_status" : upload_status,
            "sort_status" : sort_status,
            "migrate_status" : migrate_status,
            "touched_playlists" : touched_playlists,
        }
        if on_progress and overall_status:
            on_progress("success", 100, "Upload complete")

        return final_statuses

    def __migrate_self(self) -> bool:

        """ MNigrate self to ghost file """

        result = make_video_ghost_file(self.original_path, self._context.directory_record_service)
        return result


        

    def __upload_to_youtube(
            self, 
            force : bool = False, 
            made_for_kids : bool = DEFAULT_MADE_FOR_KIDS,
            upload_name : Optional[str] = None,
        ) -> bool:

        
        """ Uploads video to youtube. Returns true if already uploaded. force overrides the already uploaded check """

        # Early exit if already uploaded
        if self.is_uploaded() and not force:
            return True

        description = f"""Auto uploaded and clipped.\n\n&&&{str(self.original_creation_date)}"""

        # upload
        upload_title = upload_name.strip() if upload_name and upload_name.strip() else self.filename
        youtube_data = self._context.youtube_service.upload_video(
            video_file = self.original_path,
            title = upload_title,
            description = description,
            category_id = YouTubeCategory.GAMING,
            privacy_status = YoutubePrivacySetting.UNLISTED,
            made_for_kids = made_for_kids
        )

        # Check if upload was successful
        if not youtube_data or 'id' not in youtube_data:
            # raise Exception(f"Failed to upload video: Invalid response from YouTube API")
            return False

        # unpack data
        self.youtube_url = f"https://www.youtube.com/watch?v={youtube_data['id']}"
        self.youtube_video_id = youtube_data['id']
        self.upload_date = youtube_data['snippet']['publishedAt']
        self.youtube_title = youtube_data['snippet']['title']
        self.youtube_description = youtube_data['snippet']['description']
        self.channel_id = youtube_data['snippet']['channelId']
        self.channel_title = youtube_data['snippet']['channelTitle']
        self.category_id = youtube_data['snippet']['categoryId']
        self.privacy_status = youtube_data['status']['privacyStatus']

        # Update status
        self.status = VideoStatus.UPLOADED

        # save changes to directory service
        self.save()
        
        return True

    def __upload_to_youtube_sse(
            self,
            force : bool = False,
            made_for_kids : bool = DEFAULT_MADE_FOR_KIDS,
            upload_name : Optional[str] = None,
            on_progress: Optional[Callable[[str, int, str], None]] = None
        ) -> bool:

        """SSE-friendly upload implementation with upload percentage callbacks."""

        # Explicitly refuse ghost-file uploads unless force is requested.
        # Ghost files should never create a new YouTube upload.
        if file_is_ghost_file(self.original_path) and not force:
            if self.is_uploaded():
                if on_progress:
                    on_progress("uploading", 100, "Already ghost file; skipping upload")
                return True
            if on_progress:
                on_progress("error", 100, "Ghost file detected and not marked uploaded")
            return False

        # Early exit if already uploaded
        if self.is_uploaded() and not force:
            if on_progress:
                on_progress("uploading", 100, "Already uploaded")
            return True

        description = f"""Auto uploaded and clipped.\n\n&&&{str(self.original_creation_date)}"""

        if on_progress:
            on_progress("uploading", 0, "Starting upload")

        # upload
        upload_title = upload_name.strip() if upload_name and upload_name.strip() else self.filename
        youtube_data = self._context.youtube_service.upload_video_sse(
            video_file = self.original_path,
            title = upload_title,
            description = description,
            category_id = YouTubeCategory.GAMING,
            privacy_status = YoutubePrivacySetting.UNLISTED,
            made_for_kids = made_for_kids,
            on_progress=lambda percent: (
                on_progress("uploading", percent, "Uploading to YouTube") if on_progress else None
            )
        )

        # Check if upload was successful
        if not youtube_data or 'id' not in youtube_data:
            # raise Exception(f"Failed to upload video: Invalid response from YouTube API")
            return False

        # unpack data
        self.youtube_url = f"https://www.youtube.com/watch?v={youtube_data['id']}"
        self.youtube_video_id = youtube_data['id']
        self.upload_date = youtube_data['snippet']['publishedAt']
        self.youtube_title = youtube_data['snippet']['title']
        self.youtube_description = youtube_data['snippet']['description']
        self.channel_id = youtube_data['snippet']['channelId']
        self.channel_title = youtube_data['snippet']['channelTitle']
        self.category_id = youtube_data['snippet']['categoryId']
        self.privacy_status = youtube_data['status']['privacyStatus']

        # Update status
        self.status = VideoStatus.UPLOADED

        # save changes to directory service
        self.save()
        
        return True

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
            'original_path': str(self.original_path),
            'filename': self.filename,
            'filesize': self.filesize,
            'original_creation_date': self.original_creation_date.isoformat(),
            
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
            'keep_local' : self.keep_local,
            'status': self.status.value if isinstance(self.status, VideoStatus) else self.status
        }

    def update_playlists(self) -> Dict[str, Any]:

        # Raise error if not yet uploaded
        if not self.is_uploaded():
            raise FileNotFoundError("update_playlists called on non-uploaded video")
  
        # # Grab playlists we're currently in
        # playlists = self._context.youtube_service.get_playlists_for_video(self.youtube_video_id)
        
        # Calculate playlist requirements
        parent_directory_name = self.original_path.parent.name # likely to be game name

        # Calculate timing
        adjusted_timing = self.original_creation_date + timedelta(hours=CTIME_OFFSET_FOR_GAMERS) # account for CTIME_OFFSET_FOR_GAMERS
        date_str = str(adjusted_timing.date())

        playlists = [
            parent_directory_name,
            date_str
        ]

        statuses = self._context.youtube_service.set_video_playlists(
            video_id = self.youtube_video_id,
            playlist_names = playlists,
            create_missing = True
        )

        return statuses