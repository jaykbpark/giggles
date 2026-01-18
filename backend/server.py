# local server endpoints using fastapi
from fastapi import FastAPI
from objects.RequestObjects import RequestSearchObject, RequestVideoObject
from objects.ResponseObjects import ResponseTagsObject, ResponseVideoObject

app = FastAPI()

# upload video
@app.post("/api/videos")
async def create_video(video: RequestVideoObject):
    # SQL INSERTION/CREATION QUERY HERE
    return video

# get all videos
@app.get("/api/videos")
def get_videos(limit: int = 50, offset: int = 0):
    # SQL DATABASE QUERY HERE
    return

# retrieve full metadata + transcript for a specific video
@app.get("/api/video/:videoId")
def get_video(videoId):
    # SQL DATANASE QUERY HERE
    return

@app.get("/api/search")
def search(search: RequestSearchObject):
    return