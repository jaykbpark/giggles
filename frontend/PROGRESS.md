# Clip iOS App - Development Progress

> **Last Updated:** January 17, 2026  
> **Platform:** iOS 26+ (SwiftUI with Liquid Glass)

---

## Current Sprint

- [ ] Integrate WakeWordDetector with Meta SDK audio stream
- [ ] Implement backend API call in `sendClipToBackend(transcript:)`
- [ ] Test wake word detection end-to-end with real glasses

---

## In Progress

### Wake Word → Backend Integration
**Owner:** Jay  
**Status:** Waiting on Meta SDK audio stream hookup

The `WakeWordDetector` is complete and ready to receive audio. Next steps:
1. Get `AVAudioFormat` from Meta Wearables SDK
2. Call `wakeWordDetector.startListening(audioFormat:)`
3. Feed buffers via `wakeWordDetector.processAudioBuffer(buffer)`
4. Implement `sendClipToBackend()` API call

---

## Completed

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
- [x] `GlassesStatusCard(isListening:)` - Shows listening state
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

---

## Integration Points

| Feature | Owner | Status | Notes |
|---------|-------|--------|-------|
| Video capture/clipping | Video Team | In Progress | Handles 60s video buffer |
| Wake word detection | Jay | ✅ Done | Returns 30s transcript |
| Meta SDK audio stream | TBD | Not Started | Need to hook up to WakeWordDetector |
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
│   ├── WakeWordDetector.swift   ← Wake word + transcript buffer
│   ├── HapticManager.swift
│   ├── PhotoManager.swift
│   └── CameraManager.swift
├── Core/Navigation/
│   └── RootView.swift           ← Main view with integration
└── Info.plist                   ← Permissions
```

---

## Quick Start (For New Devs)

1. Open `nw2025.xcodeproj` in Xcode
2. Build target: iOS 26+ device or simulator
3. The app requests speech recognition permission on launch
4. Wake word detection is set up but waiting for Meta SDK audio stream

To test wake word manually (without glasses):
```swift
// In RootView, temporarily use device mic:
let audioEngine = AVAudioEngine()
let format = audioEngine.inputNode.outputFormat(forBus: 0)
wakeWordDetector.startListening(audioFormat: format)
audioEngine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
    wakeWordDetector.processAudioBuffer(buffer)
}
try audioEngine.start()
```
