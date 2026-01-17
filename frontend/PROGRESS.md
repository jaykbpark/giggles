# Clip iOS App - Development Progress

> **Last Updated:** January 17, 2026  
> **Platform:** iOS 26+ (SwiftUI with Liquid Glass)

---

## Current Sprint

- [x] Integrate WakeWordDetector with Meta SDK audio stream
- [x] Implement clip capture pipeline (ClipCaptureCoordinator + ClipExporter)
- [ ] Save exported clips to Photo Library
- [ ] Implement backend video upload (`POST /api/video`)
- [ ] Test wake word detection end-to-end with real glasses
- [ ] Add video preview from glasses camera feed

---

## Data Flow Status

| Component | Status | Notes |
|-----------|--------|-------|
| Feed data | **Mock** | `MockData.clips` hardcoded (6 sample clips) |
| Clip capture | **Real** | `ClipCaptureCoordinator` working |
| Video export | **Real** | `.mov` files created in temp directory |
| Photo Library save | Not Implemented | TODO in `handleExportedClip()` |
| Backend upload | Not Implemented | TODO in `sendClipToBackend()` |
| Search | **Mock** | Filters mock data locally |

### Clip Save Flow (Intended)

```
Wake Word Detected
       ↓
ClipCaptureCoordinator.handleClipTrigger()
       ↓
ClipExporter.exportWithHostTimeSync()
       ↓
.mov file in temp directory
       ↓
[TODO] Save to Photo Library (PHAsset)
       ↓
[TODO] Upload to Backend (POST /api/video)
       ↓
[TODO] Receive transcript + tags from backend
       ↓
[TODO] Update ClipMetadata in feed
```

---

## In Progress

### Clip Pipeline Integration
**Owner:** TBD  
**Status:** Export working, persistence not implemented

Next steps:
1. Implement Photo Library save in `handleExportedClip()`
2. Implement `sendClipToBackend()` with real API call
3. Wire up backend response to update feed with real metadata

### Backend Integration
**Owner:** TBD  
**Status:** Waiting on public server deployment

API contract defined in [`../endpoint.md`](../endpoint.md)

Next steps:
1. Deploy backend to public server (Cloudflare Tunnel or Railway)
2. Update `APIService.baseURL` with real endpoint
3. Implement video upload flow

---

## Completed

### Clip Capture Pipeline (Jan 17, 2026)
- [x] `ClipCaptureCoordinator` - orchestrates video/audio capture with rolling buffers
- [x] `ClipExporter` - exports synchronized video+audio to `.mov` file
- [x] `AudioCaptureManager` - captures audio from Bluetooth or mock source
- [x] 30-second rolling buffer for both video and audio
- [x] Wake word triggers automatic clip export
- [x] New clips added to timeline with placeholder metadata

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
| Video capture/clipping | - | ✅ Done | `ClipCaptureCoordinator` + `ClipExporter` |
| Wake word detection | Jay | ✅ Done | Returns 30s transcript |
| Meta SDK audio stream | - | ✅ Done | Wired to WakeWordDetector via MetaGlassesManager |
| Meta SDK video stream | - | ✅ Done | Available via `videoFramePublisher` |
| Photo Library save | - | Not Started | TODO in `handleExportedClip()` |
| Backend video upload | TBD | Not Started | Endpoint: `POST /api/video` |
| Backend transcript API | TBD | Not Started | Endpoint: `GET /api/videos` |
| Semantic search | Backend | Mock | Filters mock data locally |

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
│   ├── AudioCapture/
│   │   ├── AudioCaptureManager.swift    ← Audio capture orchestration
│   │   ├── AudioCaptureProvider.swift   ← Protocol for audio sources
│   │   ├── BluetoothAudioProvider.swift ← Real Bluetooth audio
│   │   └── MockAudioProvider.swift      ← Mock audio for development
│   ├── ClipCaptureCoordinator.swift     ← Orchestrates video+audio capture
│   ├── ClipExporter.swift               ← Exports .mov files
│   ├── WakeWordDetector.swift           ← Wake word + transcript buffer
│   ├── HapticManager.swift
│   ├── PhotoManager.swift
│   └── CameraManager.swift
├── Core/Navigation/
│   └── RootView.swift                   ← Main view with integration
├── Services/
│   ├── APIService.swift                 ← Backend API calls (mock URL)
│   └── MockData.swift                   ← Hardcoded sample clips
└── Info.plist                           ← Permissions
```

See also: [`../endpoint.md`](../endpoint.md) for full API contract

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
