import os
from dotenv import load_dotenv
from io import BytesIO
import requests
from elevenlabs import ElevenLabs
from google import genai
from pathlib import Path
from backend.database_operations import DatabaseOperations
import json

'''
# test area
load_dotenv()
elevenlabs = ElevenLabs(
    api_key=os.getenv("ELEVENLABS_API_KEY")
)
path = Path("C:/Users/tsuna/OneDrive/Documents/Sound Recordings/erik.m4a")
audio_bytes = path.read_bytes()
audio_data = BytesIO(audio_bytes)
# use elevenlabs to convert speech to text
transcription = elevenlabs.speech_to_text.convert(
    file=audio_data,
    model_id="scribe_v2",
    tag_audio_events=True,
    language_code="eng",
    diarize=True,
)
print(transcription)
print('\n')
print(transcription.text)
'''

class TranscriptProcessor:
    # retrieve API keys
    def __init__(self):
        load_dotenv()
        self.elevenlabs = ElevenLabs(
            api_key=os.getenv("ELEVENLABS_API_KEY")
        )
        self.client = genai.Client()

    # audio data is taken in as bytes and processed,
    # using elevenlabs to convert speech to text
    def process_audio(self, audio_bytes, tags):
        audio_data = BytesIO(audio_bytes)
        # use elevenlabs to convert speech to text
        transcription = self.elevenlabs.speech_to_text.convert(
            file=audio_data,
            model_id="scribe_v2",
            tag_audio_events=True,
            language_code="eng",
            diarize=False,
        )
        transcription_text = transcription.text
        # list of tags string
        tags_string = ", ".join(tags)
        # generate tags (general) 5 tags max but if less is needed to less
        # give me tags + if greater than 300 characters
        prompt = f"Given the following InputPrompt, generate at most 3 lowercase tags that describe the transcript, generating suitable ones when needed or if applicable, matching with the tags: {tags_string}. If the prompt is over 300 characters condense it with minimal loss of context. Return in the format where 'tags' are a list and 'prompt' is a string (either condensed or original), in JSON format without anything like ```json ```. InputPrompt: {transcription_text}"
        response = self.client.models.generate_content(
            model="gemini-3-flash-preview",
            contents=prompt,
        )
        prompt_and_tags = json.loads(response.text)
        return (transcription_text, prompt_and_tags["prompt"], prompt_and_tags["tags"])

# inputs into gemini and processes, puts tags in, checks against db