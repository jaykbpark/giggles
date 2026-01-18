import AVFoundation
import Speech
import Combine

/// A segment of transcript with its timestamp
struct TranscriptSegment {
    let text: String
    let timestamp: Date
}

/// Detects "Clip That" and "Hey Clip" wake phrases from an audio stream using iOS Speech Recognition
/// and maintains a rolling 30-second transcript buffer
@MainActor
final class WakeWordDetector: ObservableObject {
    // MARK: - Published State
    
    @Published private(set) var isListening: Bool = false
    @Published private(set) var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    @Published private(set) var currentTranscript: String = ""
    @Published private(set) var error: WakeWordError?
    @Published private(set) var isProcessingQuestion: Bool = false
    
    // MARK: - Callbacks
    
    /// Called when "Clip That" is detected, passes the last 30 seconds of transcript
    var onClipTriggered: ((String) -> Void)?
    
    /// Called when "Hey Clip" is detected, passes the question that follows
    var onQuestionAsked: ((String) -> Void)?
    
    // MARK: - Transcript Buffer
    
    /// Rolling buffer of transcript segments
    private var transcriptBuffer: [TranscriptSegment] = []
    
    /// Track segments already appended for the current recognition session
    private var lastSegmentIndex: Int = 0
    private var currentSessionStartTime: Date?
    
    /// How long to keep transcript segments (30 seconds)
    private let bufferDuration: TimeInterval = 30.0
    
    /// The last complete transcript from the previous session (before restart)
    private var previousSessionTranscript: String = ""
    private var previousSessionTimestamp: Date = Date()
    
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
    
    /// The wake phrase for clip capture (case-insensitive)
    private let clipPhrase = "clip that"
    
    /// The wake phrase for asking questions (case-insensitive)
    private let questionPhrase = "hey clip"
    
    /// Track if we've already processed the current question to avoid duplicates
    private var lastProcessedQuestion: String = ""
    
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
    
    /// Get the last 30 seconds of transcript (for manual access if needed)
    func getRecentTranscript() -> String {
        return buildTranscriptFromBuffer()
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
        currentSessionStartTime = Date()
        lastSegmentIndex = 0
        
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
        
        let transcription = result.bestTranscription.formattedString
        currentTranscript = transcription
        
        // Append new transcript segments and prune old ones
        appendTranscriptSegments(from: result)
        pruneTranscriptBuffer()
        
        let lowercased = transcription.lowercased()
        
        // Check for "Hey Clip" question phrase first (higher priority)
        if lowercased.contains(questionPhrase) {
            triggerQuestion(from: transcription)
        }
        // Check for "Clip That" capture phrase
        else if lowercased.contains(clipPhrase) {
            triggerClip()
        }
    }
    
    private func appendTranscriptSegments(from result: SFSpeechRecognitionResult) {
        guard let sessionStart = currentSessionStartTime else { return }
        
        let segments = result.bestTranscription.segments
        if segments.count < lastSegmentIndex {
            // Recognition session reset or corrected significantly; start fresh for this session
            lastSegmentIndex = 0
        }
        
        guard lastSegmentIndex < segments.count else { return }
        
        for segment in segments[lastSegmentIndex...] {
            let segmentTime = sessionStart.addingTimeInterval(segment.timestamp)
            transcriptBuffer.append(
                TranscriptSegment(text: segment.substring, timestamp: segmentTime)
            )
        }
        
        lastSegmentIndex = segments.count
    }
    
    private func pruneTranscriptBuffer() {
        // Clean up old segments beyond 30 seconds
        let cutoffTime = Date().addingTimeInterval(-bufferDuration)
        transcriptBuffer.removeAll { $0.timestamp < cutoffTime }
    }
    
    private func buildTranscriptFromBuffer() -> String {
        let cutoffTime = Date().addingTimeInterval(-bufferDuration)
        let recentSegments = transcriptBuffer
            .filter { $0.timestamp >= cutoffTime }
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        var fullTranscript = recentSegments.joined(separator: " ")
        
        // Remove the wake phrase from the end if present
        let lowercased = fullTranscript.lowercased()
        if let range = lowercased.range(of: clipPhrase, options: .backwards) {
            let startIndex = fullTranscript.index(fullTranscript.startIndex, offsetBy: lowercased.distance(from: lowercased.startIndex, to: range.lowerBound))
            fullTranscript = String(fullTranscript[..<startIndex]).trimmingCharacters(in: .whitespaces)
        }
        
        return fullTranscript
    }
    
    private func triggerClip() {
        // Check cooldown
        if let lastTrigger = lastTriggerTime,
           Date().timeIntervalSince(lastTrigger) < triggerCooldown {
            return
        }
        
        lastTriggerTime = Date()
        
        // Build the transcript from the last 30 seconds
        let transcript = buildTranscriptFromBuffer()
        print("📝 [WakeWord] Transcript length: \(transcript.count) chars, segments: \(transcriptBuffer.count)")
        
        // Save current transcript before restarting
        saveCurrentSessionTranscript()
        
        // Restart session to clear the transcription buffer
        restartRecognitionSession()
        
        // Fire callback with the transcript
        onClipTriggered?(transcript)
    }
    
    private func triggerQuestion(from transcription: String) {
        // Extract the question (everything after "hey clip")
        let lowercased = transcription.lowercased()
        guard let range = lowercased.range(of: questionPhrase) else { return }
        
        // Get text after "hey clip"
        let afterPhrase = String(transcription[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        
        // Don't process empty questions or the same question twice
        guard !afterPhrase.isEmpty else { return }
        guard afterPhrase != lastProcessedQuestion else { return }
        
        // Check cooldown
        if let lastTrigger = lastTriggerTime,
           Date().timeIntervalSince(lastTrigger) < triggerCooldown {
            return
        }
        
        lastTriggerTime = Date()
        lastProcessedQuestion = afterPhrase
        isProcessingQuestion = true
        
        // Fire callback with the question
        onQuestionAsked?(afterPhrase)
        
        // Reset processing state after a delay (will be set to false when response completes)
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s minimum
        }
    }
    
    /// Call this when question processing is complete
    func questionProcessingComplete() {
        isProcessingQuestion = false
        lastProcessedQuestion = ""
        
        // Restart session to clear the transcription and listen fresh
        restartRecognitionSession()
    }
    
    private func saveCurrentSessionTranscript() {
        // Save the current transcript so it persists across session restarts
        if !currentTranscript.isEmpty {
            previousSessionTranscript = currentTranscript
            previousSessionTimestamp = Date()
        }
    }
    
    private func restartRecognitionSession() {
        guard isListening else { return }
        
        // Save current transcript before restart
        saveCurrentSessionTranscript()
        
        // Clear current transcript for new session
        currentTranscript = ""
        
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
            Task { @MainActor [weak self] in
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
