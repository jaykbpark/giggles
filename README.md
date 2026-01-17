# Clip

> Voice-activated memory capture for Meta Ray-Ban glasses. Say "Clip that" and save the last 30 seconds forever.

Built for a university hackathon. iOS 26 + SwiftUI with Liquid Glass design.

---

## What It Does

Say **"Clip that"** while wearing your Meta Ray-Ban glasses → App automatically saves the last 30 seconds of video/audio → Transcribes it → Makes it searchable.

Perfect for capturing those "I wish I recorded that" moments without fumbling with your phone.

---

## Features

- 🎙️ **Voice activation** - Just say "Clip that"
- 📱 **Beautiful timeline** - See all your moments in a clean vertical timeline
- 🔍 **Search** - Find moments by what was said
- 🎨 **Liquid Glass UI** - iOS 26's new glass effects everywhere

---

## Setup

1. **Open in Xcode:**
   ```bash
   open frontend/nw2025.xcodeproj
   ```

2. **Build & Run:**
   - Select iPhone simulator or your device
   - Press ⌘R

3. **That's it!** The app uses mock data so you can see the UI without glasses.

---

## Tech Stack

- SwiftUI + iOS 26
- Liquid Glass design system
- Native speech recognition (on-device)
- MVVM architecture

---

## Project Structure

```
frontend/ClipApp/
├── App/              # App entry point
├── Core/             # Managers, navigation, design system
├── Features/         # Timeline, moment cards, detail view
├── Models/           # Data models
└── Services/         # API client, mock data
```

---

## How It Works

1. **Wake Word Detection** - Listens for "Clip that" using iOS `SFSpeechRecognizer`
2. **Capture** - Saves last 30 seconds of video to Photo Library
3. **Transcribe** - Converts audio to text (on-device)
4. **Store** - Saves transcript + metadata
5. **Search** - Semantic search finds moments by content

---

## Current Status

✅ UI complete with warm minimal design  
✅ Wake word detection working  
🔄 Waiting on Meta SDK integration for real glasses  
🔄 Backend API integration pending  

---

## Demo

The app works in demo mode with mock data. You can:
- Browse the timeline
- Search moments
- View transcripts
- See the beautiful Liquid Glass UI

Full functionality requires Meta Ray-Ban glasses connected via Meta Wearables SDK.

---

## Built With

- Swift 6.2
- SwiftUI
- iOS 26 Liquid Glass
- Xcode 26.2

---

**Made at [Hackathon Name] 🚀**
