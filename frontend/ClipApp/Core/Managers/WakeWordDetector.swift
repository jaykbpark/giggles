import AVFoundation
import Speech
import Combine

/// Detects "Clip That" wake word from an audio stream using iOS Speech Recognition
@MainActor
final class WakeWordDetector: ObservableObject {
    // MARK: - Published State
    
    @Published private(set) var isListening: Bool = false
    @Published private(set) var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    @Published private(set) var lastDetectedPhrase: String?
    @Published private(set) var error: WakeWordError?
    
    // MARK: - Callback
    
    /// Called when "Clip That" is detected
    var onClipTriggered: (() -> Void)?
    
    // MARK: - Private Properties
    
    private let speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioFormat: AVAudioFormat?
    
    /// Cooldown to prevent repeated triggers
    private var lastTriggerTime: Date?
    private let triggerCooldown: TimeInterval = 2.0
    
    /// Session restart timer (iOS limits recognition to ~1 minute)
    private var sessionRestartTimer: Timer?
    private let sessionDuration: TimeInterval = 50.0
    
    /// The wake phrase to detect (case-insensitive)
    private let wakePhrase = "clip that"
    
    // MARK: - Initialization
    
    init() {
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }
    
    // MARK: - Public Methods
    
    /// Request speech recognition authorization
    func requestAuthorization() async {
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        authorizationStatus = status
    }
    
    /// Start listening for wake word on the given audio format
    /// - Parameter audioFormat: The format of the incoming audio buffers
    func startListening(audioFormat: AVAudioFormat) {
        guard authorizationStatus == .authorized else {
            error = .notAuthorized
            return
        }
        
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            error = .recognizerNotAvailable
            return
        }
        
        self.audioFormat = audioFormat
        startRecognitionSession()
        startSessionRestartTimer()
        isListening = true
        error = nil
    }
    
    /// Feed an audio buffer from the Meta SDK stream
    /// - Parameter buffer: PCM audio buffer to process
    func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard isListening else { return }
        recognitionRequest?.append(buffer)
    }
    
    /// Stop listening for wake word
    func stopListening() {
        stopRecognitionSession()
        stopSessionRestartTimer()
        isListening = false
    }
    
    // MARK: - Private Methods
    
    private func startRecognitionSession() {
        // Cancel any existing task
        recognitionTask?.cancel()
        recognitionTask = nil
        
        // Create new recognition request
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        
        // Use dictation task hint for continuous speech
        if #available(iOS 16.0, *) {
            request.addsPunctuation = false
        }
        
        recognitionRequest = request
        
        // Start recognition task
        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                self?.handleRecognitionResult(result, error: error)
            }
        }
    }
    
    private func handleRecognitionResult(_ result: SFSpeechRecognitionResult?, error: Error?) {
        if let error = error {
            // Check if it's just a timeout/cancellation (expected during restart)
            let nsError = error as NSError
            if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 1110 {
                // Recognition was cancelled, this is expected during restart
                return
            }
            
            self.error = .recognitionFailed(error.localizedDescription)
            return
        }
        
        guard let result = result else { return }
        
        let transcription = result.bestTranscription.formattedString.lowercased()
        lastDetectedPhrase = transcription
        
        // Check for wake phrase
        if transcription.contains(wakePhrase) {
            triggerClip()
        }
    }
    
    private func triggerClip() {
        // Check cooldown
        if let lastTrigger = lastTriggerTime,
           Date().timeIntervalSince(lastTrigger) < triggerCooldown {
            return
        }
        
        lastTriggerTime = Date()
        
        // Restart session to clear the transcription buffer
        restartRecognitionSession()
        
        // Fire callback
        onClipTriggered?()
    }
    
    private func restartRecognitionSession() {
        guard isListening else { return }
        
        stopRecognitionSession()
        startRecognitionSession()
    }
    
    private func stopRecognitionSession() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
    }
    
    private func startSessionRestartTimer() {
        stopSessionRestartTimer()
        
        sessionRestartTimer = Timer.scheduledTimer(withTimeInterval: sessionDuration, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.restartRecognitionSession()
            }
        }
    }
    
    private func stopSessionRestartTimer() {
        sessionRestartTimer?.invalidate()
        sessionRestartTimer = nil
    }
}

// MARK: - Error Types

enum WakeWordError: Error, LocalizedError {
    case notAuthorized
    case recognizerNotAvailable
    case recognitionFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Speech recognition not authorized. Please enable in Settings."
        case .recognizerNotAvailable:
            return "Speech recognizer is not available on this device."
        case .recognitionFailed(let message):
            return "Recognition failed: \(message)"
        }
    }
}
