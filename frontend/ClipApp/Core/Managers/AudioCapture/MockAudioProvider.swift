import AVFoundation
import Combine

/// Mock implementation of AudioCaptureProvider for testing.
/// Generates synthetic audio buffers on a timer without requiring real hardware.
///
/// ## Features
/// - Generates silent or low-amplitude noise buffers
/// - Matches timing of real audio capture (~60 buffers/second at 16kHz)
/// - No microphone permission needed
/// - Works in simulator and on device without glasses
///
/// ## Usage
/// Automatically selected when `USE_MOCK_GLASSES=1` environment variable is set.
final class MockAudioProvider: AudioCaptureProvider {
    
    // MARK: - Publishers
    
    private let captureStateSubject = CurrentValueSubject<AudioCaptureState, Never>(.idle)
    private let audioBufferSubject = PassthroughSubject<AVAudioPCMBuffer, Never>()
    private let timestampedAudioSubject = PassthroughSubject<TimestampedAudioBuffer, Never>()
    
    // MARK: - State
    
    var captureState: AudioCaptureState {
        captureStateSubject.value
    }
    
    var captureStatePublisher: AnyPublisher<AudioCaptureState, Never> {
        captureStateSubject.eraseToAnyPublisher()
    }
    
    var isCapturing: Bool {
        captureState.isCapturing
    }
    
    // MARK: - Audio Format
    
    private(set) var audioFormat: AVAudioFormat?
    
    // MARK: - Audio Stream
    
    var audioBufferPublisher: AnyPublisher<AVAudioPCMBuffer, Never> {
        audioBufferSubject.eraseToAnyPublisher()
    }
    
    var timestampedAudioPublisher: AnyPublisher<TimestampedAudioBuffer, Never> {
        timestampedAudioSubject.eraseToAnyPublisher()
    }
    
    // MARK: - Configuration
    
    private let sampleRate: Double = 16000 // 16kHz for speech recognition
    private let bufferSize: AVAudioFrameCount = 1024
    private let channels: AVAudioChannelCount = 1
    
    /// Interval between buffer emissions (~64ms for 1024 samples at 16kHz)
    private var bufferInterval: TimeInterval {
        Double(bufferSize) / sampleRate
    }
    
    // MARK: - Timer
    
    private var timer: Timer?
    private var sampleTime: AVAudioFramePosition = 0
    private var startHostTime: UInt64 = 0
    
    // MARK: - Cancellables
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init() {
        // Create audio format for 16kHz mono float32
        audioFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: false
        )
        
        print("🎤 MockAudioProvider initialized (16kHz mono)")
    }
    
    deinit {
        stopCapture()
    }
    
    // MARK: - Capture Control
    
    func startCapture() async throws {
        guard !isCapturing else { return }
        
        captureStateSubject.send(.starting)
        
        // Reset timing
        sampleTime = 0
        startHostTime = mach_absolute_time()
        
        // Start timer on main thread
        await MainActor.run {
            startTimer()
        }
        
        captureStateSubject.send(.capturing)
        print("🎤 Mock audio capture started")
    }
    
    func stopCapture() {
        timer?.invalidate()
        timer = nil
        captureStateSubject.send(.idle)
        print("🎤 Mock audio capture stopped")
    }
    
    // MARK: - Private Methods
    
    @MainActor
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: bufferInterval, repeats: true) { [weak self] _ in
            self?.emitSyntheticBuffer()
        }
    }
    
    private func emitSyntheticBuffer() {
        guard let format = audioFormat,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: bufferSize) else {
            return
        }
        
        buffer.frameLength = bufferSize
        
        // Fill with silence (or very low amplitude noise for testing)
        if let channelData = buffer.floatChannelData {
            for frame in 0..<Int(bufferSize) {
                // Generate very quiet noise (helps verify audio is flowing)
                let noise = Float.random(in: -0.001...0.001)
                channelData[0][frame] = noise
            }
        }
        
        // Calculate host time for this buffer
        let currentHostTime = mach_absolute_time()
        
        // Publish raw buffer
        audioBufferSubject.send(buffer)
        
        // Publish timestamped buffer
        let timestamped = TimestampedAudioBuffer(
            buffer: buffer,
            hostTime: currentHostTime,
            sampleTime: sampleTime
        )
        timestampedAudioSubject.send(timestamped)
        
        // Advance sample time
        sampleTime += AVAudioFramePosition(bufferSize)
    }
}
