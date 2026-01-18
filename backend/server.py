# local server endpoints using fastapi
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from datetime import datetime
from objects.RequestObjects import RequestSearchObject, RequestVideoObject
from objects.ResponseObjects import ResponseTagsObject, ResponseVideoObject
from database_operations import DatabaseOperations
from preprocessing.processing_manager import ProcessingManager

app = FastAPI()

# Allow CORS for iOS app
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Health check endpoint
@app.get("/health")
def health_check():
    return {
        "status": "ok",
        "service": "clip-backend",
        "timestamp": datetime.utcnow().isoformat()
    }

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