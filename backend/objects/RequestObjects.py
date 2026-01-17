from pydantic import BaseModel

class RequestSearchObject(BaseModel):
    type: str
    input: str

class RequestVideoObject(BaseModel):
    videoId: str
    title: str
    timestamp: str
    videoData: bytes

# we're transcript + tags generation
'''
To convert a bytearray to video frames in Python, 
the primary approach is to use the numpy library to 
reshape the raw bytes into an image array and then 
use libraries like OpenCV or Pillow to process or 
save those arrays as video frames or images. 

get video metadata
'''