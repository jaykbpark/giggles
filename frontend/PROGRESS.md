# Clip iOS App - Development Progress

> **Last Updated:** January 17, 2026  
> **Platform:** iOS 26+ (SwiftUI with Liquid Glass)

---

## Current Sprint

- [x] Integrate WakeWordDetector with Meta SDK audio stream
- [ ] Implement backend API call in `sendClipToBackend(transcript:)`
- [ ] Test wake word detection end-to-end with real glasses
- [ ] Add video preview from glasses camera feed

---

## In Progress

### Backend Integration
**Owner:** TBD  
**Status:** Waiting on API endpoint implementation

Next steps:
1. Implement `sendClipToBackend()` in RootView.swift
2. Connect to `/api/process` endpoint
3. Handle response and error states

---

## Completed

### Meta Glasses SDK Integration (Jan 17, 2026)
- [x] `GlassesStreamProvider` protocol for mock/real SDK abstraction
- [x] `MockGlassesProvider` - generates synthetic video frames and audio
- [x] `MetaSDKProvider` - wrapper for real Meta Wearables DAT SDK
- [x] `MetaGlassesManager` - main entry point with provider selection
- [x] Audio stream wired to WakeWordDetector
- [x] GlassesStatusCard shows real connection state and battery
- [x] Mock mode indicator in status card
- [x] Environment variable configuration (`USE_MOCK_GLASSES=1`)

### Wake Word Detection (Jan 17, 2026)
- [x] `WakeWordDetector` class using native iOS `SFSpeechRecognizer`
- [x] On-device recognition (no network required)
- [x] Rolling 30-second transcript buffer
- [x] Auto session restart every 50 seconds (iOS limit workaround)
- [x] 2-second cooldown to prevent duplicate triggers
- [x] "Clip that" phrase stripped from returned transcript
- [x] `currentTranscript` published property for live UI

### UI Components (Jan 17, 2026)
- [x] `ListeningIndicator` - Pulsing mic animation
- [x] `GlassesStatusCard` - Shows connection state, listening, battery, mock mode
- [x] `SpectacularConfirmation` - Clip saved overlay

### Permissions (Jan 17, 2026)
- [x] `NSSpeechRecognitionUsageDescription` in Info.plist
- [x] `NSMicrophoneUsageDescription` in Info.plist
- [x] Authorization flow in `WakeWordDetector.requestAuthorization()`

### Base App Structure (Prior)
- [x] Liquid Glass design system
- [x] `ClipsGridView` / `ClipsListView` with thumbnails
- [x] `ClipDetailView` player overlay
- [x] `BottomSearchBar` with semantic search
- [x] `PhotoManager` for Photo Library integration
- [x] `HapticManager` for feedback

---

## Architecture Decisions

| Decision | Rationale |
|----------|-----------|
| Native `SFSpeechRecognizer` over ElevenLabs | On-device, zero latency, no API cost, works offline |
| 50-second session restart | iOS limits recognition to ~1 minute; restart preserves transcript |
| Transcript buffer (not audio buffer) | Lighter memory footprint; video team handles actual clip |
| Foreground-only listening | Simpler implementation, less battery drain |
| Protocol-based SDK abstraction | Allows mock mode for development, easy swap to real SDK |
| Environment variable for mock mode | Clean separation, no code changes needed to switch |

---

## Integration Points

| Feature | Owner | Status | Notes |
|---------|-------|--------|-------|
| Video capture/clipping | Video Team | In Progress | Handles 30s video buffer |
| Wake word detection | Jay | ✅ Done | Returns 30s transcript |
| Meta SDK audio stream | - | ✅ Done | Wired to WakeWordDetector via MetaGlassesManager |
| Meta SDK video stream | - | ✅ Done | Available via `videoFramePublisher` |
| Backend transcript API | TBD | Not Started | Endpoint: `/api/process` |
| Semantic search | Backend | ✅ Done | Mock data in place |

---

## API Contract (Proposed)

When "Clip That" is triggered, send to backend:

```json
POST /api/process
{
  "localIdentifier": "PHAsset-XXXX",
  "transcript": "Last 30 seconds of speech before clip that",
  "timestamp": "2026-01-17T10:30:00Z"
}
```

---

## Known Issues

| Issue | Severity | Notes |
|-------|----------|-------|
| None currently | - | - |

---

## File Reference

```
ClipApp/
├── Core/Managers/
│   ├── MetaGlasses/
│   │   ├── GlassesStreamProvider.swift  ← Protocol + shared types
│   │   ├── MetaGlassesManager.swift     ← Main entry point
│   │   ├── MockGlassesProvider.swift    ← Mock implementation
│   │   └── MetaSDKProvider.swift        ← Real SDK wrapper
│   ├── WakeWordDetector.swift           ← Wake word + transcript buffer
│   ├── HapticManager.swift
│   ├── PhotoManager.swift
│   └── CameraManager.swift
├── Core/Navigation/
│   └── RootView.swift                   ← Main view with integration
└── Info.plist                           ← Permissions
```

---

## Quick Start (For New Devs)

1. Open `nw2025.xcodeproj` in Xcode
2. Build target: iOS 26+ device or simulator
3. The app requests speech recognition permission on launch
4. **Mock mode is active by default** - set `USE_MOCK_GLASSES=1` environment variable

### Using Mock Mode (Development)

Mock mode is ideal for development without physical glasses:

```
Edit Scheme → Run → Arguments → Environment Variables
Add: USE_MOCK_GLASSES = 1
```

The mock provider generates:
- **Video:** 720p frames at 30fps with gradient background, timestamp, and "MOCK GLASSES FEED" watermark
- **Audio:** Silent buffers at 16kHz (keeps speech recognition active)
- **Connection:** Simulates 1-2 second connection delay
- **Battery:** Returns mock 82% level

### Using Real Glasses

1. Remove or unset `USE_MOCK_GLASSES` environment variable
2. Add Meta Wearables SDK via SPM: `https://github.com/facebook/meta-wearables-dat-ios`
3. Pair glasses via Meta View app
4. Uncomment SDK imports in `MetaSDKProvider.swift`

### Testing Wake Word

Say "Clip that" while the app is running to trigger a clip capture. The last 30 seconds of transcript will be captured.

### MetaGlassesManager Usage

```swift
// Connect and start streams
try await MetaGlassesManager.shared.connect()
try await MetaGlassesManager.shared.startAudioStream()

// Subscribe to video frames (for preview)
MetaGlassesManager.shared.videoFramePublisher
    .sink { pixelBuffer in
        // Display frame in preview view
    }
    .store(in: &cancellables)

// Subscribe to audio (already wired in RootView)
MetaGlassesManager.shared.audioBufferPublisher
    .sink { buffer in
        wakeWordDetector.processAudioBuffer(buffer)
    }
    .store(in: &cancellables)
```
