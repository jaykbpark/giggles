import AVFoundation
import Combine

/// Real implementation of AudioCaptureProvider using AVAudioEngine with Bluetooth routing.
/// Captures audio from the glasses microphone when connected as a Bluetooth audio device.
///
/// ## How it works
/// The Meta glasses connect to iPhone as a Bluetooth audio device. By configuring
/// AVAudioSession with `.allowBluetooth`, iOS routes microphone input through the
/// glasses instead of the iPhone's built-in mic.
///
/// ## Requirements
/// - Glasses must be paired and connected via Bluetooth
/// - Microphone permission must be granted
/// - Audio session must be configured before starting capture
final class BluetoothAudioProvider: AudioCaptureProvider {
    
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
    
    // MARK: - Audio Engine
    
    private var audioEngine: AVAudioEngine?
    private let desiredSampleRate: Double = 16000 // 16kHz for speech recognition
    private let bufferSize: AVAudioFrameCount = 1024
    
    // MARK: - Initialization
    
    init() {
        // Create initial format (will be updated when capture starts)
        audioFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: desiredSampleRate,
            channels: 1,
            interleaved: false
        )
    }
    
    deinit {
        stopCapture()
    }
    
    // MARK: - Capture Control
    
    func startCapture() async throws {
        guard !isCapturing else { return }
        
        captureStateSubject.send(.starting)
        
        // Request microphone permission
        let permissionGranted = await requestMicrophonePermission()
        guard permissionGranted else {
            captureStateSubject.send(.error(.permissionDenied))
            throw AudioCaptureError.permissionDenied
        }
        
        // Configure audio session for Bluetooth
        do {
            try configureAudioSession()
        } catch {
            captureStateSubject.send(.error(.audioSessionFailed(error.localizedDescription)))
            throw AudioCaptureError.audioSessionFailed(error.localizedDescription)
        }
        
        // Start audio engine
        do {
            try startAudioEngine()
            captureStateSubject.send(.capturing)
        } catch {
            captureStateSubject.send(.error(.engineStartFailed(error.localizedDescription)))
            throw AudioCaptureError.engineStartFailed(error.localizedDescription)
        }
    }
    
    func stopCapture() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        
        captureStateSubject.send(.idle)
    }
    
    // MARK: - Private Methods
    
    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
    
    private func configureAudioSession() throws {
        let audioSession = AVAudioSession.sharedInstance()

        do {
            // Configure for play and record with Bluetooth support
            // .allowBluetooth routes input through connected Bluetooth device (glasses mic)
            try audioSession.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [.allowBluetooth, .defaultToSpeaker]
            )

            // Set preferred sample rate
            try audioSession.setPreferredSampleRate(desiredSampleRate)

            // Set preferred buffer duration for low latency
            try audioSession.setPreferredIOBufferDuration(Double(bufferSize) / desiredSampleRate)

            // Activate the session
            try audioSession.setActive(true)
        } catch {
            // Fallback to built-in mic if Bluetooth session activation fails
            print("⚠️ Audio session Bluetooth config failed, falling back to device mic: \(error.localizedDescription)")
            try audioSession.setCategory(.record, mode: .measurement, options: [])
            try audioSession.setPreferredSampleRate(desiredSampleRate)
            try audioSession.setPreferredIOBufferDuration(Double(bufferSize) / desiredSampleRate)
            try audioSession.setActive(true)
        }
        
        // Log the current input route
        if let input = audioSession.currentRoute.inputs.first {
            print("🎤 Audio input: \(input.portName) (\(input.portType.rawValue))")
        }
    }
    
    private func startAudioEngine() throws {
        let engine = AVAudioEngine()
        self.audioEngine = engine
        
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        // Update our audio format to match the actual input
        self.audioFormat = inputFormat
        
        print("🎤 Input format: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount) channels")
        
        // Install tap on input node to receive audio buffers
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, time in
            self?.handleAudioBuffer(buffer, time: time)
        }
        
        // Prepare and start the engine
        engine.prepare()
        try engine.start()
        
        print("🎤 Audio engine started")
    }
    
    private func handleAudioBuffer(_ buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        // Publish raw buffer for speech recognition
        audioBufferSubject.send(buffer)
        
        // Publish timestamped buffer for synchronization
        let timestamped = TimestampedAudioBuffer(
            buffer: buffer,
            hostTime: time.hostTime,
            sampleTime: time.sampleTime
        )
        timestampedAudioSubject.send(timestamped)
    }
}
