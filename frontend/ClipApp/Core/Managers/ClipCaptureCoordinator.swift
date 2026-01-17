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
    
    // MARK: - Dependencies
    
    private let glassesManager: MetaGlassesManager
    private let audioManager: AudioCaptureManager
    private let wakeWordDetector: WakeWordDetector
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
    
    // MARK: - Callbacks
    
    /// Called when a clip is successfully exported
    var onClipExported: ((URL) -> Void)?
    
    /// Called when export fails
    var onExportError: ((Error) -> Void)?
    
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
        self.exporter = ClipExporter()
        
        setupWakeWordCallback()
    }
    
    /// Initialize with custom managers (for testing)
    init(
        glassesManager: MetaGlassesManager,
        audioManager: AudioCaptureManager,
        wakeWordDetector: WakeWordDetector,
        exporter: ClipExporter
    ) {
        self.glassesManager = glassesManager
        self.audioManager = audioManager
        self.wakeWordDetector = wakeWordDetector
        self.exporter = exporter
        
        setupWakeWordCallback()
    }
    
    // MARK: - Setup
    
    private func setupWakeWordCallback() {
        wakeWordDetector.onClipTriggered = { [weak self] transcript in
            Task { @MainActor in
                await self?.handleClipTrigger(transcript: transcript)
            }
        }
    }
    
    // MARK: - Capture Control
    
    /// Start capturing video and audio from glasses
    func startCapture() async throws {
        guard !isCapturing else { return }
        
        // Clear buffers
        clearBuffers()
        
        // Start glasses video stream
        if !glassesManager.isVideoStreaming {
            try await glassesManager.startVideoStream()
        }
        
        // Start audio capture (Bluetooth or mock)
        try await audioManager.startCapture()
        
        // Request speech recognition authorization if needed
        if wakeWordDetector.authorizationStatus == .notDetermined {
            await wakeWordDetector.requestAuthorization()
        }
        
        // Start wake word detection
        if let audioFormat = audioManager.audioFormat {
            wakeWordDetector.startListening(audioFormat: audioFormat)
        }
        
        // Subscribe to streams
        setupStreamSubscriptions()
        
        isCapturing = true
        print("🎬 ClipCaptureCoordinator: Capture started")
    }
    
    /// Stop capturing
    func stopCapture() {
        cancellables.removeAll()
        
        wakeWordDetector.stopListening()
        audioManager.stopCapture()
        glassesManager.stopVideoStream()
        
        isCapturing = false
        print("🎬 ClipCaptureCoordinator: Capture stopped")
    }
    
    // MARK: - Stream Subscriptions
    
    private func setupStreamSubscriptions() {
        // Subscribe to timestamped video frames
        glassesManager.timestampedVideoFramePublisher
            .receive(on: bufferQueue)
            .sink { [weak self] frame in
                self?.appendVideoFrame(frame)
            }
            .store(in: &cancellables)
        
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
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Buffer Management
    
    private func appendVideoFrame(_ frame: TimestampedVideoFrame) {
        let now = Date()
        videoBuffer.append((frame: frame, timestamp: now))
        pruneVideoBuffer(before: now.addingTimeInterval(-bufferDuration))
        
        Task { @MainActor in
            self.videoBufferCount = self.videoBuffer.count
        }
    }
    
    private func appendAudioBuffer(_ buffer: TimestampedAudioBuffer) {
        let now = Date()
        audioBuffer.append((buffer: buffer, timestamp: now))
        pruneAudioBuffer(before: now.addingTimeInterval(-bufferDuration))
        
        Task { @MainActor in
            self.audioBufferCount = self.audioBuffer.count
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
    }
    
    // MARK: - Clip Export
    
    private func handleClipTrigger(transcript: String) async {
        guard !isExporting else {
            print("⚠️ Already exporting, ignoring trigger")
            return
        }
        
        isExporting = true
        print("🎬 Clip triggered! Transcript: \(transcript)")
        
        do {
            let url = try await exportCurrentBuffer()
            lastExportedURL = url
            lastError = nil
            onClipExported?(url)
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
        
        isExporting = true
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
    case exportFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .noVideoFrames:
            return "No video frames in buffer"
        case .alreadyExporting:
            return "Export already in progress"
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
        """
    }
    
    func printDebugInfo() {
        print(debugDescription)
    }
}
