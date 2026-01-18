# local server endpoints using fastapi
from fastapi import FastAPI,Form,File,UploadFile
from fastapi.middleware.cors import CORSMiddleware
from datetime import datetime
from backend.objects.RequestObjects import RequestSearchObject, RequestVideoObject
from backend.objects.ResponseObjects import ResponseTagsObject, ResponseVideoObject
from backend.database_operations import DatabaseOperations
from backend.preprocessing.processing_manager import ProcessingManager
from backend.vectorizer import Vectorizer, get_vectorizer
import uvicorn
app = FastAPI()

# Preload the vectorizer model at startup so first search is fast
@app.on_event("startup")
async def startup_event():
    print("🚀 Preloading CLIP model...")
    get_vectorizer()  # This caches the model
    print("✅ CLIP model ready!")

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
    try:
        vectorizer = get_vectorizer()  # Use cached singleton
        # preprocessing
        tags = db.query_tags_table_get_tags()
        ((transcription, tags), condensed_transcript) = pm.create_transcript_from_audio(tags)
        # video _ tags table insertion
        
        db.insert_video_table(video.videoId, video.title, transcription, video.timestamp)
        for tag in tags:
            db.insert_tags_table(tag, video.videoId)
        # vectorizing table insertion
        frames = pm.split_video_to_frames(3)
        image_vectors = vectorizer.encode_images(frames)
        
        for image_vector in image_vectors:
            db.insert_vector_table(image_vector,videoId)
            
        transcription_vector = vectorizer.encode_text(condensed_transcript)
        db.insert_vector_table(transcription_vector,videoId)
        db.close()
        return {"message": "Item created"}
    finally:
        db.close()

# get all videos, PAGINATION NOT IMPLEMENTED YET
@app.get("/api/videos")
def get_videos(limit: int = 50, offset: int = 0):
    db = DatabaseOperations()
    try:
        all_videos = db.query_video_table_all() # need this to be in the proper format
        # format: [(id, title, transcript, timestamp), (), ()]
        all_video_objects = []
        for (id, title, transcript, timestamp) in all_videos:
            tags = db.query_tags_table_by_video_id(id)
            video_object = ResponseVideoObject(
                videoId=id,
                title=title,
                transcript=transcript,
                timestamp=timestamp,
                tags=tags
            )
            all_video_objects.append(video_object)
        db.close()
        return {"success": True, "result": all_video_objects}
    finally:
        db.close()


@app.get("/api/tags")
def get_videos(limit: int = 50, offset: int = 0):
    db = DatabaseOperations()
    try:
        all_tags = db.query_tags_table_get_tags() 
        db.close()
        return {"success": True, "result": all_tags}
    finally:
        db.close()

# retrieve full metadata + transcript for a specific video
@app.get("/api/videos/{videoId}")
def get_video(videoId):
    db = DatabaseOperations()
    try:
        id, title, transcript, timestamp = db.query_video_table(videoId)
        tags = db.query_tags_table_by_video_id(id)
        result = ResponseVideoObject(
            videoId=id,
            title=title,
            transcript=transcript,
            timestamp=timestamp,
            tags=tags
        )
        db.close()
        return {"success": True, "result": result}
    finally:
        db.close()

@app.get("/api/search/")
def search(type,input):
    db = DatabaseOperations()
    try:
        if type == "tag":
            videos = db.get_videos_from_tags(input)
            video_objects = []
            for (id, title, transcript, timestamp) in videos:
                tags = db.query_tags_table_by_video_id(id)
                video_object = ResponseVideoObject(
                    videoId=id,
                    title=title,
                    transcript=transcript,
                    timestamp=timestamp,
                    tags=tags
                )
                video_objects.append(video_object)
            return video_objects
        else:
            vectorizer = get_vectorizer()  # Use cached singleton instead of loading model each time
            encoded_vector = vectorizer.encode_text(input)
            result = db.search_vector_table(encoded_vector)
            seen = set()
            unique_video_ids = [
                item['entity']['video_id'] 
                for item in result[0] 
                if item['entity']['video_id'] not in seen and not seen.add(item['entity']['video_id'])
            ][:3]
            
            video_objs = []
            for video_id in unique_video_ids:
                video_objs.append(get_video(video_id)["result"])
            return video_objs
    finally:
        db.close()
if __name__ == "__main__":
    uvicorn.run(app, port=8000)
