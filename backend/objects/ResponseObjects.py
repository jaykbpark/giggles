from pydantic import BaseModel

class ResponseTagsObject(BaseModel):
    def __init__(self, tags):
        self.tags = tags

class ResponseVideoObject(BaseModel):
    success: bool
    videoId: str
    tags: list[str]
    transcript: str
