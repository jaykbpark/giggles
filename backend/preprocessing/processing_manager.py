import ffmpeg 
import numpy as np
import tempfile
from transcript_processor import TranscriptProcessor
from objects.RequestObjects import RequestVideoObject
class ProcessingManager():
    def __init__(self,requestVideoObject:RequestVideoObject):
        video_bytes = requestVideoObject.videoData
        self.audio_bytes =  self.extract_audio(video_bytes)
        self.video_bytes = video_bytes
        self.width = 1920 #1920
        self.height = 1080 #1080
        self.requestVideoObject = requestVideoObject
   
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

    def split_video_to_frames(self,fps):
        frame_size = self.width * self.height * 3
        with tempfile.NamedTemporaryFile(suffix=".mp4") as tmp:
            tmp.write(self.video_bytes)
            tmp.flush()

            process = (
                ffmpeg
                .input(tmp.name)
                .filter('fps', fps=fps)
                .output('pipe:1', format='rawvideo', pix_fmt='rgb24')
                .run_async(pipe_stdout=True, pipe_stderr=True)
            )

            frames = []
            while True:
                raw_frame = process.stdout.read(frame_size)
                if len(raw_frame) < frame_size:
                    break
                frame = np.frombuffer(raw_frame, np.uint8).reshape((self.height, self.width, 3))
                frames.append(frame)

            process.wait()
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