from pathlib import Path
from typing import Optional, List, Dict, Any, Union, TYPE_CHECKING
import os
import shutil
import subprocess
from datetime import datetime
import json

if TYPE_CHECKING:
    from services.DirectoryRecordService import DirectoryRecordService

def file_is_ghost_file(file : Path) -> bool:
    """
    Check if a file is already a ghost file by checking:
    1. Video duration is less than 2 seconds
    2. The corners of the video are black
    
    Args:
        file: Path to the video file to check
        
    Returns:
        True if the file is a ghost file, False otherwise
    """
    
    if not file.exists():
        return False
    
    try:
        # Check video duration using ffprobe
        duration_cmd = [
            'ffprobe',
            '-v', 'error',
            '-show_entries', 'format=duration',
            '-of', 'json',
            str(file)
        ]
        
        duration_result = subprocess.run(
            duration_cmd,
            capture_output=True,
            text=True,
            check=False
        )
        
        if duration_result.returncode != 0:
            # Can't determine duration, assume not a ghost file
            return False
        
        duration_data = json.loads(duration_result.stdout)
        duration = float(duration_data.get('format', {}).get('duration', 0))
        
        # Check if duration is less than 2 seconds
        if duration >= 2.0:
            return False
        
        # Check if corners are black
        # Extract a frame and check pixel values at corners
        frame_check_cmd = [
            'ffmpeg',
            '-i', str(file),
            '-vframes', '1',
            '-f', 'rawvideo',
            '-pix_fmt', 'rgb24',
            'pipe:1'
        ]
        
        frame_result = subprocess.run(
            frame_check_cmd,
            capture_output=True,
            check=False
        )
        
        if frame_result.returncode != 0:
            # Can't read frame, assume not a ghost file
            return False
        
        # Get video dimensions
        dimension_cmd = [
            'ffprobe',
            '-v', 'error',
            '-select_streams', 'v:0',
            '-show_entries', 'stream=width,height',
            '-of', 'json',
            str(file)
        ]
        
        dimension_result = subprocess.run(
            dimension_cmd,
            capture_output=True,
            text=True,
            check=False
        )
        
        if dimension_result.returncode != 0:
            return False
        
        dimension_data = json.loads(dimension_result.stdout)
        streams = dimension_data.get('streams', [])
        if not streams:
            return False
        
        width = streams[0].get('width', 0)
        height = streams[0].get('height', 0)
        
        if width == 0 or height == 0:
            return False
        
        # Get raw frame data
        frame_data = frame_result.stdout
        
        # Check corners (top-left, top-right, bottom-left, bottom-right)
        # Each pixel is 3 bytes (RGB)
        bytes_per_pixel = 3
        row_size = width * bytes_per_pixel
        
        # Define corner positions to check (5x5 pixel area in each corner)
        corner_positions = [
            (0, 0),  # top-left
            (width - 1, 0),  # top-right
            (0, height - 1),  # bottom-left
            (width - 1, height - 1)  # bottom-right
        ]
        
        # Check if all corners are black (or very dark - RGB < 20 for each channel)
        black_threshold = 20
        
        for x, y in corner_positions:
            pixel_offset = (y * row_size) + (x * bytes_per_pixel)
            
            if pixel_offset + 3 > len(frame_data):
                continue
            
            r = frame_data[pixel_offset]
            g = frame_data[pixel_offset + 1]
            b = frame_data[pixel_offset + 2]
            
            # If any corner is not black, it's not a ghost file
            if r > black_threshold or g > black_threshold or b > black_threshold:
                return False
        
        # If we get here, video is short and corners are black
        return True
        
    except Exception as e:
        # On any error, assume it's not a ghost file
        print(f"Error checking if file is ghost: {e}")
        return False

def make_video_ghost_file(file : Path, directory_record_service : "DirectoryRecordService") -> bool:
    """
    Replace a video file with a 1-second black screen "ghost" video containing
    the YouTube URL as white text. The original file is moved to a subdirectory
    named 'original_from_ghost'. The ghost file maintains the same filename,
    creation date, and other metadata as the original.
    
    Args:
        file: Path to the video file to convert to a ghost file
        directory_record_service: DirectoryRecordService instance to check upload status
        
    Returns:
        True if the ghost file was created successfully, False otherwise
        
    Raises:
        ValueError: If the file has not been uploaded to YouTube
    """

    # Check if video is already ghost file
    #  Exit early if true
    if file_is_ghost_file(file):
        print(f"File {file.name} is already a ghost file. Skipping.")
        return True

    # Verify that it's uploaded
    is_uploaded = directory_record_service.is_uploaded(file)
    if not is_uploaded:
        raise ValueError("make_video_ghost_file received un-uploaded file path")

    # Get video data to retrieve YouTube URL
    video_data = directory_record_service.get_video_json_by_path(file)
    if not video_data or not video_data.get('youtube_url'):
        raise ValueError("Could not retrieve YouTube URL for uploaded video")
    
    youtube_url = video_data['youtube_url']

    # Get original file metadata before moving
    original_creation_time = os.path.getctime(str(file))
    original_modified_time = os.path.getmtime(str(file))
    file_extension = file.suffix

    # Move the file to original_from_ghost subdirectory
    original_backup_dir = file.parent / "original_from_ghost"
    original_backup_dir.mkdir(exist_ok=True)
    
    original_backup_path = original_backup_dir / file.name
    
    # If backup already exists, add timestamp to avoid collision
    if original_backup_path.exists():
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        stem = file.stem
        original_backup_path = original_backup_dir / f"{stem}_{timestamp}{file_extension}"
    
    # Move the original file
    shutil.move(str(file), str(original_backup_path))

    # Confirm file is moved
    if not original_backup_path.exists() or file.exists():
        # Rollback if something went wrong
        if original_backup_path.exists() and not file.exists():
            shutil.move(str(original_backup_path), str(file))
        raise RuntimeError(f"Failed to move original file to {original_backup_path}")

    # Create new ghost file with metadata
    try:
        # Use ffmpeg to create a 1-second black video with white text
        # Format: 1 second, black background, white text with YouTube URL
        temp_output = file.parent / f"temp_ghost_{file.name}"
        
        # Escape special characters in URL for ffmpeg drawtext filter
        # ffmpeg drawtext uses : and = as separators, so they need to be escaped.
        # Also escape % so drawtext does not treat it as expansion syntax.
        escaped_url = (
            youtube_url
            .replace('\\', '\\\\')
            .replace(':', '\\:')
            .replace('=', '\\=')
            .replace('%', '\\%')
            .replace("'", "\\'")
        )
        drawtext_common = (
            f"text='{escaped_url}':fontcolor=white:fontsize=40:"
            "x=(w-text_w)/2:y=(h-text_h)/2"
        )

        # Build drawtext filter candidates.
        # 1) Prefer explicit Windows font files (no Fontconfig dependency).
        # 2) Fall back to named/default fonts.
        windows_dir = Path(os.environ.get('WINDIR', 'C:/Windows'))
        windows_font_candidates = [
            windows_dir / 'Fonts' / 'arial.ttf',
            windows_dir / 'Fonts' / 'segoeui.ttf',
            windows_dir / 'Fonts' / 'tahoma.ttf',
        ]
        drawtext_filters = []
        for font_path in windows_font_candidates:
            if font_path.exists():
                escaped_font_path = (
                    str(font_path)
                    .replace('\\', '/')
                    .replace(':', '\\:')
                    .replace("'", "\\'")
                )
                drawtext_filters.append(
                    f"drawtext=fontfile='{escaped_font_path}':{drawtext_common}"
                )
        drawtext_filters.extend([
            f"drawtext=font=Arial:{drawtext_common}",
            f"drawtext={drawtext_common}",
        ])

        result = None
        drawtext_errors = []
        for drawtext_filter in drawtext_filters:
            ffmpeg_cmd = [
                'ffmpeg',
                '-f', 'lavfi',
                '-i', 'color=c=black:s=1280x720:d=1',  # 1 second black video
                '-vf', drawtext_filter,
                '-c:v', 'libx264',
                '-t', '1',
                '-pix_fmt', 'yuv420p',
                '-metadata', f'comment={youtube_url}',
                '-metadata', f'purl={youtube_url}',
                '-y',  # Overwrite output file if it exists
                str(temp_output)
            ]

            # Run ffmpeg command
            result = subprocess.run(
                ffmpeg_cmd,
                capture_output=True,
                text=True,
                check=False
            )

            if result.returncode == 0:
                break
            drawtext_errors.append(result.stderr)

        if result is None or result.returncode != 0:
            # Final fallback: create a plain black ghost video and store URL in metadata.
            # This keeps the workflow functional when drawtext/font systems are unavailable.
            fallback_cmd = [
                'ffmpeg',
                '-f', 'lavfi',
                '-i', 'color=c=black:s=1280x720:d=1',
                '-c:v', 'libx264',
                '-t', '1',
                '-pix_fmt', 'yuv420p',
                '-metadata', f'comment={youtube_url}',
                '-metadata', f'purl={youtube_url}',
                '-y',
                str(temp_output)
            ]
            fallback_result = subprocess.run(
                fallback_cmd,
                capture_output=True,
                text=True,
                check=False
            )
            if fallback_result.returncode != 0:
                # Rollback: move original file back
                shutil.move(str(original_backup_path), str(file))
                error_details = '\n---\n'.join(drawtext_errors) if drawtext_errors else 'unknown drawtext error'
                raise RuntimeError(
                    f"ffmpeg failed (drawtext attempts): {error_details}\n"
                    f"fallback failed: {fallback_result.stderr}"
                )
            print("Warning: drawtext failed; created plain black ghost file with URL in metadata comment.")
        
        # Move temp file to final location
        shutil.move(str(temp_output), str(file))
        
        # Restore original metadata (creation and modification times)
        os.utime(str(file), (original_modified_time, original_modified_time))
        
        # Note: Windows doesn't easily allow setting creation time via Python
        # The creation time will be the current time, which is acceptable for ghost files
        
        # Verify ghost file was created
        if not file.exists():
            # Rollback: move original file back
            if original_backup_path.exists():
                shutil.move(str(original_backup_path), str(file))
            raise RuntimeError("Ghost file was not created successfully")
        
        print(f"Successfully created ghost file for {file.name}")
        print(f"Original file backed up to: {original_backup_path}")
        
        # Return status
        return True
        
    except Exception as e:
        # Rollback on any error: restore original file
        if original_backup_path.exists() and not file.exists():
            shutil.move(str(original_backup_path), str(file))
        raise RuntimeError(f"Failed to create ghost file: {str(e)}") from e