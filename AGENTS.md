# Agents Guide - Clip (nw2025)

This file is the shared playbook for AI agents and contributors working on the Clip iOS app.

---

## Project Snapshot

- **App:** Clip (Meta Ray-Ban glasses companion)
- **Platform:** iOS 26+ (SwiftUI + Liquid Glass)
- **UI Direction:** Warm minimal, timeline-first, “just works”
- **Core Flow:** Wake word → capture 30s → transcript → search + timeline

Progress and sprint notes live in `frontend/PROGRESS.md`.

---

## Development Workflow (Required)

1. **Pull first, always**
   ```bash
   cd /Users/jaypark/Documents/GitHub/nw2025 && git pull origin main
   git log --oneline -10
   ```
   After pulling, **explicitly say** you pulled and are on `main`.

2. **Build after changes**

   **Simulator:**
   ```bash
   cd /Users/jaypark/Documents/GitHub/nw2025/frontend && \
   xcodebuild -project nw2025.xcodeproj -scheme nw2025 \
     -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
     -configuration Debug build
   ```

   **Device (connected):**
   ```bash
   cd /Users/jaypark/Documents/GitHub/nw2025/frontend && \
   xcodebuild -project nw2025.xcodeproj -scheme nw2025 \
     -destination 'id=00008140-001534E83647001C' \
     -configuration Debug -allowProvisioningUpdates build

   xcrun devicectl device install app --device 00008140-001534E83647001C \
     ~/Library/Developer/Xcode/DerivedData/nw2025-*/Build/Products/Debug-iphoneos/nw2025.app

   xcrun devicectl device process launch --device 00008140-001534E83647001C me.park.jay.nw2025
   ```

3. **Commit only after user validation**
   ```bash
   git add -A
   git commit -m "<type>: <summary>"
   git push origin main
   ```

Commit types: `Feat`, `Fix`, `UI`, `Refactor`, `Chore`.

4. **Clear push messaging (always)**
   After pushing, **explicitly say** what was pushed (branch + commit hash/summary).

---

## UI & Design Principles

### Liquid Glass (iOS 26)
- Use `.glassEffect()` for chrome and controls.
- Use `.glassEffect(.regular.interactive())` for tappable elements.
- Avoid glass for primary content blocks (transcripts, cards).

### Warm Minimal Aesthetic
- Warm off-white background, soft surfaces, subtle shadows.
- Generous spacing; avoid visual noise.
- Timeline-first UI with vertical rhythm.

### Core Views
- `RootView`: header + timeline + overlays
- `TimelineView`: main timeline list
- `MomentCard`: concise card for each clip
- `ClipDetailView`: expanded detail view with transcript

---

## Architecture & Data Flow

```
WakeWordDetector → Transcript (30s buffer)
Photo Library ← 30s video capture
Backend → Whisper/Gemini → topics
Search → localIdentifiers → rehydrate in UI
```

---

## Key Files

```
frontend/ClipApp/
├── App/
│   ├── ClipApp.swift
│   └── GlobalViewState.swift
├── Core/
│   ├── Navigation/RootView.swift
│   ├── DesignSystem/Colors.swift
│   └── Managers/WakeWordDetector.swift
├── Features/Feed/
│   ├── TimelineView.swift
│   ├── MomentCard.swift
│   └── ClipDetailView.swift
└── Services/
    ├── APIService.swift
    └── MockData.swift
```

---

## Wake Word Integration

Location: `Core/Managers/WakeWordDetector.swift`

```swift
wakeWordDetector.startListening(audioFormat: format)
wakeWordDetector.processAudioBuffer(buffer)
wakeWordDetector.onClipTriggered = { transcript in ... }
```

Notes:
- On-device recognition
- 30s rolling transcript buffer
- Auto restart every 50s

---

## Meta Wearables SDK

SPM URL: `https://github.com/facebook/meta-wearables-dat-ios`  
Docs: `https://wearables.developer.meta.com/docs/develop`

---

## Apple Docs (Local)

```
/Applications/Xcode.app/Contents/PlugIns/IDEIntelligenceChat.framework/Versions/A/Resources/AdditionalDocumentation/
```

Key files:
- `SwiftUI-Implementing-Liquid-Glass-Design.md`
- `Swift-Concurrency-Updates.md`

