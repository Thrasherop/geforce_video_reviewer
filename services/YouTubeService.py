"""
YouTubeService - A comprehensive service for interacting with YouTube API
Supports video uploads, description modifications, and playlist management
"""

import os
import pickle
import random
import tempfile
import threading
import time
from pprint import pprint
from pathlib import Path
from typing import Optional, List, Dict, Any, Union, Callable
from dateutil import parser as date_parser
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import InstalledAppFlow
from google.auth.transport.requests import Request
from googleapiclient.discovery import build
from googleapiclient.http import MediaFileUpload
from googleapiclient.errors import HttpError


from enums.YoutubePrivacySetting import YoutubePrivacySetting
from enums.YoutubeCategory import YouTubeCategory



class YouTubeService:
    """
    A service class for interacting with YouTube Data API v3
    
    Provides methods for:
    - Uploading videos
    - Modifying video descriptions
    - Creating playlists
    - Adding/removing videos from playlists
    """
    
    # YouTube API scopes
    SCOPES = [
        'https://www.googleapis.com/auth/youtube.upload',
        'https://www.googleapis.com/auth/youtube',
        'https://www.googleapis.com/auth/youtube.force-ssl'
    ]
    MAX_UPLOAD_RETRIES = 5
    RETRIABLE_STATUS_CODES = [500, 502, 503, 504]
    
    def __init__(self, client_secrets_file: str = 'secrets/client_secrets.json', 
                 token_file: str = 'secrets/token.pickle'):
        """
        Initialize the YouTube service
        
        Args:
            client_secrets_file: Path to OAuth2 client secrets JSON file
            token_file: Path to store/retrieve authentication token
        """
        self.client_secrets_file = client_secrets_file
        self.token_file = token_file
        self._thread_local = threading.local()
        self._token_lock = threading.Lock()
        self._authenticate()
    
    def _write_token_file_atomic(self, creds: Credentials) -> None:
        token_directory = os.path.dirname(self.token_file) or '.'
        os.makedirs(token_directory, exist_ok=True)
        with tempfile.NamedTemporaryFile(mode='wb', delete=False, dir=token_directory) as temp_token:
            pickle.dump(creds, temp_token)
            temp_path = temp_token.name
        os.replace(temp_path, self.token_file)

    def _load_or_refresh_credentials(self) -> Credentials:
        """
        Authenticate with YouTube API using OAuth2
        """
        creds = None

        with self._token_lock:
            # Load existing credentials from token file
            if os.path.exists(self.token_file):
                with open(self.token_file, 'rb') as token:
                    creds = pickle.load(token)

            # If credentials are invalid or don't exist, get new ones
            if not creds or not creds.valid:
                if creds and creds.expired and creds.refresh_token:
                    creds.refresh(Request())
                else:
                    if not os.path.exists(self.client_secrets_file):
                        raise FileNotFoundError(
                            f"Client secrets file not found: {self.client_secrets_file}\n"
                            "Please download OAuth2 credentials from Google Cloud Console"
                        )

                    flow = InstalledAppFlow.from_client_secrets_file(
                        self.client_secrets_file, self.SCOPES
                    )
                    creds = flow.run_local_server(port=0)

                # Save credentials for future use
                self._write_token_file_atomic(creds)

        return creds

    def _authenticate(self) -> None:
        creds = self._load_or_refresh_credentials()
        self._thread_local.credentials = creds
        self._thread_local.youtube_client = build('youtube', 'v3', credentials=creds)
        print(f"[YouTubeService][thread={threading.get_ident()}] Initialized thread-local client")

    def _get_thread_client(self):
        youtube_client = getattr(self._thread_local, 'youtube_client', None)
        creds = getattr(self._thread_local, 'credentials', None)
        if youtube_client is not None and creds is not None and creds.valid:
            print(f"[YouTubeService][thread={threading.get_ident()}] Reusing thread-local client")
            return youtube_client

        creds = self._load_or_refresh_credentials()
        youtube_client = build('youtube', 'v3', credentials=creds)
        self._thread_local.credentials = creds
        self._thread_local.youtube_client = youtube_client
        print(f"[YouTubeService][thread={threading.get_ident()}] Created new thread-local client")
        return youtube_client
    
    def upload_video(self, 
                     video_file: Union[str, Path],
                     title: str,
                     description: str = "",
                     category_id: Union[str, 'YouTubeCategory'] = YouTubeCategory.GAMING,  # Default: People & Blogs
                     tags: Optional[List[str]] = None,
                     privacy_status: Union[str, 'YoutubePrivacySetting'] = YoutubePrivacySetting.UNLISTED,
                     made_for_kids: Optional[bool] = None) -> dict:
        """
        Upload a video to YouTube
        
        Args:
            video_file: Path to the video file (string or pathlib.Path object)
            title: Video title
            description: Video description
            category_id: YouTube category ID (string) or YouTubeCategory enum
                        (default: "22" - People & Blogs)
            tags: List of tags for the video
            privacy_status: Privacy status ('public', 'private', or 'unlisted')
            made_for_kids: Optional boolean to declare if video is made for kids.
                          If True, marks video as child-directed (COPPA compliance).
                          If False, marks video as not child-directed.
                          If None (default), YouTube will determine based on channel settings.
        
        Returns:
            dict object containing youtube response
        
        Raises:
            FileNotFoundError: If video file doesn't exist
            HttpError: If upload fails
        
        Example:
            from youtube_categories import YouTubeCategory
            from pathlib import Path
            
            yt.upload_video(
                Path('clip.mp4'),
                'My Gaming Clip',
                category_id=YouTubeCategory.GAMING,
                made_for_kids=False
            )
        """
        if not os.path.exists(video_file):
            raise FileNotFoundError(f"Video file not found: {video_file}")
        
        # Convert enum to string if necessary
        if hasattr(category_id, 'value'):
            category_id = category_id.value
        
        if hasattr(privacy_status, 'value'):
            privacy_status = privacy_status.value
        
        body = {
            'snippet': {
                'title': title,
                'description': description,
                'categoryId': str(category_id)
            },
            'status': {
                'privacyStatus': privacy_status
            }
        }
        
        # Add selfDeclaredMadeForKids if specified
        if made_for_kids is not None:
            body['status']['selfDeclaredMadeForKids'] = made_for_kids
        
        if tags:
            body['snippet']['tags'] = tags
        
        # Create MediaFileUpload object
        media = MediaFileUpload(
            str(video_file),
            chunksize=-1,  # Upload in a single request
            resumable=True
        )
        
        response = None
        retry_count = 0
        try:
            # Execute the upload
            youtube = self._get_thread_client()
            request = youtube.videos().insert(
                part='snippet,status',
                body=body,
                media_body=media
            )
            
            response = request.execute()

            # Return response data
            return response
            
            # Create and return YouTubeUpload object
            # return YouTubeUpload(
            #     youtube_response=response,
            #     video_file=video_file,
            #     title=title,
            #     description=description,
            #     category_id=str(category_id),
            #     privacy_status=privacy_status
            # )
        
        except HttpError as e:
            print("Failed to upload video due to error:")
            pprint(e)
            # raise Exception(f"Failed to upload video: {e}")

    def upload_video_sse(self, 
                     video_file: Union[str, Path],
                     title: str,
                     description: str = "",
                     category_id: Union[str, 'YouTubeCategory'] = YouTubeCategory.GAMING,  # Default: People & Blogs
                     tags: Optional[List[str]] = None,
                     privacy_status: Union[str, 'YoutubePrivacySetting'] = YoutubePrivacySetting.UNLISTED,
                     made_for_kids: Optional[bool] = None,
                     on_progress: Optional[Callable[[int], None]] = None) -> dict:
        """
        Upload a video to YouTube and optionally emit upload percentage updates.
        """
        if not os.path.exists(video_file):
            raise FileNotFoundError(f"Video file not found: {video_file}")
        
        # Convert enum to string if necessary
        if hasattr(category_id, 'value'):
            category_id = category_id.value
        
        if hasattr(privacy_status, 'value'):
            privacy_status = privacy_status.value
        
        body = {
            'snippet': {
                'title': title,
                'description': description,
                'categoryId': str(category_id)
            },
            'status': {
                'privacyStatus': privacy_status
            }
        }
        
        # Add selfDeclaredMadeForKids if specified
        if made_for_kids is not None:
            body['status']['selfDeclaredMadeForKids'] = made_for_kids
        
        if tags:
            body['snippet']['tags'] = tags
        
        # Create MediaFileUpload object
        media = MediaFileUpload(
            str(video_file),
            resumable=True
        )
        
        response = None
        try:
            # Execute the upload
            youtube = self._get_thread_client()
            request = youtube.videos().insert(
                part='snippet,status',
                body=body,
                media_body=media
            )

            last_percent_reported = -1
            while response is None:
                try:
                    status, response = request.next_chunk()
                    if status and on_progress:
                        this_percent = int(status.progress() * 100)
                        if this_percent > last_percent_reported:
                            last_percent_reported = this_percent
                            on_progress(this_percent)
                    retry_count = 0
                except HttpError as e:
                    status_code = getattr(getattr(e, 'resp', None), 'status', None)
                    if status_code in self.RETRIABLE_STATUS_CODES and retry_count < self.MAX_UPLOAD_RETRIES:
                        retry_count += 1
                        sleep_seconds = random.random() * (2 ** retry_count)
                        print(
                            f"[YouTubeService][thread={threading.get_ident()}] Retriable upload error {status_code}; "
                            f"retry {retry_count}/{self.MAX_UPLOAD_RETRIES} in {sleep_seconds:.2f}s"
                        )
                        time.sleep(sleep_seconds)
                        continue
                    raise

            if on_progress and last_percent_reported < 100:
                on_progress(100)

            # Return response data
            return response
        
        except HttpError as e:
            print("Failed to upload video due to error:")
            pprint(e)
            # raise Exception(f"Failed to upload video: {e}")
    
    def update_video_description(self, 
                                  video_id: str,
                                  new_description: str,
                                  update_title: Optional[str] = None,
                                  update_tags: Optional[List[str]] = None) -> Dict[str, Any]:
        """
        Update a video's description (and optionally title and tags)
        
        Args:
            video_id: The YouTube video ID
            new_description: New description text
            update_title: Optional new title
            update_tags: Optional new tags list
        
        Returns:
            Dictionary containing updated video information
        
        Raises:
            HttpError: If update fails
        """
        try:
            # First, get the current video details
            youtube = self._get_thread_client()
            video_response = youtube.videos().list(
                part='snippet',
                id=video_id
            ).execute()
            
            if not video_response.get('items'):
                raise ValueError(f"Video not found: {video_id}")
            
            video = video_response['items'][0]
            snippet = video['snippet']
            
            # Update the description
            snippet['description'] = new_description
            
            # Update title if provided
            if update_title:
                snippet['title'] = update_title
            
            # Update tags if provided
            if update_tags:
                snippet['tags'] = update_tags
            
            # Update the video
            update_response = youtube.videos().update(
                part='snippet',
                body={
                    'id': video_id,
                    'snippet': snippet
                }
            ).execute()
            
            return {
                'video_id': update_response['id'],
                'title': update_response['snippet']['title'],
                'description': update_response['snippet']['description'],
                'tags': update_response['snippet'].get('tags', [])
            }
        
        except HttpError as e:
            raise Exception(f"Failed to update video: {e}")
    
    def create_playlist(self, 
                       title: str,
                       description: str = "",
                       privacy_status: str = "private") -> Dict[str, Any]:
        """
        Create a new playlist
        
        Args:
            title: Playlist title
            description: Playlist description
            privacy_status: Privacy status ('public', 'private', or 'unlisted')
        
        Returns:
            Dictionary containing playlist information including playlist ID
        
        Raises:
            HttpError: If creation fails
        """
        try:
            youtube = self._get_thread_client()
            request = youtube.playlists().insert(
                part='snippet,status',
                body={
                    'snippet': {
                        'title': title,
                        'description': description
                    },
                    'status': {
                        'privacyStatus': privacy_status
                    }
                }
            )
            
            response = request.execute()
            
            return {
                'playlist_id': response['id'],
                'title': response['snippet']['title'],
                'description': response['snippet']['description'],
                'url': f"https://www.youtube.com/playlist?list={response['id']}"
            }
        
        except HttpError as e:
            raise Exception(f"Failed to create playlist: {e}")
    
    def add_video_to_playlist(self, 
                             playlist_id: str,
                             video_id: str,
                             position: Optional[int] = None) -> Dict[str, Any]:
        """
        Add a video to a playlist
        
        Args:
            playlist_id: The playlist ID
            video_id: The video ID to add
            position: Optional position in playlist (0-indexed)
        
        Returns:
            Dictionary containing playlist item information
        
        Raises:
            HttpError: If adding fails
        """
        try:
            youtube = self._get_thread_client()
            body = {
                'snippet': {
                    'playlistId': playlist_id,
                    'resourceId': {
                        'kind': 'youtube#video',
                        'videoId': video_id
                    }
                }
            }
            
            if position is not None:
                body['snippet']['position'] = position
            
            request = youtube.playlistItems().insert(
                part='snippet',
                body=body
            )
            
            response = request.execute()
            
            return {
                'playlist_item_id': response['id'],
                'playlist_id': playlist_id,
                'video_id': video_id,
                'position': response['snippet'].get('position')
            }
        
        except HttpError as e:
            raise Exception(f"Failed to add video to playlist: {e}")
    
    def remove_video_from_playlist(self, playlist_item_id: str) -> bool:
        """
        Remove a video from a playlist
        
        Note: This requires the playlist item ID, not the video ID.
        Use get_playlist_items() to get the playlist item IDs.
        
        Args:
            playlist_item_id: The playlist item ID (not video ID)
        
        Returns:
            True if successful
        
        Raises:
            HttpError: If removal fails
        """
        try:
            youtube = self._get_thread_client()
            youtube.playlistItems().delete(
                id=playlist_item_id
            ).execute()
            
            return True
        
        except HttpError as e:
            raise Exception(f"Failed to remove video from playlist: {e}")
    
    def get_playlist_items(self, 
                          playlist_id: str,
                          max_results: int = 50) -> List[Dict[str, Any]]:
        """
        Get all videos in a playlist
        
        Args:
            playlist_id: The playlist ID
            max_results: Maximum number of results to return
        
        Returns:
            List of dictionaries containing playlist item information
        
        Raises:
            HttpError: If retrieval fails
        """
        try:
            items = []
            next_page_token = None
            youtube = self._get_thread_client()
            
            while True:
                request = youtube.playlistItems().list(
                    part='snippet,contentDetails',
                    playlistId=playlist_id,
                    maxResults=min(max_results - len(items), 50),
                    pageToken=next_page_token
                )
                
                response = request.execute()
                
                for item in response.get('items', []):
                    items.append({
                        'playlist_item_id': item['id'],
                        'video_id': item['contentDetails']['videoId'],
                        'title': item['snippet']['title'],
                        'position': item['snippet']['position']
                    })
                
                next_page_token = response.get('nextPageToken')
                
                if not next_page_token or len(items) >= max_results:
                    break
            
            return items
        
        except HttpError as e:
            raise Exception(f"Failed to get playlist items: {e}")
    
    def get_my_playlists(self, max_results: int = 25) -> List[Dict[str, Any]]:
        """
        Get user's playlists
        
        Args:
            max_results: Maximum number of results to return
        
        Returns:
            List of dictionaries containing playlist information
        
        Raises:
            HttpError: If retrieval fails
        """
        try:
            playlists = []
            next_page_token = None
            youtube = self._get_thread_client()
            
            while True:
                request = youtube.playlists().list(
                    part='snippet,contentDetails',
                    mine=True,
                    maxResults=min(max_results - len(playlists), 50),
                    pageToken=next_page_token
                )
                
                response = request.execute()
                
                for playlist in response.get('items', []):
                    playlists.append({
                        'playlist_id': playlist['id'],
                        'title': playlist['snippet']['title'],
                        'description': playlist['snippet']['description'],
                        'video_count': playlist['contentDetails']['itemCount']
                    })
                
                next_page_token = response.get('nextPageToken')
                
                if not next_page_token or len(playlists) >= max_results:
                    break
            
            return playlists
        
        except HttpError as e:
            raise Exception(f"Failed to get playlists: {e}")
    
    def get_playlist_id_by_name(self, playlist_name: str) -> Optional[str]:
        """
        Get the playlist ID for a playlist with an exact name match
        
        Args:
            playlist_name: The exact name of the playlist to find
        
        Returns:
            The playlist ID if found, None otherwise
        
        Raises:
            HttpError: If retrieval fails
        """
        try:
            # Get all user's playlists
            playlists = self.get_my_playlists(max_results=150)
            
            # Find exact match
            for playlist in playlists:
                if playlist['title'] == playlist_name:
                    return playlist['playlist_id']
            
            # No match found
            return None
        
        except HttpError as e:
            raise Exception(f"Failed to get playlist by name: {e}")
    
    def get_video_info(self, video_id: str) -> Dict[str, Any]:
        """
        Get information about a specific video
        
        Args:
            video_id: The YouTube video ID
        
        Returns:
            Dictionary containing video information
        
        Raises:
            HttpError: If retrieval fails
        """
        try:
            youtube = self._get_thread_client()
            request = youtube.videos().list(
                part='snippet,contentDetails,statistics',
                id=video_id
            )
            
            response = request.execute()
            
            if not response.get('items'):
                raise ValueError(f"Video not found: {video_id}")
            
            video = response['items'][0]
            
            return {
                'video_id': video['id'],
                'title': video['snippet']['title'],
                'description': video['snippet']['description'],
                'tags': video['snippet'].get('tags', []),
                'category_id': video['snippet']['categoryId'],
                'published_at': video['snippet']['publishedAt'],
                'duration': video['contentDetails']['duration'],
                'view_count': video['statistics'].get('viewCount', 0),
                'like_count': video['statistics'].get('likeCount', 0),
                'comment_count': video['statistics'].get('commentCount', 0)
            }
        
        except HttpError as e:
            raise Exception(f"Failed to get video info: {e}")
    
    def get_playlists_for_video(self, video_id: str) -> List[Dict[str, Any]]:
        """
        Get all playlists that contain a specific video
        
        Args:
            video_id: The YouTube video ID
        
        Returns:
            List of dictionaries containing playlist information where the video appears
        
        Raises:
            HttpError: If retrieval fails
        """
        try:
            playlists = []
            
            # Get all user's playlists first
            all_playlists = self.get_my_playlists(max_results=50)
            
            # Check each playlist for the video
            for playlist in all_playlists:
                playlist_id = playlist['playlist_id']
                
                # Get items in this playlist
                playlist_items = self.get_playlist_items(playlist_id, max_results=50)
                
                # Check if video is in this playlist
                for item in playlist_items:
                    if item['video_id'] == video_id:
                        playlists.append({
                            'playlist_id': playlist_id,
                            'playlist_item_id': item['playlist_item_id'],
                            'title': playlist['title'],
                            'description': playlist['description'],
                            'position': item['position'],
                            'url': f"https://www.youtube.com/playlist?list={playlist_id}"
                        })
                        break  # Video found in this playlist, move to next
            
            return playlists
        
        except HttpError as e:
            raise Exception(f"Failed to get playlists for video: {e}")
    
    def get_my_channel_info(self) -> Dict[str, Any]:
        """
        Get information about the authenticated channel
        
        Useful for verifying which channel you're uploading to
        
        Returns:
            Dictionary containing channel information
        
        Raises:
            HttpError: If retrieval fails
        """
        try:
            youtube = self._get_thread_client()
            request = youtube.channels().list(
                part='snippet,statistics,contentDetails',
                mine=True
            )
            
            response = request.execute()
            
            if not response.get('items'):
                raise ValueError("No channel found for authenticated user")
            
            channel = response['items'][0]
            
            return {
                'channel_id': channel['id'],
                'title': channel['snippet']['title'],
                'description': channel['snippet']['description'],
                'custom_url': channel['snippet'].get('customUrl', 'N/A'),
                'subscriber_count': channel['statistics'].get('subscriberCount', 0),
                'video_count': channel['statistics'].get('videoCount', 0),
                'view_count': channel['statistics'].get('viewCount', 0),
                'thumbnail_url': channel['snippet']['thumbnails']['default']['url'],
                'url': f"https://www.youtube.com/channel/{channel['id']}"
            }
        
        except HttpError as e:
            raise Exception(f"Failed to get channel info: {e}")
    
    def set_video_playlists(self, 
                           video_id: str, 
                           playlist_names: List[str],
                           create_missing: bool = True) -> Dict[str, Any]:
        """
        Set which playlists a video should be in, removing from others and adding to specified ones
        
        This method will:
        1. Remove the video from any playlists not in the provided list
        2. Add the video to any playlists in the provided list that it's not already in
        3. Optionally create playlists that don't exist
        
        Args:
            video_id: The YouTube video ID
            playlist_names: List of playlist names (string names, not IDs) the video should be in
            create_missing: If True, create playlists that don't exist (default: True)
        
        Returns:
            Dictionary containing operation results:
                - added: List of playlist names the video was added to
                - removed: List of playlist names the video was removed from
                - created: List of playlist names that were created
                - errors: List of error messages if any operations failed
        
        Raises:
            HttpError: If critical operations fail
        """
        try:
            results = {
                'added': [],
                'removed': [],
                'created': [],
                'errors': []
            }
            
            # Get all current playlists the video is in
            current_playlists = self.get_playlists_for_video(video_id)
            current_playlist_names = {p['title'] for p in current_playlists}
            
            # Get all user's playlists
            all_playlists = self.get_my_playlists(max_results=150)
            playlist_name_to_id = {p['title']: p['playlist_id'] for p in all_playlists}
            
            # Convert playlist_names to a set for easier comparison
            desired_playlist_names = set(playlist_names)
            
            # Remove video from playlists it shouldn't be in
            for playlist in current_playlists:
                if playlist['title'] not in desired_playlist_names:
                    try:
                        self.remove_video_from_playlist(playlist['playlist_item_id'])
                        results['removed'].append(playlist['title'])
                    except Exception as e:
                        results['errors'].append(f"Failed to remove from '{playlist['title']}': {str(e)}")
            
            # Add video to playlists it should be in
            for playlist_name in desired_playlist_names:
                # Skip if already in this playlist
                if playlist_name in current_playlist_names:
                    continue
                
                # Check if playlist exists
                if playlist_name not in playlist_name_to_id:
                    if create_missing:
                        # Create the playlist
                        try:
                            new_playlist = self.create_playlist(
                                title=playlist_name,
                                description="",
                                privacy_status="private"
                            )
                            playlist_name_to_id[playlist_name] = new_playlist['playlist_id']
                            results['created'].append(playlist_name)
                        except Exception as e:
                            results['errors'].append(f"Failed to create playlist '{playlist_name}': {str(e)}")
                            continue
                    else:
                        results['errors'].append(f"Playlist '{playlist_name}' does not exist")
                        continue
                
                # Add video to playlist
                try:
                    self.add_video_to_playlist(
                        playlist_id=playlist_name_to_id[playlist_name],
                        video_id=video_id
                    )
                    results['added'].append(playlist_name)
                except Exception as e:
                    results['errors'].append(f"Failed to add to '{playlist_name}': {str(e)}")
            
            return results
        
        except HttpError as e:
            raise Exception(f"Failed to set video playlists: {e}")
    
    def sort_playlist_by_id_and_description_date(self, playlist_id: str) -> Dict[str, Any]:
        """
        Sort a playlist by date found in video descriptions (newest first)
        
        Video descriptions should have a date string at the end, separated by &&&
        Format: "Description content &&&{date string}"
        The date string will be automatically parsed in various formats.
        
        Args:
            playlist_id: The playlist ID to sort
        
        Returns:
            Dictionary containing operation results:
                - sorted_count: Number of videos successfully sorted
                - skipped: List of video IDs that were skipped (no date found or parse error)
                - errors: List of error messages if any
        
        Raises:
            HttpError: If critical operations fail
        """
        try:
            results = {
                'sorted_count': 0,
                'skipped': [],
                'errors': []
            }
            
            # Get all playlist items
            playlist_items = self.get_playlist_items(playlist_id, max_results=500)
            
            if not playlist_items:
                return results
            
            # Fetch video descriptions and extract dates
            items_with_dates = []
            
            for item in playlist_items:
                video_id = item['video_id']
                
                try:
                    # Get video info including description
                    video_info = self.get_video_info(video_id)
                    description = video_info.get('description', '')
                    
                    # Extract date from description
                    if '&&&' in description:
                        date_string = description.split('&&&')[-1].strip()
                        
                        try:
                            # Parse the date automatically
                            date_obj = date_parser.parse(date_string)
                            
                            items_with_dates.append({
                                'playlist_item_id': item['playlist_item_id'],
                                'video_id': video_id,
                                'date': date_obj,
                                'title': item['title']
                            })
                        except (ValueError, date_parser.ParserError) as e:
                            # Could not parse date
                            results['skipped'].append({
                                'video_id': video_id,
                                'title': item['title'],
                                'reason': f"Date parse error: {str(e)}"
                            })
                    else:
                        # No date delimiter found
                        results['skipped'].append({
                            'video_id': video_id,
                            'title': item['title'],
                            'reason': "No &&& delimiter found in description"
                        })
                
                except Exception as e:
                    results['errors'].append(f"Error processing video {video_id}: {str(e)}")
            
            # Sort by date (newest first)
            items_with_dates.sort(key=lambda x: x['date'], reverse=True)
            
            # Update positions in playlist
            for new_position, item in enumerate(items_with_dates):
                try:
                    # Move existing    playlist item to the desired position.
                    # Updating in place is more reliable than remove+reinsert.
                    youtube = self._get_thread_client()
                    youtube.playlistItems().update(
                        part='snippet',
                        body={
                            'id': item['playlist_item_id'],
                            'snippet': {
                                'playlistId': playlist_id,
                                'resourceId': {
                                    'kind': 'youtube#video',
                                    'videoId': item['video_id']
                                },
                                'position': new_position
                            }
                        }
                    ).execute()
                    
                    results['sorted_count'] += 1
                
                except Exception as e:
                    results['errors'].append(
                        f"Failed to reorder video '{item['title']}' to position {new_position}: {str(e)}"
                    )
            
            return results
        
        except HttpError as e:
            raise Exception(f"Failed to sort playlist by description date: {e}")

    def sort_playlists_by_name_and_description(self, playlists_to_sort: Union[List[str], set[str]]) -> Dict[str, dict]:
        """
        Sort multiple playlists by resolving each playlist name to ID, then sorting by description date.
        
        Args:
            playlists_to_sort: Playlist names to sort
        
        Returns:
            Dictionary mapping playlist name -> sort status result
        """
        statuses = {}
        for playlist in playlists_to_sort:
            # Resolve playlist name to playlist ID first
            playlist_id = self.get_playlist_id_by_name(playlist)

            if playlist_id is None:
                statuses[playlist] = {
                    'sorted_count': 0,
                    'skipped': [],
                    'errors': [f"Playlist not found: {playlist}"]
                }
                continue

            # Sort this playlist by description date
            statuses[playlist] = self.sort_playlist_by_id_and_description_date(playlist_id)

        return statuses
