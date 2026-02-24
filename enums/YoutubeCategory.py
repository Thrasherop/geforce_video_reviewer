"""
YouTube Category Enums

Official YouTube category IDs for video uploads
"""

from enum import Enum


class YouTubeCategory(Enum):
    """
    YouTube video categories with their official API IDs
    
    Usage:
        from enums import YouTubeCategory
        
        yt.upload_video(
            video_file='clip.mp4',
            title='My Video',
            category_id=YouTubeCategory.GAMING
        )
    """
    
    FILM_AND_ANIMATION = "1"
    AUTOS_AND_VEHICLES = "2"
    MUSIC = "10"
    PETS_AND_ANIMALS = "15"
    SPORTS = "17"
    TRAVEL_AND_EVENTS = "19"
    GAMING = "20"
    PEOPLE_AND_BLOGS = "22"
    COMEDY = "23"
    ENTERTAINMENT = "24"
    NEWS_AND_POLITICS = "25"
    HOWTO_AND_STYLE = "26"
    EDUCATION = "27"
    SCIENCE_AND_TECHNOLOGY = "28"
    NONPROFITS_AND_ACTIVISM = "29"
    
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
