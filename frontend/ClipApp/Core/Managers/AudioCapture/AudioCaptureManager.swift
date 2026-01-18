import AVFoundation
import Combine

/// Main manager for audio capture from glasses microphone via Bluetooth.
/// Provides a unified interface for Bluetooth audio capture.
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
@MainActor
final class AudioCaptureManager: ObservableObject {
    
    // MARK: - Singleton
    
    /// Shared instance
    static let shared = AudioCaptureManager()
    
    // MARK: - Provider
    
    private let provider: AudioCaptureProvider
    
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
    
    init() {
        self.provider = BluetoothAudioProvider()
        print("🎤 AudioCaptureManager: Initialized with Bluetooth provider")
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
