

from __future__ import annotations
from typing import TYPE_CHECKING

# from services import YouTubeService
# from services.DirectoryRecordService import DirectoryRecordService
# from services.FileSelectionService import FileSelectionService

if TYPE_CHECKING:
    from services.DirectoryRecordService import DirectoryRecordService
    from services.FileSelectionService import FileSelectionService
    from services.YouTubeService import YouTubeService


class Context:

    def __init__(
        self, 
        directory_record_service : DirectoryRecordService,
        file_selection_service : FileSelectionService,
        youtube_service : YouTubeService,
        ) -> None:

        # Save context
        self.file_service = file_selection_service
        self.directory_record_service = directory_record_service
        self.youtube_service = youtube_service


        pass