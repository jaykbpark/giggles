import AVFoundation
import Combine
import CoreMedia
import CoreVideo
import Speech

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
    
    // MARK: - Published State
    
    @Published private(set) var isCapturing: Bool = false
    @Published private(set) var isExporting: Bool = false
    @Published private(set) var lastExportedURL: URL?
    @Published private(set) var lastError: Error?
    
    /// Number of video frames in the buffer
    @Published private(set) var videoBufferCount: Int = 0
    
    /// Number of audio buffers in the buffer
    @Published private(set) var audioBufferCount: Int = 0
    
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
    
    // MARK: - Subscriptions
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    /// Initialize with default shared managers
    init() {
        self.glassesManager = MetaGlassesManager.shared
        self.audioManager = AudioCaptureManager.shared
        self.wakeWordDetector = WakeWordDetector()
        self.laughterDetector = LaughterDetector()
        self.exporter = ClipExporter()
        
        setupWakeWordCallback()
        setupLaughterCallback()
        setupExporterProgress()
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
        
        setupWakeWordCallback()
        setupLaughterCallback()
        setupExporterProgress()
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
        
        // 3️⃣ Video stream is NOT auto-started here
        // The video stream will be started when:
        // - User taps the preview button (via ensureVideoStreamReady)
        // - User manually triggers recording
        // This avoids race conditions between coordinator and UI trying to start the stream simultaneously
        print("📹 [Stream] Video stream NOT auto-started (will start on user action)")
        
        // Note: If glasses are already streaming, we'll pick up the frames via our subscription
        
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
        
        isCapturing = true
        print("🎬 ClipCaptureCoordinator: Capture started (audio: \(audioAvailable ? "enabled" : "disabled"))")
    }
    
    /// Stop capturing
    func stopCapture() {
        cancellables.removeAll()
        
        wakeWordDetector.stopListening()
        laughterDetector.stopListening()
        audioManager.stopCapture()
        glassesManager.stopVideoStream()
        
        isCapturing = false
        print("🎬 ClipCaptureCoordinator: Capture stopped")
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
        // Subscribe to timestamped audio buffers
        audioManager.timestampedAudioPublisher
            .receive(on: bufferQueue)
            .sink { [weak self] buffer in
                self?.appendAudioBuffer(buffer)
            }
            .store(in: &cancellables)
        
        // Feed raw audio to wake word detector
        audioManager.audioBufferPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] buffer in
                self?.wakeWordDetector.processAudioBuffer(buffer)
                self?.laughterDetector.processAudioBuffer(buffer)
            }
            .store(in: &cancellables)
        
        print("🎤 Audio subscriptions set up")
    }
    
    // MARK: - Buffer Management
    
    private func appendVideoFrame(_ frame: TimestampedVideoFrame) {
        let now = Date()
        videoBuffer.append((frame: frame, timestamp: now))
        pruneVideoBuffer(before: now.addingTimeInterval(-bufferDuration))
        
        updateBufferDuration()
        
        Task { @MainActor in
            self.videoBufferCount = self.videoBuffer.count
        }
    }
    
    private func appendAudioBuffer(_ buffer: TimestampedAudioBuffer) {
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
        
        guard !videoFrames.isEmpty else {
            throw ClipExportError.noVideoFrames
        }
        
        // Determine video size from first frame
        let firstFrame = videoFrames[0].0
        let videoSize = CGSize(
            width: CVPixelBufferGetWidth(firstFrame),
            height: CVPixelBufferGetHeight(firstFrame)
        )
        
        let config = ClipExporter.ExportConfig(
            videoSize: videoSize,
            frameRate: 30,
            videoBitRate: 5_000_000,
            audioSampleRate: 16000,
            audioChannels: 1
        )
        
        return try await exporter.exportWithHostTimeSync(
            videoFrames: videoFrames,
            audioBuffers: audioBuffers,
            config: config
        )
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
