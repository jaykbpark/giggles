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

2. **Build + run after every code change**

   > **⚠️ IMPORTANT: Before building, ASK the user if they want Mock Mode ON or OFF.**
   > - **Mock Mode ON:** Use when no physical Meta glasses are connected
   > - **Mock Mode OFF:** Use when physical Meta Ray-Ban glasses are paired
   > - If user hasn't specified, **ask before proceeding with the build**

   **Simulator with Mock Mode (recommended for simulator):**
   ```bash
   cd /Users/jaypark/Documents/GitHub/nw2025/frontend && \
   xcodebuild -project nw2025.xcodeproj -scheme nw2025 \
     -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
     -configuration Debug build && \
   xcrun simctl boot "iPhone 17 Pro" || true && \
   xcrun simctl install "iPhone 17 Pro" ~/Library/Developer/Xcode/DerivedData/nw2025-*/Build/Products/Debug-iphonesimulator/nw2025.app && \
   xcrun simctl launch --env USE_MOCK_GLASSES=1 "iPhone 17 Pro" me.park.jay.nw2025
   ```

   **Simulator without Mock Mode (real SDK):**
   ```bash
   cd /Users/jaypark/Documents/GitHub/nw2025/frontend && \
   xcodebuild -project nw2025.xcodeproj -scheme nw2025 \
     -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
     -configuration Debug build && \
   xcrun simctl boot "iPhone 17 Pro" || true && \
   xcrun simctl install "iPhone 17 Pro" ~/Library/Developer/Xcode/DerivedData/nw2025-*/Build/Products/Debug-iphonesimulator/nw2025.app && \
   xcrun simctl launch "iPhone 17 Pro" me.park.jay.nw2025
   ```

   **Device with Mock Mode:**
   ```bash
   cd /Users/jaypark/Documents/GitHub/nw2025/frontend && \
   xcodebuild -project nw2025.xcodeproj -scheme nw2025 \
     -destination 'id=00008140-001534E83647001C' \
     -configuration Debug -allowProvisioningUpdates build && \
   xcrun devicectl device install app --device 00008140-001534E83647001C \
     ~/Library/Developer/Xcode/DerivedData/nw2025-*/Build/Products/Debug-iphoneos/nw2025.app && \
   xcrun devicectl device process launch --device 00008140-001534E83647001C \
     --environment USE_MOCK_GLASSES=1 me.park.jay.nw2025
   ```

   **Device without Mock Mode (real glasses connected):**
   ```bash
   cd /Users/jaypark/Documents/GitHub/nw2025/frontend && \
   xcodebuild -project nw2025.xcodeproj -scheme nw2025 \
     -destination 'id=00008140-001534E83647001C' \
     -configuration Debug -allowProvisioningUpdates build && \
   xcrun devicectl device install app --device 00008140-001534E83647001C \
     ~/Library/Developer/Xcode/DerivedData/nw2025-*/Build/Products/Debug-iphoneos/nw2025.app && \
   xcrun devicectl device process launch --device 00008140-001534E83647001C me.park.jay.nw2025
   ```

   If build/run fails, **stop and report the error**.

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

### Mock Mode for Glasses

The app supports a mock glasses provider for development without physical hardware.

- **Environment Variable:** `USE_MOCK_GLASSES=1` (passed at launch time)
- **When to use Mock Mode:**
  - Running on simulator (no glasses support)
  - Device testing without paired glasses
  - UI/UX development and iteration
- **When to use Real SDK:**
  - Testing actual glasses integration
  - Device with paired Meta Ray-Ban glasses

**Key Files:**
- `Core/Managers/MetaGlasses/MetaGlassesManager.swift` - Unified interface
- `Core/Managers/MetaGlasses/MockGlassesProvider.swift` - Synthetic video/audio
- `Core/Managers/MetaGlasses/MetaSDKProvider.swift` - Real SDK wrapper

Console output when mock mode is active: `🕶️ MetaGlassesManager: Using MOCK provider`

---

## Apple Docs (Local)

```
/Applications/Xcode.app/Contents/PlugIns/IDEIntelligenceChat.framework/Versions/A/Resources/AdditionalDocumentation/
```

Key files:
- `SwiftUI-Implementing-Liquid-Glass-Design.md`
- `Swift-Concurrency-Updates.md`

