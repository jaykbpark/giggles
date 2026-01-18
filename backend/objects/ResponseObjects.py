from pydantic import BaseModel
from typing import List

class ResponseTagsObject(BaseModel):
    def __init__(self, tags):
        self.tags = tags

class ResponseVideoObject(BaseModel):
    videoId: str
    title: str
    transcript: str
    timestamp: str
    tags: List[str] = []
