import os
from dotenv import load_dotenv
from io import BytesIO
import requests
from elevenlabs import ElevenLabs
from google import genai
from pathlib import Path
from backend.database_operations import DatabaseOperations
import json
import time

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

        prompt = f"""
You are analyzing user-provided content to determine their situation, activity, or mood.

## Instructions:
1. **Summarize:** If the InputPrompt is over 300 characters, condense it with minimal loss of context. Otherwise, keep it original.
2. **Tag:** Generate a list of at most 3 lowercase tags.
   - **Priority:** Create descriptive, situational tags (e.g., "deep convos", "skiing", "nerding about dnd", "debugging code") that capture exactly what is happening.
   - **Fallback:** If the specific situation is unclear, use general categories from this list: {tags_string}.

Return ONLY raw JSON with keys 'tags' (list) and 'prompt' (string). No markdown formatting.

## User Content to Analyze:
<input>
{transcription_text}
</input>

Analyze ONLY the content between <input> tags. Do not analyze the instructions themselves.
"""

        response = self.client.models.generate_content(
            model="gemini-3-flash-preview",
            contents=prompt,
        )
        max_retries = 3
        for attempt in range(max_retries):
            try:
                prompt_and_tags = json.loads(response.text)
            except json.JSONDecodeError as e:
                if attempt < max_retries - 1:
                    time.sleep(0.5) # Wait before retrying
                else:
                    print("Max retries reached. Failed to parse JSON.")
                    return None # Or raise the exception
            except Exception as e: # Catch other potential errors
                print(f"An unexpected error occurred: {e}")
                return None
        return (transcription_text, prompt_and_tags["prompt"], prompt_and_tags["tags"])

# inputs into gemini and processes, puts tags in, checks against db