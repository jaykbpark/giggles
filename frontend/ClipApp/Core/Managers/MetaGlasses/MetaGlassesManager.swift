import AVFoundation
import Combine
import CoreVideo

/// Main manager for Meta Glasses integration.
/// Provides a unified interface for the Meta Wearables DAT SDK.
///
/// ## Usage
/// ```swift
/// // Connect and start streams
/// try await MetaGlassesManager.shared.connect()
/// try await MetaGlassesManager.shared.startAudioStream()
///
/// // Subscribe to audio buffers for wake word detection
/// MetaGlassesManager.shared.audioBufferPublisher
///     .sink { buffer in
///         wakeWordDetector.processAudioBuffer(buffer)
///     }
///     .store(in: &cancellables)
/// ```
@MainActor
final class MetaGlassesManager: ObservableObject {
    
    // MARK: - Singleton
    
    /// Shared instance
    static let shared = MetaGlassesManager()
    
    // MARK: - Provider
    
    private let provider: GlassesStreamProvider
    
    // MARK: - Published State
    
    @Published private(set) var connectionState: GlassesConnectionState = .disconnected
    @Published private(set) var isVideoStreaming: Bool = false
    @Published private(set) var isAudioStreaming: Bool = false
    @Published private(set) var batteryLevel: Int = 0
    @Published private(set) var deviceName: String = "Ray-Ban Meta"
    @Published private(set) var lastError: GlassesError?
    
    // MARK: - Publishers
    
    /// Publisher for video frames (CVPixelBuffer)
    var videoFramePublisher: AnyPublisher<CVPixelBuffer, Never> {
        provider.videoFramePublisher
    }
    
    /// Publisher for timestamped video frames (for synchronization with audio)
    var timestampedVideoFramePublisher: AnyPublisher<TimestampedVideoFrame, Never> {
        provider.timestampedVideoFramePublisher
    }
    
    /// Publisher for audio buffers (for speech recognition)
    var audioBufferPublisher: AnyPublisher<AVAudioPCMBuffer, Never> {
        provider.audioBufferPublisher
    }
    
    /// Publisher for connection state changes
    var connectionStatePublisher: AnyPublisher<GlassesConnectionState, Never> {
        provider.connectionStatePublisher
    }
    
    /// The audio format for speech recognition
    var audioFormat: AVAudioFormat? {
        provider.audioFormat
    }
    
    // MARK: - Private
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init() {
        self.provider = MetaSDKProvider()
        print("🕶️ MetaGlassesManager: Initialized with SDK provider")
        setupBindings()
    }
    
    // MARK: - Setup
    
    private func setupBindings() {
        // Observe connection state changes
        provider.connectionStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.connectionState = state
                
                // Extract error if present
                if case .error(let error) = state {
                    self?.lastError = error
                }
            }
            .store(in: &cancellables)
        
        // Update device info periodically when connected
        Timer.publish(every: 5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateDeviceInfo()
            }
            .store(in: &cancellables)
    }
    
    private func updateDeviceInfo() {
        // Read connection state directly from provider to avoid race condition
        // (the manager's connectionState is updated async via Combine)
        guard provider.connectionState.isConnected else { return }
        
        batteryLevel = provider.batteryLevel
        deviceName = provider.deviceName
        isVideoStreaming = provider.isVideoStreaming
        isAudioStreaming = provider.isAudioStreaming
    }
    
    // MARK: - Connection
    
    /// Connect to the Meta glasses
    func connect() async throws {
        lastError = nil
        
        do {
            try await provider.connect()
            // Sync connection state immediately from provider to avoid race condition
            // (the Combine subscription updates async, but we need state now)
            connectionState = provider.connectionState
            updateDeviceInfo()
        } catch let error as GlassesError {
            lastError = error
            throw error
        } catch {
            let glassesError = GlassesError.connectionFailed(error.localizedDescription)
            lastError = glassesError
            throw glassesError
        }
    }
    
    /// Disconnect from the Meta glasses
    func disconnect() {
        provider.disconnect()
        updateDeviceInfo()
    }
    
    // MARK: - URL Handling
    
    /// Handle URL callback from Meta AI app after registration
    func handleURL(_ url: URL) async -> Bool {
        guard let sdkProvider = provider as? MetaSDKProvider else {
            return false
        }
        return await sdkProvider.handleURL(url)
    }
    
    /// Re-request camera permission from the SDK
    /// Returns a status message for the UI
    func reauthorize() async -> String {
        guard let sdkProvider = provider as? MetaSDKProvider else {
            return "SDK not available"
        }
        return await sdkProvider.reauthorize()
    }
    
    // MARK: - Video Streaming
    
    /// Start the video stream from the glasses camera
    func startVideoStream() async throws {
        do {
            try await provider.startVideoStream()
            isVideoStreaming = true
        } catch let error as GlassesError {
            lastError = error
            throw error
        } catch {
            let glassesError = GlassesError.streamFailed(error.localizedDescription)
            lastError = glassesError
            throw glassesError
        }
    }
    
    /// Stop the video stream
    func stopVideoStream() {
        provider.stopVideoStream()
        isVideoStreaming = false
    }
    
    // MARK: - Audio Streaming
    
    /// Start the audio stream from the glasses microphone
    func startAudioStream() async throws {
        do {
            try await provider.startAudioStream()
            isAudioStreaming = true
        } catch let error as GlassesError {
            lastError = error
            throw error
        } catch {
            let glassesError = GlassesError.streamFailed(error.localizedDescription)
            lastError = glassesError
            throw glassesError
        }
    }
    
    /// Stop the audio stream
    func stopAudioStream() {
        provider.stopAudioStream()
        isAudioStreaming = false
    }
    
    // MARK: - Convenience
    
    /// Start both video and audio streams
    func startAllStreams() async throws {
        try await startVideoStream()
        try await startAudioStream()
    }
    
    /// Stop all streams and disconnect
    func stopAllAndDisconnect() {
        stopVideoStream()
        stopAudioStream()
        disconnect()
    }
}

// MARK: - Debug Helpers

extension MetaGlassesManager {
    /// Debug description of current state
    var debugDescription: String {
        """
        MetaGlassesManager:
          Connection: \(connectionState.statusText)
          Video: \(isVideoStreaming ? "Streaming" : "Stopped")
          Audio: \(isAudioStreaming ? "Streaming" : "Stopped")
          Battery: \(batteryLevel)%
          Device: \(deviceName)
        """
    }
    
    /// Print debug info to console
    func printDebugInfo() {
        print(debugDescription)
    }
    
    /// Get SDK debug status for UI display
    var sdkDebugStatus: String {
        guard let sdkProvider = provider as? MetaSDKProvider else {
            return ""
        }
        return sdkProvider.debugStatus
    }
}
