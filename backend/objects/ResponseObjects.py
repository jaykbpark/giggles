from pydantic import BaseModel

class ResponseTagsObject(BaseModel):
    def __init__(self, tags):
        self.tags = tags

class ResponseVideoObject(BaseModel):
    def __init__(self, vidId, transcript, tags):
        self.vidId = vidId
        self.transcript = transcript
        self.tags = tags