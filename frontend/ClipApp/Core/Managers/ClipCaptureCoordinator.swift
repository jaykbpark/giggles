import AVFoundation
import Combine
import CoreMedia
import CoreVideo
import Speech
import UIKit

/// Coordinates synchronized video and audio capture from Meta glasses.
/// Maintains rolling buffers of both streams and triggers clip export on wake word detection.
///
/// ## Architecture
/// - Video: Subscribes to `MetaGlassesManager.timestampedVideoFramePublisher`
/// - Audio: Subscribes to `AudioCaptureManager.timestampedAudioPublisher`
/// - Wake Word: Feeds audio to `WakeWordDetector` for "Clip That" detection
/// - Export: On trigger, exports last 30 seconds as synchronized video+audio file
///
/// ## SDK Requirement: Audio/HFP Setup Order
/// Per Meta Wearables DAT SDK documentation, HFP (Bluetooth audio) MUST be configured
/// BEFORE starting any stream session that requires audio functionality.
///
/// ## Usage
/// ```swift
/// let coordinator = ClipCaptureCoordinator.shared
/// try await coordinator.startCapture()
///
/// // Coordinator automatically handles wake word detection and export
/// coordinator.onClipExported = { url in
///     // Save to photo library or upload
/// }
/// ```
@MainActor
final class ClipCaptureCoordinator: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = ClipCaptureCoordinator()
    
    // MARK: - Configuration
    
    /// Duration of the rolling buffer (30 seconds)
    let bufferDuration: TimeInterval = 30.0
    
    /// Delay after HFP setup before starting video stream (per SDK docs)
    private let hfpSetupDelay: UInt64 = 2_000_000_000 // 2 seconds in nanoseconds
    
    // MARK: - Dependencies
    
    private let glassesManager: MetaGlassesManager
    private let audioManager: AudioCaptureManager
    private let wakeWordDetector: WakeWordDetector
    private let laughterDetector: LaughterDetector
    private let exporter: ClipExporter
    private let ffmpegExporter: FFmpegExporter
    private let elevenLabsSTT: ElevenLabsSTTService
    
    // MARK: - Published State
    
    @Published private(set) var isCapturing: Bool = false
    @Published private(set) var isExporting: Bool = false
    @Published private(set) var lastExportedURL: URL?
    @Published private(set) var lastExportedThumbnail: UIImage?
    @Published private(set) var lastExportedIsPortrait: Bool = false
    @Published private(set) var lastError: Error?
    
    /// Whether to export clips in portrait mode (center-cropped from landscape)
    /// Default: false - save video as-is, UI handles display orientation
    var exportAsPortrait: Bool = false
    
    /// Number of video frames in the buffer
    @Published private(set) var videoBufferCount: Int = 0
    
    /// Number of audio buffers in the buffer
    @Published private(set) var audioBufferCount: Int = 0
    
    /// Whether video stream is stale (no frames received for 2+ seconds)
    /// Used by UI to show disconnected state in connection pill
    @Published private(set) var isVideoStreamStale: Bool = false
    
    /// Current buffer duration in seconds (calculated from timestamps)
    @Published private(set) var currentBufferDuration: TimeInterval = 0.0
    
    /// Export progress: frames written so far
    @Published private(set) var exportFramesWritten: Int = 0
    
    /// Export progress: total frames to write
    @Published private(set) var exportTotalFrames: Int = 0
    
    /// Export progress as a percentage (0.0 to 1.0)
    var exportProgress: Double {
        guard exportTotalFrames > 0 else { return 0.0 }
        return Double(exportFramesWritten) / Double(exportTotalFrames)
    }
    
    /// Minimum buffer duration required to record (default: 1 second)
    let minimumBufferDuration: TimeInterval = 1.0
    
    /// Whether laughter detection auto-trigger is enabled
    var isLaughterDetectionEnabled: Bool {
        get { laughterDetector.isEnabled }
        set { 
            laughterDetector.isEnabled = newValue
            objectWillChange.send()
        }
    }
    
    /// Whether to use ElevenLabs STT for real-time transcription (better quality, requires API key)
    @Published var useElevenLabsSTT: Bool = true
    
    /// Current real-time transcript from ElevenLabs STT
    @Published private(set) var realtimeTranscript: String = ""
    
    /// Whether ElevenLabs STT is connected
    var isElevenLabsConnected: Bool {
        elevenLabsSTT.isConnected
    }
    
    /// Current laughter detection confidence (0.0 - 1.0)
    @Published private(set) var laughterConfidence: Float = 0
    
    // MARK: - Callbacks
    
    /// Called when a clip is successfully exported (URL, transcript)
    var onClipExported: ((URL, String) -> Void)?
    
    /// Called when export fails
    var onExportError: ((Error) -> Void)?
    
    /// Called when a question is asked via "Hey Clip" (Memory Assistant)
    var onQuestionAsked: ((String) -> Void)?
    
    // MARK: - Rolling Buffers
    
    private var videoBuffer: [(frame: TimestampedVideoFrame, timestamp: Date)] = []
    private var audioBuffer: [(buffer: TimestampedAudioBuffer, timestamp: Date)] = []
    
    private let bufferQueue = DispatchQueue(label: "com.clip.capturecoordinator.buffer", qos: .userInitiated)
    
    /// Tracks whether we've received at least one video frame (gates audio buffering)
    /// This prevents buffering audio before video is ready, which would result in black clips
    private var hasReceivedFirstVideoFrame: Bool = false
    
    /// Last time a video frame was received (for stale detection)
    private var lastVideoFrameTime: Date?
    
    /// Timer for checking video stream staleness
    private var staleCheckTimer: Timer?
    
    /// Threshold for considering video stream stale (2 seconds)
    private let videoStaleThreshold: TimeInterval = 2.0
    
    // MARK: - Subscriptions
    
    private var cancellables = Set<AnyCancellable>()
    
    /// Separate set for audio subscriptions so they can be cancelled independently
    /// when resuming audio capture after video playback
    private var audioSubscriptions = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    /// Initialize with default shared managers
    init() {
        self.glassesManager = MetaGlassesManager.shared
        self.audioManager = AudioCaptureManager.shared
        self.wakeWordDetector = WakeWordDetector()
        self.laughterDetector = LaughterDetector()
        self.exporter = ClipExporter()
        self.ffmpegExporter = FFmpegExporter()
        self.elevenLabsSTT = ElevenLabsSTTService.shared
        
        setupWakeWordCallback()
        setupLaughterCallback()
        setupExporterProgress()
        setupElevenLabsSTTCallback()
    }
    
    /// Initialize with custom managers (for testing)
    init(
        glassesManager: MetaGlassesManager,
        audioManager: AudioCaptureManager,
        wakeWordDetector: WakeWordDetector,
        laughterDetector: LaughterDetector,
        exporter: ClipExporter
    ) {
        self.glassesManager = glassesManager
        self.audioManager = audioManager
        self.wakeWordDetector = wakeWordDetector
        self.laughterDetector = laughterDetector
        self.exporter = exporter
        self.ffmpegExporter = FFmpegExporter()
        self.elevenLabsSTT = ElevenLabsSTTService.shared
        
        setupWakeWordCallback()
        setupLaughterCallback()
        setupExporterProgress()
        setupElevenLabsSTTCallback()
    }
    
    // MARK: - Setup
    
    private func setupWakeWordCallback() {
        wakeWordDetector.onClipTriggered = { [weak self] transcript in
            Task { @MainActor in
                await self?.handleClipTrigger(transcript: transcript, source: .wakeWord)
            }
        }
        
        wakeWordDetector.onQuestionAsked = { [weak self] question in
            Task { @MainActor in
                self?.onQuestionAsked?(question)
            }
        }
    }
    
    /// Notify that question processing is complete (call from Memory Assistant)
    func questionProcessingComplete() {
        wakeWordDetector.questionProcessingComplete()
    }
    
    private func setupLaughterCallback() {
        laughterDetector.onLaughterDetected = { [weak self] in
            Task { @MainActor in
                await self?.handleClipTrigger(transcript: "[Laughter detected]", source: .laughter)
            }
        }
        
        laughterDetector.onConfidenceUpdate = { [weak self] confidence in
            Task { @MainActor in
                self?.laughterConfidence = confidence
            }
        }
    }
    
    private func setupExporterProgress() {
        exporter.onProgress = { [weak self] framesWritten, totalFrames in
            Task { @MainActor in
                self?.exportFramesWritten = framesWritten
                self?.exportTotalFrames = totalFrames
            }
        }
    }
    
    private func setupElevenLabsSTTCallback() {
        // Real-time transcript updates
        elevenLabsSTT.onPartialTranscript = { [weak self] transcript in
            Task { @MainActor in
                self?.realtimeTranscript = transcript
            }
        }
        
        elevenLabsSTT.onCommittedTranscript = { [weak self] transcript in
            Task { @MainActor in
                // Append to transcript display
                if let self = self, !transcript.isEmpty {
                    if self.realtimeTranscript.isEmpty {
                        self.realtimeTranscript = transcript
                    } else {
                        self.realtimeTranscript += " " + transcript
                    }
                }
            }
        }
        
        // Phrase detection (clip triggers, questions)
        elevenLabsSTT.onPhraseDetected = { [weak self] phrase in
            Task { @MainActor in
                guard let self = self else { return }
                
                switch phrase {
                case .clipThat(let transcript):
                    print("🎤 [ElevenLabs] Clip triggered with transcript: \(transcript.prefix(50))...")
                    await self.handleClipTrigger(transcript: transcript, source: .wakeWord)
                    
                case .heyClip(let question):
                    print("🎤 [ElevenLabs] Question asked: \(question)")
                    self.onQuestionAsked?(question)
                }
            }
        }
    }
    
    // MARK: - Capture Control
    
    /// Start capturing video and audio from glasses
    ///
    /// **IMPORTANT**: Per Meta Wearables DAT SDK documentation, this method
    /// configures HFP (Bluetooth audio) BEFORE starting the video stream session.
    /// This order is critical for proper audio+video synchronization.
    func startCapture() async throws {
        guard !isCapturing else { return }
        
        // Clear buffers
        clearBuffers()
        
        // Set up subscriptions FIRST so we capture frames as soon as streams start
        setupVideoSubscription()
        setupConnectionSubscription()
        
        // =====================================================================
        // CRITICAL: HFP/Audio MUST be configured BEFORE starting video stream
        // Per Meta Wearables DAT SDK docs:
        // "When planning to use HFP and streaming simultaneously, it is essential
        // to ensure that HFP is fully configured before initiating any streaming
        // session that requires audio functionality."
        // =====================================================================
        
        // 1️⃣ FIRST: Set up HFP/Bluetooth audio session
        var audioAvailable = false
        do {
            try await audioManager.startCapture()
            setupAudioSubscriptions()
            audioAvailable = true
            print("🎤 [HFP] Audio/HFP configured successfully")
        } catch {
            print("⚠️ [HFP] Audio capture failed: \(error.localizedDescription)")
            print("⚠️ [HFP] Continuing with video-only recording")
            // Continue without audio - video-only recording is fine
        }
        
        // 2️⃣ Wait for HFP to be fully ready (per SDK docs)
        // The docs show a 2-second delay as fallback; ideally use state-based coordination
        if audioAvailable {
            print("🎤 [HFP] Waiting for HFP to be ready...")
            try? await Task.sleep(nanoseconds: hfpSetupDelay)
            print("🎤 [HFP] HFP setup delay complete")
        }
        
        // 3️⃣ Auto-start video stream for immediate buffer filling
        // This ensures users can clip right away without waiting
        if glassesManager.connectionState == .connected {
            do {
                if !glassesManager.isVideoStreaming {
                    print("📹 [Stream] Auto-starting video stream...")
                    try await glassesManager.startVideoStream()
                    print("📹 [Stream] Video stream started automatically!")
                } else {
                    print("📹 [Stream] Video already streaming, buffer will fill")
                }
            } catch {
                print("⚠️ [Stream] Auto-start failed (user can manually start via Preview): \(error.localizedDescription)")
                // Non-fatal - user can start manually via Preview button
            }
        } else {
            print("📹 [Stream] Glasses not connected, video will start when connected")
        }
        
        // 4️⃣ Wake word + laughter detection (only if audio is available)
        if audioAvailable {
            if wakeWordDetector.authorizationStatus == .notDetermined {
                await wakeWordDetector.requestAuthorization()
            }
            
            if let audioFormat = audioManager.audioFormat {
                wakeWordDetector.startListening(audioFormat: audioFormat)
                laughterDetector.startListening(audioFormat: audioFormat)
                print("🎤 [WakeWord] Wake word detection started")
            }
        }
        
        // 5️⃣ Start video stale detection timer
        setupStaleCheckTimer()
        
        isCapturing = true
        print("🎬 ClipCaptureCoordinator: Capture started (audio: \(audioAvailable ? "enabled" : "disabled"))")
    }
    
    /// Stop capturing
    func stopCapture() {
        cancellables.removeAll()
        audioSubscriptions.removeAll()
        
        // Stop stale check timer
        staleCheckTimer?.invalidate()
        staleCheckTimer = nil
        isVideoStreamStale = false
        lastVideoFrameTime = nil
        
        wakeWordDetector.stopListening()
        laughterDetector.stopListening()
        audioManager.stopCapture()
        glassesManager.stopVideoStream()
        
        // Disconnect ElevenLabs STT
        elevenLabsSTT.disconnect()
        realtimeTranscript = ""
        
        isCapturing = false
        print("🎬 ClipCaptureCoordinator: Capture stopped")
    }
    
    /// Set up timer to check for stale video stream (no frames for 2+ seconds)
    private func setupStaleCheckTimer() {
        staleCheckTimer?.invalidate()
        staleCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.checkVideoStreamStale()
            }
        }
    }
    
    /// Check if video stream is stale and update state
    private func checkVideoStreamStale() {
        guard isCapturing else { return }
        
        if let lastTime = lastVideoFrameTime {
            let elapsed = Date().timeIntervalSince(lastTime)
            let wasStale = isVideoStreamStale
            isVideoStreamStale = elapsed > videoStaleThreshold
            
            // Log state change
            if isVideoStreamStale && !wasStale {
                print("⚠️ [Stale] Video stream stale - no frames for \(String(format: "%.1f", elapsed))s")
            } else if !isVideoStreamStale && wasStale {
                print("✅ [Stale] Video stream recovered")
            }
        } else if hasReceivedFirstVideoFrame {
            // We've received frames before but lastVideoFrameTime is nil - shouldn't happen
            isVideoStreamStale = true
        }
    }
    
    /// Resume audio capture after it was interrupted (e.g., by video playback)
    /// Call this when returning from video detail view to restore wake word detection
    func resumeAudioCapture() async {
        guard isCapturing else {
            print("🎤 [Resume] Skipping - not capturing")
            return
        }
        
        print("🎤 [Resume] Starting audio resume after video playback...")
        
        // Cancel existing audio subscriptions FIRST to prevent duplicates
        let oldSubscriptionCount = audioSubscriptions.count
        audioSubscriptions.removeAll()
        print("🎤 [Resume] Cancelled \(oldSubscriptionCount) old audio subscriptions")
        
        // Stop existing audio to ensure clean restart
        wakeWordDetector.stopListening()
        laughterDetector.stopListening()
        audioManager.stopCapture()
        
        // Small delay to ensure audio session is fully released
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // Restart audio capture
        do {
            try await audioManager.startCapture()
            setupAudioSubscriptions()
            
            // Restart wake word and laughter detection
            if let audioFormat = audioManager.audioFormat {
                wakeWordDetector.startListening(audioFormat: audioFormat)
                laughterDetector.startListening(audioFormat: audioFormat)
                print("🎤 [Resume] Audio format: \(audioFormat.sampleRate)Hz, \(audioFormat.channelCount) channels")
            } else {
                print("⚠️ [Resume] No audio format available")
            }
            print("✅ [Resume] Audio capture resumed successfully")
        } catch {
            print("❌ [Resume] Failed to resume audio capture: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Stream Subscriptions
    
    /// Set up video frame subscription to fill the rolling buffer
    /// Called separately from audio to ensure video works even if audio fails
    private func setupVideoSubscription() {
        // Subscribe to timestamped video frames
        glassesManager.timestampedVideoFramePublisher
            .receive(on: bufferQueue)
            .sink { [weak self] frame in
                self?.appendVideoFrame(frame)
            }
            .store(in: &cancellables)
        
        print("📹 Video subscription set up")
    }
    
    /// Set up audio subscriptions for buffer and wake word detection
    /// Called only if audio capture succeeds
    private func setupAudioSubscriptions() {
        // Cancel any existing audio subscriptions before adding new ones
        // This prevents duplicate subscriptions when resuming after video playback
        audioSubscriptions.removeAll()
        
        // Subscribe to timestamped audio buffers
        audioManager.timestampedAudioPublisher
            .receive(on: bufferQueue)
            .sink { [weak self] buffer in
                self?.appendAudioBuffer(buffer)
            }
            .store(in: &audioSubscriptions)
        
        // Feed raw audio to wake word detector and/or ElevenLabs STT
        audioManager.audioBufferPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] buffer in
                guard let self = self else { return }
                
                // Always use local wake word detector as fallback
                self.wakeWordDetector.processAudioBuffer(buffer)
                self.laughterDetector.processAudioBuffer(buffer)
                
                // Also send to ElevenLabs STT if enabled and connected
                if self.useElevenLabsSTT && self.elevenLabsSTT.isConnected {
                    self.elevenLabsSTT.sendAudioBuffer(buffer)
                }
            }
            .store(in: &audioSubscriptions)
        
        print("🎤 Audio subscriptions set up (cancelled old: \(audioSubscriptions.count) active)")
        
        // Connect to ElevenLabs STT if enabled
        if useElevenLabsSTT && elevenLabsSTT.isConfigured {
            Task {
                do {
                    try await elevenLabsSTT.connect()
                    print("🎤 [ElevenLabs] Real-time STT connected")
                } catch {
                    print("⚠️ [ElevenLabs] STT connection failed: \(error.localizedDescription)")
                    print("⚠️ [ElevenLabs] Falling back to on-device transcription")
                }
            }
        }
    }

    /// Auto-start video stream when glasses finish connecting
    private func setupConnectionSubscription() {
        glassesManager.connectionStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                guard self.isCapturing else { return }

                if case .connected = state {
                    Task { @MainActor in
                        if !self.glassesManager.isVideoStreaming {
                            do {
                                print("📹 [Stream] Connection established - starting video stream...")
                                try await self.glassesManager.startVideoStream()
                                print("📹 [Stream] Video stream started after connect")
                            } catch {
                                print("⚠️ [Stream] Auto-start after connect failed: \(error.localizedDescription)")
                            }
                        }
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Buffer Management
    
    private func appendVideoFrame(_ frame: TimestampedVideoFrame) {
        // CRITICAL: Copy the pixel buffer - SDK reuses/releases the original after ~3 seconds
        guard let copiedBuffer = copyPixelBuffer(frame.pixelBuffer) else {
            print("⚠️ Failed to copy pixel buffer, skipping frame")
            return
        }
        
        let copiedFrame = TimestampedVideoFrame(
            pixelBuffer: copiedBuffer,
            hostTime: frame.hostTime,
            presentationTime: frame.presentationTime
        )
        
        // Mark that we've received a video frame (enables audio buffering)
        if !hasReceivedFirstVideoFrame {
            hasReceivedFirstVideoFrame = true
            print("📹 [Buffer] First video frame received - enabling audio buffering")
        }
        
        let now = Date()
        videoBuffer.append((frame: copiedFrame, timestamp: now))
        pruneVideoBuffer(before: now.addingTimeInterval(-bufferDuration))
        
        updateBufferDuration()
        
        Task { @MainActor in
            self.videoBufferCount = self.videoBuffer.count
            // Update last frame time for stale detection
            self.lastVideoFrameTime = Date()
            if self.isVideoStreamStale {
                self.isVideoStreamStale = false
            }
        }
    }
    
    /// Copy a CVPixelBuffer to ensure we own the data
    private func copyPixelBuffer(_ source: CVPixelBuffer) -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(source)
        let height = CVPixelBufferGetHeight(source)
        let pixelFormat = CVPixelBufferGetPixelFormatType(source)
        
        guard width > 0, height > 0 else {
            print("⚠️ Invalid pixel buffer dimensions: \(width)x\(height)")
            return nil
        }
        
        if CVPixelBufferIsPlanar(source) {
            let planeCount = CVPixelBufferGetPlaneCount(source)
            for plane in 0..<planeCount {
                let planeHeight = CVPixelBufferGetHeightOfPlane(source, plane)
                let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(source, plane)
                if planeHeight <= 0 || bytesPerRow <= 0 {
                    print("⚠️ Invalid pixel buffer plane \(plane): height=\(planeHeight), bytesPerRow=\(bytesPerRow)")
                    return nil
                }
            }
        } else {
            let bytesPerRow = CVPixelBufferGetBytesPerRow(source)
            if bytesPerRow <= 0 {
                print("⚠️ Invalid pixel buffer bytesPerRow: \(bytesPerRow)")
                return nil
            }
        }
        
        var copy: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any]
        ]
        
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            pixelFormat,
            attrs as CFDictionary,
            &copy
        )
        
        guard status == kCVReturnSuccess, let destination = copy else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(source, .readOnly)
        CVPixelBufferLockBaseAddress(destination, [])
        defer {
            CVPixelBufferUnlockBaseAddress(source, .readOnly)
            CVPixelBufferUnlockBaseAddress(destination, [])
        }
        
        // Copy each plane (YUV has 2 planes)
        let planeCount = CVPixelBufferGetPlaneCount(source)
        if planeCount > 0 {
            for plane in 0..<planeCount {
                guard let srcAddr = CVPixelBufferGetBaseAddressOfPlane(source, plane),
                      let dstAddr = CVPixelBufferGetBaseAddressOfPlane(destination, plane) else {
                    continue
                }
                let srcBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(source, plane)
                let dstBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(destination, plane)
                let height = CVPixelBufferGetHeightOfPlane(source, plane)
                
                if srcBytesPerRow == dstBytesPerRow {
                    memcpy(dstAddr, srcAddr, srcBytesPerRow * height)
                } else {
                    // Copy row by row if bytes per row differs
                    let copyBytes = min(srcBytesPerRow, dstBytesPerRow)
                    for row in 0..<height {
                        memcpy(dstAddr + row * dstBytesPerRow, srcAddr + row * srcBytesPerRow, copyBytes)
                    }
                }
            }
        } else {
            // Non-planar format (single plane)
            guard let srcAddr = CVPixelBufferGetBaseAddress(source),
                  let dstAddr = CVPixelBufferGetBaseAddress(destination) else {
                return nil
            }
            let srcBytesPerRow = CVPixelBufferGetBytesPerRow(source)
            let dataSize = srcBytesPerRow * height
            memcpy(dstAddr, srcAddr, dataSize)
        }
        
        return destination
    }
    
    private func isValidPixelBuffer(_ buffer: CVPixelBuffer) -> Bool {
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        guard width > 0, height > 0 else { return false }
        
        if CVPixelBufferIsPlanar(buffer) {
            let planeCount = CVPixelBufferGetPlaneCount(buffer)
            for plane in 0..<planeCount {
                let planeHeight = CVPixelBufferGetHeightOfPlane(buffer, plane)
                let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(buffer, plane)
                if planeHeight <= 0 || bytesPerRow <= 0 {
                    return false
                }
            }
        } else if CVPixelBufferGetBytesPerRow(buffer) <= 0 {
            return false
        }
        
        return true
    }
    
    /// Tracks whether we've logged the first audio buffer (for debugging)
    private var hasLoggedFirstAudioBuffer: Bool = false
    
    private func appendAudioBuffer(_ buffer: TimestampedAudioBuffer) {
        // Don't buffer audio until we have video frames to prevent black clips at stream startup
        guard hasReceivedFirstVideoFrame else { return }
        
        // Log first audio buffer for debugging
        if !hasLoggedFirstAudioBuffer {
            hasLoggedFirstAudioBuffer = true
            print("🎤 [Buffer] First audio buffer received - audio buffering active")
        }
        
        let now = Date()
        audioBuffer.append((buffer: buffer, timestamp: now))
        pruneAudioBuffer(before: now.addingTimeInterval(-bufferDuration))
        
        updateBufferDuration()
        
        Task { @MainActor in
            self.audioBufferCount = self.audioBuffer.count
        }
    }
    
    private func updateBufferDuration() {
        bufferQueue.async { [weak self] in
            guard let self = self else { return }
            
            let now = Date()
            var minTimestamp = now
            
            // Find the oldest timestamp in video buffer
            if let oldestVideo = self.videoBuffer.min(by: { $0.timestamp < $1.timestamp }) {
                minTimestamp = min(minTimestamp, oldestVideo.timestamp)
            }
            
            // Find the oldest timestamp in audio buffer
            if let oldestAudio = self.audioBuffer.min(by: { $0.timestamp < $1.timestamp }) {
                minTimestamp = min(minTimestamp, oldestAudio.timestamp)
            }
            
            let duration = now.timeIntervalSince(minTimestamp)
            
            Task { @MainActor in
                self.currentBufferDuration = min(duration, self.bufferDuration)
            }
        }
    }
    
    private func pruneVideoBuffer(before cutoff: Date) {
        videoBuffer.removeAll { $0.timestamp < cutoff }
    }
    
    private func pruneAudioBuffer(before cutoff: Date) {
        audioBuffer.removeAll { $0.timestamp < cutoff }
    }
    
    private func clearBuffers() {
        bufferQueue.sync {
            videoBuffer.removeAll()
            audioBuffer.removeAll()
            hasReceivedFirstVideoFrame = false  // Must be inside sync block to avoid race condition
            hasLoggedFirstAudioBuffer = false   // Reset debug logging flag
        }
        videoBufferCount = 0
        audioBufferCount = 0
        currentBufferDuration = 0.0
    }
    
    // MARK: - Clip Export
    
    /// Source of clip trigger
    enum ClipTriggerSource {
        case wakeWord
        case laughter
        case manual
    }
    
    private func handleClipTrigger(transcript: String, source: ClipTriggerSource = .manual) async {
        guard !isExporting else {
            print("⚠️ Already exporting, ignoring trigger")
            return
        }
        
        isExporting = true
        exportFramesWritten = 0
        exportTotalFrames = 0
        
        let sourceEmoji: String
        switch source {
        case .wakeWord: sourceEmoji = "🎤"
        case .laughter: sourceEmoji = "😂"
        case .manual: sourceEmoji = "👆"
        }
        print("\(sourceEmoji) Clip triggered! Source: \(source), Transcript: \(transcript)")
        
        do {
            let url = try await exportCurrentBuffer()
            lastExportedURL = url
            lastError = nil
            onClipExported?(url, transcript)
            print("✅ Clip exported to: \(url.lastPathComponent)")
        } catch {
            lastError = error
            onExportError?(error)
            print("❌ Clip export failed: \(error.localizedDescription)")
        }
        
        isExporting = false
    }
    
    private func exportCurrentBuffer() async throws -> URL {
        // Capture current buffer contents on the buffer queue
        let (videoFrames, audioBuffers) = bufferQueue.sync {
            (
                videoBuffer.map { ($0.frame.pixelBuffer, $0.frame.hostTime) },
                audioBuffer.map { $0.buffer }
            )
        }
        
        // Log buffer counts for debugging audio issues
        print("🎬 [Export] Video frames: \(videoFrames.count), Audio buffers: \(audioBuffers.count)")
        if audioBuffers.isEmpty {
            print("⚠️ [Export] WARNING: No audio buffers to export! Recording will have no audio.")
        }
        
        guard !videoFrames.isEmpty else {
            throw ClipExportError.noVideoFrames
        }
        
        let validVideoFrames = videoFrames.filter { isValidPixelBuffer($0.0) }
        if validVideoFrames.count != videoFrames.count {
            print("⚠️ Dropped \(videoFrames.count - validVideoFrames.count) invalid video frames before export")
        }
        
        guard !validVideoFrames.isEmpty else {
            throw ClipExportError.noVideoFrames
        }
        
        print("🎬 Exporting \(validVideoFrames.count) video frames with \(audioBuffers.count) audio buffers...")
        let exportFrameRate = 15
        // Use video's first frame as base time so video always starts at 0 (no black frames)
        // Audio is synced relative to video's start; any audio before video gets clipped
        let baseHostTime = validVideoFrames.first?.1 ?? 0
        
        // Try ProRes first (more lenient about formats)
        do {
            print("🎬 Trying ProRes export...")
            let videoURL = try await ffmpegExporter.exportWithProRes(
                frames: validVideoFrames,
                frameRate: exportFrameRate,
                baseHostTime: baseHostTime  // Pass consistent base time for A/V sync
            )
            do {
                // Save a master .mov with passthrough (minimal compression)
                let masterURL = try await ffmpegExporter.muxVideoWithAudio(
                    videoURL: videoURL,
                    audioBuffers: audioBuffers,
                    baseHostTime: baseHostTime,
                    outputFileType: .mov,
                    preset: AVAssetExportPresetPassthrough
                )
                print("✅ ProRes master created: \(masterURL.lastPathComponent)")
                lastExportedIsPortrait = false
                return masterURL
            } catch {
                print("⚠️ ProRes passthrough mux failed: \(error.localizedDescription)")
                print("🎬 Falling back to MP4 highest quality...")
                let muxedURL = try await ffmpegExporter.muxVideoWithAudio(
                    videoURL: videoURL,
                    audioBuffers: audioBuffers,
                    baseHostTime: baseHostTime,
                    outputFileType: .mp4,
                    preset: AVAssetExportPresetHighestQuality
                )
                lastExportedIsPortrait = false
                return muxedURL
            }
        } catch {
            print("⚠️ ProRes failed: \(error.localizedDescription)")
            print("🎬 Falling back to JPEG sequence...")
        }
        
        // Fallback to JPEG sequence (with audio mux)
        let videoURL = try await ffmpegExporter.exportAsImageSequence(
            frames: validVideoFrames,
            audioBuffers: audioBuffers,
            frameRate: exportFrameRate
        )
        
        lastExportedIsPortrait = false
        return videoURL
    }
    
    /// Manually trigger a clip export (for testing or manual capture)
    func triggerClipExport() async throws -> URL {
        guard !isExporting else {
            throw ClipExportError.alreadyExporting
        }
        
        // Check if buffer has enough content
        guard currentBufferDuration >= minimumBufferDuration else {
            throw ClipExportError.bufferTooShort(currentBufferDuration, minimumBufferDuration)
        }
        
        isExporting = true
        exportFramesWritten = 0
        exportTotalFrames = 0
        defer { isExporting = false }
        
        let url = try await exportCurrentBuffer()
        lastExportedURL = url
        return url
    }
    
    /// Get the recent transcript from the wake word detector or ElevenLabs STT (for manual clip triggers)
    func getRecentTranscript() -> String {
        // Prefer ElevenLabs STT transcript if available and connected
        if useElevenLabsSTT && elevenLabsSTT.isConnected {
            let elevenLabsTranscript = elevenLabsSTT.getRecentTranscript()
            if !elevenLabsTranscript.isEmpty {
                return elevenLabsTranscript
            }
        }
        // Fall back to on-device wake word detector
        return wakeWordDetector.getRecentTranscript()
    }
}

// MARK: - Errors

enum ClipExportError: Error, LocalizedError {
    case noVideoFrames
    case alreadyExporting
    case bufferTooShort(TimeInterval, TimeInterval)
    case exportFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .noVideoFrames:
            return "No video frames in buffer"
        case .alreadyExporting:
            return "Export already in progress"
        case .bufferTooShort(let current, let minimum):
            let remaining = max(0, minimum - current)
            return String(format: "Buffer too short. Need %.1f more seconds.", remaining)
        case .exportFailed(let reason):
            return "Export failed: \(reason)"
        }
    }
}

// MARK: - Debug Helpers

extension ClipCaptureCoordinator {
    var debugDescription: String {
        """
        ClipCaptureCoordinator:
          Capturing: \(isCapturing)
          Exporting: \(isExporting)
          Video buffer: \(videoBufferCount) frames
          Audio buffer: \(audioBufferCount) buffers
          Wake word listening: \(wakeWordDetector.isListening)
          Laughter detection: \(laughterDetector.isEnabled ? "enabled" : "disabled")
          Laughter confidence: \(String(format: "%.2f", laughterConfidence))
        """
    }
    
    func printDebugInfo() {
        print(debugDescription)
    }
}
