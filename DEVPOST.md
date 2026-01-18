# Clip

**Your memories, always within reach.**

Say "Clip that" to save the last 30 seconds. Say "Hey Clip" to ask what happened. Built for Meta Ray-Ban glasses.

---

## The Problem

**For everyone:** You're with friends, something hilarious happens, and by the time you reach for your phone—it's over. The moment is gone.

**For those with memory challenges:** Forgetting isn't just inconvenient. For people with early-stage Alzheimer's or cognitive decline, losing track of conversations, faces, and daily moments creates isolation and anxiety. Caregivers repeat the same information. Patients feel like they're losing themselves.

---

## What Clip Does

### Capture Without Interrupting
Wear your Meta Ray-Ban glasses. Live your life. When something worth keeping happens:

> "Clip that."

Clip saves the **last 30 seconds** of video and audio. No fumbling. No missed moments. The conversation continues uninterrupted.

### Ask Your Memories
Later, when you can't remember:

> "Hey Clip, what did Sarah say about the birthday party?"

Clip searches your captured moments, finds the relevant clip, and **speaks the answer back to you**. Like having a personal assistant who was there for everything.

---

## How It Works

```
You → "Clip that"
         ↓
    30-second video/audio saved
         ↓
    Transcribed (Whisper)
         ↓
    Vectorized for semantic search (Milvus)
         ↓
You → "What did we talk about at dinner?"
         ↓
    Semantic search finds relevant clips
         ↓
    Gemini generates conversational response
         ↓
    ElevenLabs speaks it back to you
```

---

## Tech Stack

| Layer | Tech |
|-------|------|
| Hardware | Meta Ray-Ban glasses |
| iOS App | SwiftUI, iOS 26 Liquid Glass |
| Wake Word | Native `SFSpeechRecognizer` (on-device, offline) |
| Video/Audio | 30-second rolling buffer, AVFoundation |
| Transcription | OpenAI Whisper |
| Vector DB | Milvus (semantic embeddings) |
| Search | Sentence transformers |
| LLM | Google Gemini |
| Voice | ElevenLabs TTS |
| Backend | FastAPI + SQLite |

---

## Key Features

- **Hands-free capture** — Just speak, no phone interaction needed
- **Semantic search** — Find clips by meaning, not keywords ("that funny story" works)
- **Conversational recall** — Ask questions in natural language, get spoken answers
- **On-device wake word** — Works offline, instant response
- **Timeline UI** — Browse all your moments chronologically
- **30-second buffer** — Captures what *just happened*, not what's about to happen

---

## Use Cases

### For Fun
- Capture spontaneous jokes without killing the vibe
- Save travel moments while staying present
- Record conversations you want to remember
- Build a searchable archive of your life's highlights

### For Accessibility
- **Alzheimer's/dementia support** — Replay recent conversations, remember names and faces
- **Caregiver tool** — "What did the doctor say?" answered instantly
- **Cognitive decline** — External memory that's always listening
- **Anxiety reduction** — Knowing you can always check what happened

---

## Demo

1. Put on glasses
2. Say "Clip that" → last 30 seconds saved
3. Say "Hey Clip, what happened?" → Clip tells you

That's it. Memory, externalized.

---

## What's Next

- [ ] Multi-user support (family caregivers)
- [ ] Daily summaries ("Here's what happened today")
- [ ] Face recognition ("Who was I talking to?")
- [ ] Proactive reminders ("You have a doctor's appointment tomorrow based on what Sarah mentioned")
- [ ] Privacy controls (auto-delete, blur faces, mute zones)

---

## Built At

Made during [Hackathon Name] — because forgetting shouldn't be inevitable.

---

## Team

[Your names here]

---

*"The best camera is the one you have with you. The best memory is the one you don't have to rely on."*
