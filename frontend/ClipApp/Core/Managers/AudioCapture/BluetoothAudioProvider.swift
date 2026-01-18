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
    
    /// Whether currently using Bluetooth input (glasses mic)
    private(set) var isUsingBluetoothInput: Bool = false
    
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
    
    // MARK: - Route Change Handling
    
    private var routeChangeObserver: NSObjectProtocol?
    
    // MARK: - Initialization
    
    init() {
        // Create initial format (will be updated when capture starts)
        audioFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: desiredSampleRate,
            channels: 1,
            interleaved: false
        )
        
        // Listen for audio route changes to handle Bluetooth connect/disconnect
        setupRouteChangeObserver()
    }
    
    deinit {
        if let observer = routeChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        stopCapture()
    }
    
    // MARK: - Route Change Observer
    
    private func setupRouteChangeObserver() {
        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleRouteChange(notification)
        }
    }
    
    private func handleRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        
        let audioSession = AVAudioSession.sharedInstance()
        let currentInput = audioSession.currentRoute.inputs.first
        let isBluetooth = currentInput?.portType == .bluetoothHFP || 
                          currentInput?.portType == .bluetoothA2DP ||
                          currentInput?.portType == .bluetoothLE
        
        print("🎤 Route changed: \(reason.rawValue) -> \(currentInput?.portName ?? "none") (BT: \(isBluetooth))")
        
        switch reason {
        case .newDeviceAvailable:
            // New device (like Bluetooth) became available - restart to use it
            if isBluetooth && !isUsingBluetoothInput && isCapturing {
                print("🎤 Bluetooth device available - restarting audio to use it")
                Task { @MainActor in
                    await self.restartWithBluetooth()
                }
            }
        case .oldDeviceUnavailable:
            // Device disconnected - may need to fallback
            if isUsingBluetoothInput && !isBluetooth && isCapturing {
                print("⚠️ Bluetooth disconnected - falling back to device mic")
                isUsingBluetoothInput = false
            }
        default:
            break
        }
    }
    
    /// Restart audio capture to pick up Bluetooth
    private func restartWithBluetooth() async {
        guard isCapturing else { return }
        
        print("🎤 Restarting audio capture for Bluetooth...")
        stopCapture()
        
        // Small delay to let audio system settle
        try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s
        
        do {
            try await startCapture()
            print("🎤 Audio capture restarted with Bluetooth")
        } catch {
            print("❌ Failed to restart audio: \(error.localizedDescription)")
        }
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
        
        // Wait for Bluetooth to be available (up to 2 seconds)
        let bluetoothAvailable = await waitForBluetoothInput(timeout: 2.0)
        if bluetoothAvailable {
            print("🎤 Bluetooth input available, proceeding with glasses mic")
        } else {
            print("⚠️ Bluetooth not available yet, will use device mic (may switch later)")
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
            
            // Check if we ended up with Bluetooth
            updateBluetoothStatus()
        } catch {
            captureStateSubject.send(.error(.engineStartFailed(error.localizedDescription)))
            throw AudioCaptureError.engineStartFailed(error.localizedDescription)
        }
    }
    
    /// Wait for Bluetooth input to become available
    private func waitForBluetoothInput(timeout: TimeInterval) async -> Bool {
        let checkInterval: TimeInterval = 0.2
        let maxAttempts = Int(timeout / checkInterval)
        
        for attempt in 0..<maxAttempts {
            if isBluetoothInputAvailable() {
                return true
            }
            
            if attempt < maxAttempts - 1 {
                try? await Task.sleep(nanoseconds: UInt64(checkInterval * 1_000_000_000))
            }
        }
        
        return isBluetoothInputAvailable()
    }
    
    /// Check if a Bluetooth input is currently available
    private func isBluetoothInputAvailable() -> Bool {
        let audioSession = AVAudioSession.sharedInstance()
        let availableInputs = audioSession.availableInputs ?? []
        
        return availableInputs.contains { port in
            port.portType == .bluetoothHFP ||
            port.portType == .bluetoothA2DP ||
            port.portType == .bluetoothLE
        }
    }
    
    /// Update the Bluetooth status based on current route
    private func updateBluetoothStatus() {
        let audioSession = AVAudioSession.sharedInstance()
        if let input = audioSession.currentRoute.inputs.first {
            isUsingBluetoothInput = input.portType == .bluetoothHFP ||
                                    input.portType == .bluetoothA2DP ||
                                    input.portType == .bluetoothLE
            print("🎤 Current input: \(input.portName) (Bluetooth: \(isUsingBluetoothInput))")
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
        
        // First, try to deactivate any existing session to reset state
        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)

        do {
            // Configure for play and record with Bluetooth support
            // .allowBluetooth routes input through connected Bluetooth device (glasses mic)
            // .mixWithOthers allows this to work alongside Meta SDK's audio
            try audioSession.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [.allowBluetooth, .defaultToSpeaker, .mixWithOthers, .allowBluetoothA2DP]
            )

            // Set preferred sample rate
            try audioSession.setPreferredSampleRate(desiredSampleRate)

            // Set preferred buffer duration for low latency
            try audioSession.setPreferredIOBufferDuration(Double(bufferSize) / desiredSampleRate)
            
            // Explicitly select Bluetooth input if available
            try selectBluetoothInputIfAvailable(audioSession)

            // Activate the session (retry to avoid transient HFP failures)
            try activateSessionWithRetry(audioSession, options: .notifyOthersOnDeactivation)
            print("🎤 Audio session configured with Bluetooth support")
        } catch {
            // Fallback 1: Try without Bluetooth-specific options
            print("⚠️ Audio session Bluetooth config failed: \(error.localizedDescription)")
            print("🎤 Trying fallback with device mic...")
            
            do {
                try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.mixWithOthers, .defaultToSpeaker])
                try audioSession.setPreferredSampleRate(desiredSampleRate)
                try audioSession.setPreferredIOBufferDuration(Double(bufferSize) / desiredSampleRate)
                try activateSessionWithRetry(audioSession)
                print("🎤 Fallback 1 succeeded: Using device mic")
            } catch {
                // Fallback 2: Simplest config - just record mode
                print("⚠️ Fallback 1 failed: \(error.localizedDescription)")
                print("🎤 Trying minimal fallback...")
                
                try audioSession.setCategory(.record, mode: .default, options: [])
                try activateSessionWithRetry(audioSession)
                print("🎤 Fallback 2 succeeded: Minimal config")
            }
        }
        
        // Log the current input route
        if let input = audioSession.currentRoute.inputs.first {
            print("🎤 Audio input: \(input.portName) (\(input.portType.rawValue))")
        } else {
            print("⚠️ No audio input available")
        }
    }
    
    /// Explicitly select Bluetooth input if available
    private func selectBluetoothInputIfAvailable(_ audioSession: AVAudioSession) throws {
        guard let availableInputs = audioSession.availableInputs else { return }
        
        // Find Bluetooth input (prefer HFP for glasses)
        let bluetoothInput = availableInputs.first { port in
            port.portType == .bluetoothHFP
        } ?? availableInputs.first { port in
            port.portType == .bluetoothA2DP || port.portType == .bluetoothLE
        }
        
        if let btInput = bluetoothInput {
            try audioSession.setPreferredInput(btInput)
            print("🎤 Explicitly selected Bluetooth input: \(btInput.portName)")
        }
    }

    private func activateSessionWithRetry(
        _ audioSession: AVAudioSession,
        options: AVAudioSession.SetActiveOptions = []
    ) throws {
        let delays: [TimeInterval] = [0, 0.25, 0.5]
        var lastError: Error?

        for (index, delay) in delays.enumerated() {
            if delay > 0 {
                Thread.sleep(forTimeInterval: delay)
            }

            do {
                try audioSession.setActive(true, options: options)
                if index > 0 {
                    print("🎤 Audio session activated on retry \(index + 1)")
                }
                return
            } catch {
                lastError = error
                print("⚠️ Audio session activation failed (attempt \(index + 1)): \(error.localizedDescription)")
            }
        }

        throw lastError ?? AudioCaptureError.audioSessionFailed("Unknown activation error")
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
