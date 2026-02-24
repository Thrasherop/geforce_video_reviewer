
from enum import Enum

class YoutubePrivacySetting(Enum):
    PUBLIC = "public"
    PRIVATE = "private"
    UNLISTED = "unlisted"

    
    def __str__(self) -> str:
        """Return the category ID as a string"""
        return self.value
    
    @property
    def id(self) -> str:
        """Get the category ID"""
        return self.value
    
    @property
    def name_display(self) -> str:
        """Get a human-readable category name"""
        return self.name.replace('_', ' ').title()
