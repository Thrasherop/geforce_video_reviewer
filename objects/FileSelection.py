"""
FileSelection - Data classes for file and directory selection results
"""

from typing import List, Optional
from pathlib import Path
from abc import ABC, abstractmethod


class FileSelection(ABC):
    """
    Abstract base class for file selection results
    """
    
    def __init__(self):
        """Initialize the file selection"""
        pass
    
    @abstractmethod
    def get_paths(self) -> List[Path]:
        """
        Get all file paths from the selection
        
        Returns:
            List of Path objects representing selected files
        """
        pass
    
    @abstractmethod
    def get_selection_type(self) -> str:
        """
        Get the type of selection
        
        Returns:
            String representing the selection type ('directory' or 'file_list')
        """
        pass
    
    def __str__(self) -> str:
        """String representation of the selection"""
        paths = self.get_paths()
        return f"{self.get_selection_type()}: {len(paths)} file(s)"
    
    def __repr__(self) -> str:
        """Detailed string representation"""
        return f"{self.__class__.__name__}(paths={self.get_paths()})"


class DirectorySelection(FileSelection):
    """
    Represents a directory selection result
    Contains the directory path and optionally all files within it
    """
    
    def __init__(self, 
                 directory_path: str,
                 file_extensions: Optional[List[str]] = None,
                 recursive: bool = False):
        """
        Initialize directory selection
        
        Args:
            directory_path: Path to the selected directory
            file_extensions: Optional list of file extensions to filter (e.g., ['.mp4', '.avi'])
            recursive: Whether to include files from subdirectories
        """
        super().__init__()
        self.directory_path = Path(directory_path)
        self.file_extensions = file_extensions
        self.recursive = recursive
        self._files: Optional[List[Path]] = None
    
    def get_paths(self) -> List[Path]:
        """
        Get all file paths from the directory
        
        Returns:
            List of Path objects for files in the directory
        """
        if self._files is None:
            self._scan_directory()
        return self._files
    
    def _scan_directory(self) -> None:
        """Scan the directory and collect file paths"""
        self._files = []
        
        if not self.directory_path.exists():
            return
        
        if not self.directory_path.is_dir():
            return
        
        # Choose glob pattern based on recursive flag
        pattern = "**/*" if self.recursive else "*"
        
        # Scan directory
        for path in self.directory_path.glob(pattern):
            if path.is_file():
                # Filter by extension if specified
                if self.file_extensions:
                    if path.suffix.lower() in [ext.lower() for ext in self.file_extensions]:
                        self._files.append(path)
                else:
                    self._files.append(path)
        
        # Sort files by name
        self._files.sort()
    
    def get_selection_type(self) -> str:
        """Get the selection type"""
        return "directory"
    
    def get_directory(self) -> Path:
        """
        Get the directory path
        
        Returns:
            Path object for the selected directory
        """
        return self.directory_path
    
    def __str__(self) -> str:
        """String representation"""
        recursive_str = " (recursive)" if self.recursive else ""
        ext_str = f" [{', '.join(self.file_extensions)}]" if self.file_extensions else ""
        return f"Directory: {self.directory_path}{recursive_str}{ext_str} - {len(self.get_paths())} file(s)"


class FileListSelection(FileSelection):
    """
    Represents a multiple file selection result
    Contains a list of explicitly selected file paths
    """
    
    def __init__(self, file_paths: List[str]):
        """
        Initialize file list selection
        
        Args:
            file_paths: List of file paths that were selected
        """
        super().__init__()
        self.file_paths = [Path(fp) for fp in file_paths]
    
    def get_paths(self) -> List[Path]:
        """
        Get all selected file paths
        
        Returns:
            List of Path objects for selected files
        """
        # Filter to only existing files
        return [path for path in self.file_paths if path.exists() and path.is_file()]
    
    def get_selection_type(self) -> str:
        """Get the selection type"""
        return "file_list"
    
    def __str__(self) -> str:
        """String representation"""
        paths = self.get_paths()
        if not paths:
            return "File List: 0 files"
        elif len(paths) == 1:
            return f"File List: {paths[0]}"
        else:
            return f"File List: {len(paths)} files"
