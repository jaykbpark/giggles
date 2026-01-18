from pydantic import BaseModel

class ResponseTagsObject(BaseModel):
    def __init__(self, tags):
        self.tags = tags

class ResponseVideoObject(BaseModel):
    videoId: str
    title: str
    transcript: str
    timestamp: str
