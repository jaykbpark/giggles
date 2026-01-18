# local server endpoints using fastapi
from fastapi import FastAPI,Form,File,UploadFile
from fastapi.middleware.cors import CORSMiddleware
from datetime import datetime
from backend.objects.RequestObjects import RequestSearchObject, RequestVideoObject
from backend.objects.ResponseObjects import ResponseTagsObject, ResponseVideoObject
from backend.database_operations import DatabaseOperations
from backend.preprocessing.processing_manager import ProcessingManager

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
async def create_video(
    videoId: str = Form(...),
    title: str = Form(...),
    timestamp: str = Form(...),
    videoData: UploadFile = File(...)
):
    video_bytes = await videoData.read()

    # Create your RequestVideoObject instance
    video = RequestVideoObject(
        videoId=videoId,
        title=title,
        timestamp=timestamp,
        videoData=video_bytes
    )
    pm = ProcessingManager(video)
    db = DatabaseOperations()
    # preprocessing
    tags = db.query_tags_table_get_tags()
    ((transcription, tags), condensed_transcript) = pm.create_transcript_from_audio(tags)
    # video _ tags table insertion
    
    db.insert_video_table(video.videoId, video.title, transcription, video.timestamp)
    for tag in tags:
        db.insert_tags_table(tag, video.videoId)
    # vectorizing table insertion
    frames = pm.split_video_to_frames(3)
    return {"message": "Item created"}

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