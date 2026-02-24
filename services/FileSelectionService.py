"""
FileSelectionService - A service for selecting files and directories
Provides methods for interactive file and directory selection using GUI dialogs
"""

import os
import tkinter as tk
from tkinter import filedialog
from typing import Optional, List, Union
from pathlib import Path

from objects.FileSelection import FileSelection, DirectorySelection, FileListSelection


class FileSelectionService:
    """
    A service class for file and directory selection
    
    Provides methods for:
    - Selecting multiple files
    - Selecting a directory
    - Selecting with file type filters
    """
    
    def __init__(self, initial_dir: str = r"C:\Users\ultra\Videos"):
        """
        Initialize the file selection service
        
        Args:
            initial_dir: Optional initial directory to open file dialogs in
        """
        self.initial_dir = initial_dir or os.getcwd()
        self._root = None
    
    def _init_tk(self) -> None:
        """Initialize Tkinter root window (hidden)"""
        if self._root is None:
            self._root = tk.Tk()
            self._root.withdraw()  # Hide the main window
    
    def _destroy_tk(self) -> None:
        """Destroy Tkinter root window"""
        if self._root is not None:
            self._root.destroy()
            self._root = None
    
    def select_files(self,
                     title: str = "Select Files",
                     file_types: Optional[List[tuple]] = None,
                     initial_dir: Optional[str] = None) -> FileListSelection:
        """
        Open a file dialog to select multiple files
        
        Args:
            title: Dialog window title
            file_types: List of file type filters, e.g., [("Video files", "*.mp4 *.avi"), ("All files", "*.*")]
            initial_dir: Optional initial directory (overrides instance default)
        
        Returns:
            FileListSelection object containing the selected files
        
        Example:
            service = FileSelectionService()
            selection = service.select_files(
                title="Select video files",
                file_types=[("Video files", "*.mp4 *.avi *.mkv"), ("All files", "*.*")]
            )
            
            for file_path in selection.get_paths():
                print(f"Selected: {file_path}")
        """
        self._init_tk()
        
        try:
            # Set up file types
            if file_types is None:
                file_types = [("All files", "*.*")]
            
            # Open file dialog
            files = filedialog.askopenfilenames(
                title=title,
                initialdir=initial_dir or self.initial_dir,
                filetypes=file_types
            )
            
            # Convert to list (askopenfilenames returns tuple)
            file_list = list(files) if files else []
            
            return FileListSelection(file_list)
        
        finally:
            self._destroy_tk()
    
    def select_directory(self,
                        title: str = "Select Directory",
                        initial_dir: Optional[str] = None,
                        file_extensions: Optional[List[str]] = None,
                        recursive: bool = False) -> DirectorySelection:
        """
        Open a dialog to select a directory
        
        Args:
            title: Dialog window title
            initial_dir: Optional initial directory (overrides instance default)
            file_extensions: Optional list of file extensions to filter (e.g., ['.mp4', '.avi'])
            recursive: Whether to include files from subdirectories
        
        Returns:
            DirectorySelection object containing the directory and its files
        
        Example:
            service = FileSelectionService()
            selection = service.select_directory(
                title="Select video directory",
                file_extensions=['.mp4', '.avi'],
                recursive=True
            )
            
            print(f"Directory: {selection.get_directory()}")
            print(f"Files found: {len(selection.get_paths())}")
            
            for file_path in selection.get_paths():
                print(f"  - {file_path}")
        """
        self._init_tk()
        
        try:
            # Open directory dialog
            directory = filedialog.askdirectory(
                title=title,
                initialdir=initial_dir or self.initial_dir
            )
            
            if not directory:
                # Return empty directory selection if cancelled
                directory = ""
            
            return DirectorySelection(
                directory_path=directory,
                file_extensions=file_extensions,
                recursive=recursive
            )
        
        finally:
            self._destroy_tk()
    
    def select_file_or_directory(self,
                                 prefer_directory: bool = False,
                                 **kwargs) -> Union[FileListSelection, DirectorySelection]:
        """
        Allow user to choose between file or directory selection
        
        Args:
            prefer_directory: If True, asks for directory first, otherwise files first
            **kwargs: Additional arguments to pass to the selection methods
        
        Returns:
            Either FileListSelection or DirectorySelection depending on user choice
        
        Note:
            This method prints prompts to console for user to choose the selection type
        """
        self._init_tk()
        
        try:
            # Create a simple dialog to ask the user
            choice = filedialog.askstring(
                "Selection Type",
                "Enter 'f' for files or 'd' for directory:"
            )
            
            if choice and choice.lower().startswith('d'):
                return self.select_directory(**kwargs)
            else:
                return self.select_files(**kwargs)
        
        finally:
            self._destroy_tk()
    
    def select_single_file(self,
                          title: str = "Select File",
                          file_types: Optional[List[tuple]] = None,
                          initial_dir: Optional[str] = None) -> Optional[Path]:
        """
        Open a file dialog to select a single file
        
        Args:
            title: Dialog window title
            file_types: List of file type filters
            initial_dir: Optional initial directory (overrides instance default)
        
        Returns:
            Path object for the selected file, or None if cancelled
        
        Example:
            service = FileSelectionService()
            file_path = service.select_single_file(
                title="Select a video file",
                file_types=[("Video files", "*.mp4 *.avi")]
            )
            
            if file_path:
                print(f"Selected: {file_path}")
        """
        self._init_tk()
        
        try:
            # Set up file types
            if file_types is None:
                file_types = [("All files", "*.*")]
            
            # Open file dialog
            file = filedialog.askopenfilename(
                title=title,
                initialdir=initial_dir or self.initial_dir,
                filetypes=file_types
            )
            
            return Path(file) if file else None
        
        finally:
            self._destroy_tk()
