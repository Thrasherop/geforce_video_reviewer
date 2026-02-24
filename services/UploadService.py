from pathlib import Path, WindowsPath
from typing import Union, Dict, Any, List
from pprint import pprint

from enums.VideoStatus import VideoStatus
from helpers.make_video_ghost_file import make_video_ghost_file
from services.DirectoryRecordService import DirectoryRecordService
from services.FileSelectionService import FileSelectionService
from services.YouTubeService import YouTubeService

from objects.FileSelection import FileSelection
from objects.Context import Context
from objects.Video import Video

class UploadService:

    def __init__(self, global_context):

        raise DeprecationWarning("This class is deprecated and only included for reference implementation")
        
        # Initialize Services
        self.file_service = FileSelectionService()
        self.directory_record_service = DirectoryRecordService()
        self.youtube_service = YouTubeService()

        # Initialize context
        self.context = Context(self.directory_record_service, self.file_service, self.youtube_service)


    def make_videos_ghost_files(self) -> bool:

        # Get selection
        selection : FileSelection = self.file_service.select_files(
            title="Select video files",
            file_types=[
                ("Video files", "*.mp4 *.avi *.mkv *.mov"),
                ("All files", "*.*")
            ]
        )

        # Loop through files, making each a ghost
        for path in selection.get_paths():

            status = make_video_ghost_file(path, self.directory_record_service)
            print(f"Success.")

        return True

    def migrate_selection(self, log : bool = False) -> bool:

        """ Fetch selection from user, upload videos, then migrate to ghost files """

        # Fetch selection from user
        selection : FileSelection = self.file_service.select_files(
            title="Select video files",
            file_types=[
                ("Video files", "*.mp4 *.avi *.mkv *.mov"),
                ("All files", "*.*")
            ]
        )

        try:
            # Upload videos
            data = self._upload_file_selection(selection)

        except Exception as e:
            print(e)
        finally:
            # Always sort playlists, even if we get rate limited.
            # Sort
            self._sort_playlists_by_description(data['touched_playlists'])

        # Attempt to migrate files
        migration_statuses : dict = {"successes" : [], "failures" : []}
        statuses : dict = data['statuses']
        for windowspath in statuses.keys():

            # Grab path object
            windowspath : WindowsPath
            path = Path(str(windowspath))

            result = make_video_ghost_file(path, self.directory_record_service)
            if result:
                migration_statuses['successes'].append(path)
            else:
                migration_statuses['failures'].append(path)

        return data["statuses"]

    def upload_selection(self, log : bool = False) -> bool:

        # Fetch selection from user
        selection : FileSelection = self.file_service.select_files(
            title="Select video files",
            file_types=[
                ("Video files", "*.mp4 *.avi *.mkv *.mov"),
                ("All files", "*.*")
            ]
        )

        try:
            # Upload videos
            data = self._upload_file_selection(selection)

        except Exception as e:
            print(e)
        finally:
            # Always sort playlists, even if we get rate limited.
            # Sort
            self._sort_playlists_by_description(data['touched_playlists'])

        return data["statuses"]

    def sort_playlist_via_description(self, playlist_name : str) -> Dict[str, dict]:

        return self._sort_playlists_by_description([playlist_name])

    def _upload_file_selection(self, selection : FileSelection, log : bool = False) -> dict[str, Any]:

        # Loop through videos, uploading and updating the record as we go
        statuses : dict[str, VideoStatus] = {} # maps path to status
        touched_playlists = set[str]()
        for file_path in selection.get_paths():

            # Get video object
            this_video : Video = Video(file_path, self.context)
            
            # Check if it is already uploaded
            if this_video.is_uploaded():
                print(f"Skipping {this_video.filename}: already uploaded.", end="")
                statuses[file_path] = this_video.status
            else:
                # Upload
                print(f"Uploading {this_video.filename}...", end="")
                result = this_video.upload_to_youtube()
                print(f"{"Success." if result else "Failed."}")

            # Organize to playlists based on game AND date
            print(f"Adding {this_video.filename} to playlists...", end="")
            playlist_status = this_video.update_playlists()
            print(f"Added {this_video.filename} to {len(playlist_status['added'])} playlists, removed from {len(playlist_status['removed'])}, with {len(playlist_status['errors'])} errors")

            # Record status
            statuses[file_path] = this_video.status

        final_return = {
            "statuses" : statuses,
            "touched_playlists" : touched_playlists
        }

        return final_return  

    def _sort_playlists_by_description(self, playlists_to_sort : Union[List[str], set[str]]) -> Dict[str, dict]:

        statuses = {}
        for playlist in playlists_to_sort:

            print(f"Sorting {playlist} (Playlist)...", end="")

            # get playlist id
            playlist_id = self.youtube_service.get_playlist_id_by_name(playlist)

            # make it sort
            status = self.youtube_service.sort_playlist_by_description_date(playlist_id)

            if len(status['errors']) > 0:
                print("Had an error sorting a playlist!")
                pprint(status)
            else:
                print("Success.")

            # Add this to statuses for this playlist
            statuses[playlist] = status

        
        return statuses
