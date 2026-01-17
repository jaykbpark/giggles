import AVFoundation
import Combine
import CoreVideo

/// Main manager for Meta Glasses integration.
/// Provides a unified interface that automatically selects between mock and real SDK providers.
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
///
/// ## Configuration
/// - Set `USE_MOCK_GLASSES=1` environment variable to use mock mode
/// - In Xcode: Edit Scheme → Run → Arguments → Environment Variables
/// - Or use `MetaGlassesManager(useMock: true)` directly
@MainActor
final class MetaGlassesManager: ObservableObject {
    
    // MARK: - Singleton
    
    /// Shared instance configured based on environment
    static let shared = MetaGlassesManager()
    
    // MARK: - Provider
    
    private let provider: GlassesStreamProvider
    
    /// Whether the manager is using mock mode
    let isMockMode: Bool
    
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
    
    /// Initialize with automatic provider selection based on environment
    convenience init() {
        // Check for USE_MOCK_GLASSES environment variable
        let useMock = ProcessInfo.processInfo.environment["USE_MOCK_GLASSES"] != nil
        self.init(useMock: useMock)
    }
    
    /// Initialize with explicit provider selection
    /// - Parameter useMock: If true, uses mock provider; otherwise uses real SDK
    init(useMock: Bool) {
        self.isMockMode = useMock
        
        if useMock {
            self.provider = MockGlassesProvider()
            print("🕶️ MetaGlassesManager: Using MOCK provider")
        } else {
            self.provider = MetaSDKProvider()
            print("🕶️ MetaGlassesManager: Using REAL SDK provider")
        }
        
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
        guard connectionState.isConnected else { return }
        
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
          Mode: \(isMockMode ? "Mock" : "Real SDK")
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
}
