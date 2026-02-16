import os
from abc import ABC, abstractmethod


class UserAction(ABC):
    action_type = "base"

    def __init__(self, folder_path):
        self.folder_path = os.path.normpath(folder_path)

    @abstractmethod
    def apply(self):
        pass

    @abstractmethod
    def undo(self):
        pass

    def redo(self):
        return self.apply()

    @abstractmethod
    def to_record(self):
        pass

    @classmethod
    @abstractmethod
    def from_record(cls, record):
        pass

