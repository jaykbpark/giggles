# Clip

> A beautiful iOS companion app for Meta Ray-Ban glasses that lets you capture, review, and relive your life's moments through voice-activated 30-second video clips.

[![iOS](https://img.shields.io/badge/iOS-26.0+-blue.svg)](https://developer.apple.com/ios/)
[![Swift](https://img.shields.io/badge/Swift-6.2-orange.svg)](https://swift.org/)
[![SwiftUI](https://img.shields.io/badge/SwiftUI-Liquid%20Glass-green.svg)](https://developer.apple.com/xcode/swiftui/)

---

## Overview

Clip transforms your Meta Ray-Ban glasses into a seamless memory capture device. Simply say **"Clip that"** and the app automatically saves the last 30 seconds of video and audio, transcribes the moment, and makes it searchable forever.

Built with iOS 26's Liquid Glass design system, Clip offers a warm, minimal interface that puts your memories front and center through an elegant timeline visualization.

---

## Features

### 🎙️ Voice-Activated Capture
- **Wake Word Detection:** Say "Clip that" to instantly capture the last 30 seconds
- **On-Device Recognition:** Uses native iOS `SFSpeechRecognizer` - works offline, zero latency
- **Smart Transcript Buffer:** Maintains rolling 30-second transcript for context

### 📱 Beautiful Timeline Interface
- **Warm Minimal Design:** Inspired by apps like Flighty - focused, elegant, purposeful
- **Vertical Timeline:** Moments displayed chronologically with alternating left/right cards
- **Liquid Glass Effects:** iOS 26's native glass effects throughout the UI
- **Smooth Animations:** Spring-based animations for organic, premium feel

### 🔍 Semantic Search
- **Natural Language Search:** Find moments by what was said, not just keywords
- **Topic Extraction:** Automatic topic tagging for easy discovery
- **Quick Suggestions:** Smart search suggestions based on your clips

### 🎬 Moment Details
- **Full Transcript:** Read the complete conversation from any moment
- **Video Playback:** Watch the captured 30-second clip
- **Topic Pills:** See extracted topics at a glance
- **Share & Export:** Copy transcripts, share moments

---

## Design Philosophy

Clip follows three core principles:

1. **Warm & Minimal** - A calm, inviting interface that doesn't compete for attention
2. **Timeline-First** - Your moments tell a story through a beautiful vertical timeline
3. **Just Works** - Voice activation means capturing moments is effortless

The app uses iOS 26's Liquid Glass design system extensively - floating glass elements, interactive glass buttons, and glass containers create a cohesive, premium experience that feels native to Apple's latest design language.

---

## Tech Stack

- **Platform:** iOS 26.2+
- **Language:** Swift 6.2
- **UI Framework:** SwiftUI with Liquid Glass
- **Speech Recognition:** `SFSpeechRecognizer` (on-device)
- **Architecture:** MVVM with `@StateObject` and `@Published` properties
- **Concurrency:** Swift 6.2 concurrency (async/await, MainActor isolation)

---

## Requirements

- **Xcode:** 26.2 or later
- **iOS Deployment Target:** 26.2
- **Device:** iPhone (iOS 26.2+) or iOS Simulator
- **Meta Ray-Ban Glasses:** For full functionality (app works in demo mode without glasses)

---

## Installation

### Prerequisites

1. **Clone the repository:**
   ```bash
   git clone <repository-url>
   cd nw2025
   ```

2. **Open in Xcode:**
   ```bash
   open frontend/nw2025.xcodeproj
   ```

3. **Configure Signing:**
   - Select the project in Xcode
   - Go to **Signing & Capabilities**
   - Select your development team (free Apple ID works for personal development)

### Build for Simulator

```bash
cd frontend && \
xcodebuild -project nw2025.xcodeproj -scheme nw2025 \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug build
```

### Build for iPhone

```bash
cd frontend && \
xcodebuild -project nw2025.xcodeproj -scheme nw2025 \
  -destination 'id=YOUR_DEVICE_ID' \
  -configuration Debug -allowProvisioningUpdates build install
```

Then install to device:
```bash
xcrun devicectl device install app --device YOUR_DEVICE_ID \
  ~/Library/Developer/Xcode/DerivedData/nw2025-*/Build/Intermediates.noindex/ArchiveIntermediates/nw2025/InstallationBuildProductsLocation/Applications/nw2025.app
```

**Note:** Replace `YOUR_DEVICE_ID` with your iPhone's device ID. Find it with:
```bash
xcrun xcodebuild -showdestinations -project frontend/nw2025.xcodeproj -scheme nw2025 | grep "platform:iOS.*arch:arm64"
```

---

## Project Structure

```
ClipApp/
├── App/
│   ├── ClipApp.swift              # App entry point with launch animation
│   └── GlobalViewState.swift      # Shared app state
├── Core/
│   ├── DesignSystem/
│   │   ├── Colors.swift           # Warm minimal color palette
│   │   ├── Gradients.swift        # Glass-friendly gradients
│   │   └── Typography.swift       # Font system
│   ├── Managers/
│   │   ├── WakeWordDetector.swift # "Clip that" detection
│   │   ├── PhotoManager.swift    # Photo Library integration
│   │   ├── HapticManager.swift    # Tactile feedback
│   │   └── CameraManager.swift    # Camera access
│   └── Navigation/
│       ├── RootView.swift         # Main app view
│       └── LaunchView.swift       # Opening animation
├── Features/
│   └── Feed/
│       ├── TimelineView.swift     # Core timeline visualization
│       ├── MomentCard.swift       # Individual moment cards
│       ├── ClipDetailView.swift   # Full moment details
│       └── FeedView.swift         # Feed container
├── Models/
│   ├── ClipMetadata.swift         # Clip data model
│   └── SearchResult.swift         # Search result model
└── Services/
    ├── APIService.swift           # Backend API client
    └── MockData.swift             # Sample data for development
```

---

## Key Components

### WakeWordDetector

Handles voice activation using native iOS speech recognition:

```swift
let detector = WakeWordDetector()

// Start listening with audio format from Meta SDK
detector.startListening(audioFormat: audioFormat)

// Feed audio buffers as they arrive
detector.processAudioBuffer(buffer)

// Handle "Clip that" trigger
detector.onClipTriggered = { transcript in
    // transcript contains last 30 seconds (without "clip that")
    print("Captured: \(transcript)")
}
```

**Features:**
- On-device recognition (no network required)
- Rolling 30-second transcript buffer
- Auto session restart every 50 seconds (iOS limit workaround)
- 2-second cooldown to prevent duplicate triggers

### TimelineView

The core experience - a vertical timeline of moments:

- Alternating left/right card placement for visual rhythm
- Date section headers ("Today", "Yesterday", etc.)
- Staggered entrance animations
- Glass effect cards with warm minimal styling

### Liquid Glass Usage

The app uses iOS 26's `.glassEffect()` modifier extensively:

```swift
// Basic glass
Text("Hello").glassEffect()

// Interactive button
Button("Tap") { }
    .glassEffect(.regular.interactive())

// Custom shape
RoundedRectangle(cornerRadius: 20)
    .glassEffect(in: .rect(cornerRadius: 20))

// Container for morphing
GlassEffectContainer(spacing: 20) {
    // Multiple glass views
}
```

---

## Development Workflow

### Before Starting
```bash
git pull origin main
```

### After Code Changes
Build and deploy immediately so you can test:

**Simulator:**
```bash
cd frontend && xcodebuild -project nw2025.xcodeproj -scheme nw2025 \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug build
```

**iPhone:**
```bash
cd frontend && xcodebuild -project nw2025.xcodeproj -scheme nw2025 \
  -destination 'id=YOUR_DEVICE_ID' \
  -configuration Debug -allowProvisioningUpdates build install
```

### After Feature Complete
```bash
git add -A
git commit -m "Feat: <descriptive name>"
git push origin main
```

---

## Permissions

The app requires the following permissions (configured in `Info.plist`):

- **Speech Recognition** (`NSSpeechRecognitionUsageDescription`): For wake word detection
- **Microphone** (`NSMicrophoneUsageDescription`): To capture audio from glasses
- **Photo Library** (`NSPhotoLibraryUsageDescription`): To save captured video clips

---

## Architecture

### State Management
- **GlobalViewState:** `@StateObject` in `RootView`, shared across app
- **Local State:** `@State` for view-specific UI state
- **Published Properties:** Reactive updates via `@Published`

### Data Flow
1. **Capture:** Wake word triggers → Video saved to Photo Library
2. **Process:** Audio extracted → Uploaded to backend
3. **Intelligence:** Whisper transcription → Gemini topics → MongoDB storage
4. **Search:** Semantic search returns `localIdentifier`s
5. **Display:** Frontend rehydrates from Photo Library using identifiers

### Concurrency
- Swift 6.2 default MainActor isolation
- Background work with `@concurrent` functions
- Async/await for network calls

---

## Integration Points

| Component | Status | Notes |
|-----------|--------|-------|
| Wake Word Detection | ✅ Complete | Returns 30s transcript |
| Meta SDK Audio Stream | 🔄 Pending | Need to hook up to `WakeWordDetector` |
| Backend API | 🔄 Pending | Endpoint: `/api/process` |
| Video Capture | 🔄 Pending | Handled by video team |
| Semantic Search | ✅ Mock Data | Backend integration pending |

---

## API Contract

When "Clip that" is triggered, send to backend:

```json
POST /api/process
{
  "localIdentifier": "PHAsset-XXXX",
  "transcript": "Last 30 seconds of speech before clip that",
  "timestamp": "2026-01-17T10:30:00Z"
}
```

---

## Design Tokens

### Colors
- **Background:** Warm off-white `#FAF9F7`
- **Surface:** Soft cream `#F5F3F0`
- **Accent:** Warm coral `#E85D4C`
- **Text Primary:** Warm charcoal `#2C2825`
- **Text Secondary:** Muted brown `#8A847D`

### Typography
- **Hero:** SF Pro Display 34pt Bold
- **Title:** SF Pro 17pt Semibold
- **Body:** SF Pro 15pt Regular
- **Metadata:** SF Pro 13pt Medium

### Spacing
- **Card Padding:** 16pt
- **Section Spacing:** 48pt
- **Timeline Node:** 8pt radius

---

## Future Work

- [ ] Integrate Meta Wearables SDK for audio stream
- [ ] Implement backend API client
- [ ] Add video playback with AVKit
- [ ] Implement semantic search UI
- [ ] Add export/share functionality
- [ ] Cloud sync for clips
- [ ] Advanced search filters

---

## Contributing

This is a personal project, but suggestions and feedback are welcome!

---

## License

Private project - All rights reserved

---

## Acknowledgments

- **Design Inspiration:** Flighty app's elegant timeline interface
- **Apple:** iOS 26 Liquid Glass design system
- **Meta:** Ray-Ban Meta glasses and Wearables SDK

---

**Built with ❤️ using SwiftUI and iOS 26 Liquid Glass**
