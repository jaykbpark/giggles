# local server endpoints using fastapi
from fastapi import FastAPI
from objects.RequestObjects import RequestSearchObject, RequestVideoObject
from objects.ResponseObjects import ResponseTagsObject, ResponseVideoObject

app = FastAPI()

@app.get("/videos")
def get_videos():
    print("GOT VIDEOS")
    return # DB 

@app.post("/videos")
async def create_video(video: RequestVideoObject):
    print("CREATED VIDEO")
    return video