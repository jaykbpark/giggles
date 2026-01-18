from google import genai

# given audio in bytes
# make it into transcript text
# categorize (using gemini or elevenlabs) and look in db and get tags

client = genai.Client()

response = client.models.generate_content(
    model="gemini-3-flash-preview",
    contents="Explain how AI works in a few words",
)

print(response.text)

# inputs into gemini and processes, puts tags in, checks against db