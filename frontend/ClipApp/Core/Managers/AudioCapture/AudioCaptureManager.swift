import AVFoundation
import Combine

/// Main manager for audio capture from glasses microphone via Bluetooth.
/// Provides a unified interface that automatically selects between mock and real providers.
///
/// ## Usage
/// ```swift
/// // Start capturing and subscribe to audio buffers
/// try await AudioCaptureManager.shared.startCapture()
///
/// AudioCaptureManager.shared.audioBufferPublisher
///     .sink { buffer in
///         wakeWordDetector.processAudioBuffer(buffer)
///     }
///     .store(in: &cancellables)
/// ```
///
/// ## Configuration
/// - Set `USE_MOCK_GLASSES=1` environment variable to use mock mode
/// - In Xcode: Edit Scheme → Run → Arguments → Environment Variables
/// - Or use `AudioCaptureManager(useMock: true)` directly
@MainActor
final class AudioCaptureManager: ObservableObject {
    
    // MARK: - Singleton
    
    /// Shared instance configured based on environment
    static let shared = AudioCaptureManager()
    
    // MARK: - Provider
    
    private let provider: AudioCaptureProvider
    
    /// Whether the manager is using mock mode
    let isMockMode: Bool
    
    // MARK: - Published State
    
    @Published private(set) var captureState: AudioCaptureState = .idle
    @Published private(set) var isCapturing: Bool = false
    @Published private(set) var lastError: AudioCaptureError?
    
    // MARK: - Publishers
    
    /// Publisher for audio buffers (for speech recognition / wake word detection)
    var audioBufferPublisher: AnyPublisher<AVAudioPCMBuffer, Never> {
        provider.audioBufferPublisher
    }
    
    /// Publisher for timestamped audio buffers (for synchronization with video)
    var timestampedAudioPublisher: AnyPublisher<TimestampedAudioBuffer, Never> {
        provider.timestampedAudioPublisher
    }
    
    /// Publisher for capture state changes
    var captureStatePublisher: AnyPublisher<AudioCaptureState, Never> {
        provider.captureStatePublisher
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
        // Check for USE_MOCK_GLASSES environment variable (same as MetaGlassesManager)
        let useMock = ProcessInfo.processInfo.environment["USE_MOCK_GLASSES"] != nil
        self.init(useMock: useMock)
    }
    
    /// Initialize with explicit provider selection
    /// - Parameter useMock: If true, uses mock provider; otherwise uses real Bluetooth provider
    init(useMock: Bool) {
        self.isMockMode = useMock
        
        if useMock {
            self.provider = MockAudioProvider()
            print("🎤 AudioCaptureManager: Using MOCK provider")
        } else {
            self.provider = BluetoothAudioProvider()
            print("🎤 AudioCaptureManager: Using BLUETOOTH provider")
        }
        
        setupBindings()
    }
    
    // MARK: - Setup
    
    private func setupBindings() {
        // Observe capture state changes
        provider.captureStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.captureState = state
                self?.isCapturing = state.isCapturing
                
                // Extract error if present
                if case .error(let error) = state {
                    self?.lastError = error
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Capture Control
    
    /// Start capturing audio from glasses microphone (via Bluetooth)
    func startCapture() async throws {
        lastError = nil
        
        do {
            try await provider.startCapture()
        } catch let error as AudioCaptureError {
            lastError = error
            throw error
        } catch {
            let captureError = AudioCaptureError.engineStartFailed(error.localizedDescription)
            lastError = captureError
            throw captureError
        }
    }
    
    /// Stop capturing audio
    func stopCapture() {
        provider.stopCapture()
    }
}

// MARK: - Debug Helpers

extension AudioCaptureManager {
    /// Debug description of current state
    var debugDescription: String {
        """
        AudioCaptureManager:
          Mode: \(isMockMode ? "Mock" : "Bluetooth")
          State: \(captureState.statusText)
          Capturing: \(isCapturing)
          Format: \(audioFormat?.description ?? "None")
        """
    }
    
    /// Print debug info to console
    func printDebugInfo() {
        print(debugDescription)
    }
}
