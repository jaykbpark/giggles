import ffmpeg 
import numpy as np
import tempfile
from io import BytesIO
from backend.preprocessing.transcript_processor import TranscriptProcessor
from backend.objects.RequestObjects import RequestVideoObject
class ProcessingManager():
    def __init__(self,requestVideoObject:RequestVideoObject):
        video_bytes = requestVideoObject.videoData
        self.requestVideoObject = requestVideoObject
        self.video_bytes = video_bytes
        
        # Extract metadata and audio
        self.set_dimensions_from_metadata(video_bytes)
        self.audio_bytes = self.extract_audio(video_bytes)
    
    def set_dimensions_from_metadata(self, video_bytes: bytes):
        with tempfile.NamedTemporaryFile(suffix=".mp4") as tmp:
            tmp.write(video_bytes)
            tmp.flush()
            
            probe = ffmpeg.probe(tmp.name)
            video_stream = next((stream for stream in probe['streams'] if stream['codec_type'] == 'video'), None)
            
            if video_stream is None:
                raise ValueError("No video stream found in the provided data.")

            # Store original dimensions (before rotation) for raw frame extraction
            self.original_width = int(video_stream['width'])
            self.original_height = int(video_stream['height'])

            # Detect rotation from metadata
            self.rotation = 0
            if 'tags' in video_stream and 'rotate' in video_stream['tags']:
                self.rotation = int(video_stream['tags']['rotate'])
            # Also check side_data for rotation (newer ffmpeg)
            if 'side_data_list' in video_stream:
                for side_data in video_stream['side_data_list']:
                    if side_data.get('side_data_type') == 'Display Matrix' and 'rotation' in side_data:
                        self.rotation = int(side_data['rotation'])
            
            # Final dimensions after rotation is applied
            if self.rotation in [90, 270, -90, -270]:
                self.width, self.height = self.original_height, self.original_width
            else:
                self.width, self.height = self.original_width, self.original_height
            
            print(f"📹 Video: {self.original_width}x{self.original_height}, rotation={self.rotation}, final={self.width}x{self.height}")
                
    def extract_audio(self, video_bytes: bytes):
        with tempfile.NamedTemporaryFile(suffix=".mp4") as tmp:
            tmp.write(video_bytes)
            tmp.flush()

            out, _ = (
                ffmpeg
                .input(tmp.name)
                .output('pipe:1', format='wav')
                .run(capture_stdout=True, capture_stderr=True)
            )
        return out

    def split_video_to_frames(self, fps):
        """Extract frames from video, properly handling rotation.
        
        Returns PIL Images that CLIP can directly preprocess.
        """
        from PIL import Image
        
        with tempfile.NamedTemporaryFile(suffix=".mp4") as tmp:
            tmp.write(self.video_bytes)
            tmp.flush()

            # Build ffmpeg pipeline
            stream = ffmpeg.input(tmp.name)
            
            # Apply rotation correction based on metadata
            # This ensures raw output matches the intended orientation
            if self.rotation == 90 or self.rotation == -270:
                stream = stream.filter('transpose', 1)  # 90 clockwise
            elif self.rotation == 180 or self.rotation == -180:
                stream = stream.filter('transpose', 1).filter('transpose', 1)  # 180
            elif self.rotation == 270 or self.rotation == -90:
                stream = stream.filter('transpose', 2)  # 90 counter-clockwise
            
            # Sample at target fps
            stream = stream.filter('fps', fps=fps)
            
            # Scale to max 320 on the longer side, preserving aspect ratio
            # Use scale2ref or just scale with force_original_aspect_ratio
            stream = stream.filter('scale', 
                                   'min(320,iw)', 'min(320,ih)', 
                                   force_original_aspect_ratio='decrease')
            
            # Output as JPEG images (avoids dimension calculation issues)
            process = (
                stream
                .output('pipe:1', format='image2pipe', vcodec='mjpeg', q=2)
                .run_async(pipe_stdout=True, pipe_stderr=True)
            )

            # Read JPEG frames from pipe
            frames = []
            jpeg_data = b''
            
            while True:
                chunk = process.stdout.read(4096)
                if not chunk:
                    break
                jpeg_data += chunk
                
                # Find JPEG boundaries (FFD8 start, FFD9 end)
                while True:
                    start = jpeg_data.find(b'\xff\xd8')
                    if start == -1:
                        break
                    end = jpeg_data.find(b'\xff\xd9', start + 2)
                    if end == -1:
                        break
                    
                    # Extract complete JPEG
                    jpeg_bytes = jpeg_data[start:end + 2]
                    jpeg_data = jpeg_data[end + 2:]
                    
                    try:
                        img = Image.open(BytesIO(jpeg_bytes))
                        frames.append(img.copy())  # Copy to detach from buffer
                        img.close()
                    except Exception as e:
                        print(f"⚠️ Failed to decode frame: {e}")

            process.wait()
            
        print(f"📹 Extracted {len(frames)} frames at {fps} fps")
        return frames
        
        
    def create_transcript_from_audio(self,tags):
        transcript_processer = TranscriptProcessor()
        transcription, condensed_transcript, tags = transcript_processer.process_audio(self.audio_bytes,tags)
        return ((transcription, tags),condensed_transcript)        

    
    
# with open('test.mp4', 'rb') as f:
#     video_bytes = f.read()

# # Initialize the ProcessingManager
# manager = ProcessingManager(video_bytes)

# # Split video into frames
# frames = manager.split_video_to_frames(fps=3)
# print(f"Extracted {len(frames)} frames")

# # Optional: show the first frame using matplotlib
# import matplotlib.pyplot as plt

# if frames:
#     plt.imshow(frames[0])
#     plt.axis('off')
#     plt.show()

# with open('test.mp4', 'rb') as f:
#     video_bytes = f.read()

# with open("my_file.wav", "wb") as binary_file:
#     binary_file.write(video_bytes)