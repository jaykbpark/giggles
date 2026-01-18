import Foundation
import AVFoundation
import Combine

/// Real-time Speech-to-Text service using ElevenLabs Scribe v2 Realtime WebSocket API.
/// Provides instant transcription with ~150ms latency.
@MainActor
final class ElevenLabsSTTService: NSObject, ObservableObject {
    static let shared = ElevenLabsSTTService()
    
    // MARK: - Published State
    
    @Published private(set) var isConnected: Bool = false
    @Published private(set) var isTranscribing: Bool = false
    @Published private(set) var currentPartialTranscript: String = ""
    @Published private(set) var committedTranscript: String = ""
    @Published private(set) var error: STTError?
    
    // MARK: - Callbacks
    
    /// Called when a partial transcript is received (updates frequently as user speaks)
    var onPartialTranscript: ((String) -> Void)?
    
    /// Called when a transcript segment is committed (finalized)
    var onCommittedTranscript: ((String) -> Void)?
    
    /// Called when specific phrases are detected (for wake word detection)
    var onPhraseDetected: ((DetectedPhrase) -> Void)?
    
    // MARK: - Configuration
    
    private let apiKey: String?
    private let websocketURL = "wss://api.elevenlabs.io/v1/speech-to-text/realtime"
    private let modelId = "scribe_v2_realtime"
    private let sampleRate: Int = 16000
    
    /// Phrases to detect in the transcript
    private let clipPhrases = ["clip that", "click that", "clip dat", "clip it", "clip this"]
    private let questionPhrase = "hey clip"
    
    // MARK: - WebSocket
    
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession!
    private var pingTimer: Timer?
    
    // MARK: - Audio Buffer
    
    /// Rolling buffer of committed transcripts for the last 30 seconds
    private var transcriptBuffer: [(text: String, timestamp: Date)] = []
    private let bufferDuration: TimeInterval = 30.0
    
    /// Track last phrase detection to prevent duplicates
    private var lastPhraseDetectionTime: Date?
    private let phraseCooldown: TimeInterval = 2.0
    
    // MARK: - Initialization
    
    override init() {
        // Get API key from environment or Info.plist
        if let envKey = ProcessInfo.processInfo.environment["ELEVENLABS_API_KEY"], !envKey.isEmpty {
            self.apiKey = envKey
            print("🎤 ElevenLabs STT: Using API key from environment")
        } else if let infoKey = Bundle.main.object(forInfoDictionaryKey: "ELEVENLABS_API_KEY") as? String,
                  !infoKey.isEmpty,
                  !infoKey.contains("YOUR_") {
            self.apiKey = infoKey
            print("🎤 ElevenLabs STT: Using API key from Info.plist")
        } else {
            self.apiKey = nil
            print("⚠️ ElevenLabs STT: NO API KEY FOUND!")
        }
        
        super.init()
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        self.urlSession = URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }
    
    // MARK: - Public API
    
    /// Check if the service is configured with an API key
    var isConfigured: Bool {
        apiKey != nil
    }
    
    /// Connect to ElevenLabs STT WebSocket
    func connect() async throws {
        guard let apiKey = apiKey else {
            throw STTError.apiKeyMissing
        }
        
        guard !isConnected else {
            print("🎤 ElevenLabs STT: Already connected")
            return
        }
        
        // Build WebSocket URL with query parameters
        var components = URLComponents(string: websocketURL)!
        components.queryItems = [
            URLQueryItem(name: "model_id", value: modelId),
            URLQueryItem(name: "language_code", value: "en"),
            URLQueryItem(name: "sample_rate", value: String(sampleRate)),
            URLQueryItem(name: "encoding", value: "pcm_s16le"),
            URLQueryItem(name: "include_timestamps", value: "true")
        ]
        
        guard let url = components.url else {
            throw STTError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        
        print("🎤 ElevenLabs STT: Connecting to \(url)")
        
        webSocketTask = urlSession.webSocketTask(with: request)
        webSocketTask?.resume()
        
        // Start receiving messages
        receiveMessage()
        
        // Start ping timer to keep connection alive
        startPingTimer()
        
        isConnected = true
        isTranscribing = true
        error = nil
        
        print("🎤 ElevenLabs STT: Connected successfully")
    }
    
    /// Disconnect from WebSocket
    func disconnect() {
        stopPingTimer()
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        isConnected = false
        isTranscribing = false
        currentPartialTranscript = ""
        print("🎤 ElevenLabs STT: Disconnected")
    }
    
    /// Send audio data to be transcribed
    /// - Parameter audioData: PCM audio data (16-bit, 16kHz, mono)
    func sendAudio(_ audioData: Data) {
        guard isConnected, let webSocketTask = webSocketTask else { return }
        
        let base64Audio = audioData.base64EncodedString()
        
        let message: [String: Any] = [
            "type": "audio",
            "data": base64Audio
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: message),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return
        }
        
        webSocketTask.send(.string(jsonString)) { [weak self] error in
            if let error = error {
                Task { @MainActor in
                    self?.handleWebSocketError(error)
                }
            }
        }
    }
    
    /// Send audio buffer from AVAudioPCMBuffer
    /// - Parameter buffer: Audio buffer to send
    func sendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let floatData = buffer.floatChannelData else { return }
        
        let frameLength = Int(buffer.frameLength)
        let channelData = floatData[0]
        
        // Convert Float32 to Int16 PCM
        var int16Data = [Int16](repeating: 0, count: frameLength)
        for i in 0..<frameLength {
            let sample = channelData[i]
            let clampedSample = max(-1.0, min(1.0, sample))
            int16Data[i] = Int16(clampedSample * Float(Int16.max))
        }
        
        // Convert to Data
        let audioData = int16Data.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer.baseAddress!.withMemoryRebound(to: UInt8.self, capacity: buffer.count * 2) { ptr in
                UnsafeBufferPointer(start: ptr, count: buffer.count * 2)
            })
        }
        
        sendAudio(audioData)
    }
    
    /// Get the last 30 seconds of committed transcript
    func getRecentTranscript() -> String {
        pruneTranscriptBuffer()
        return transcriptBuffer.map { $0.text }.joined(separator: " ")
    }
    
    /// Manually commit the current audio buffer (force finalization)
    func commitAudio() {
        guard isConnected, let webSocketTask = webSocketTask else { return }
        
        let message: [String: Any] = [
            "type": "flush"
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: message),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return
        }
        
        webSocketTask.send(.string(jsonString)) { [weak self] error in
            if let error = error {
                Task { @MainActor in
                    self?.handleWebSocketError(error)
                }
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success(let message):
                    self?.handleMessage(message)
                    // Continue receiving
                    self?.receiveMessage()
                    
                case .failure(let error):
                    self?.handleWebSocketError(error)
                }
            }
        }
    }
    
    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            parseTranscriptMessage(text)
            
        case .data(let data):
            if let text = String(data: data, encoding: .utf8) {
                parseTranscriptMessage(text)
            }
            
        @unknown default:
            break
        }
    }
    
    private func parseTranscriptMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        
        // Handle different message types from ElevenLabs
        if let messageType = json["type"] as? String {
            switch messageType {
            case "transcript":
                // Partial transcript update
                if let transcript = json["text"] as? String {
                    currentPartialTranscript = transcript
                    onPartialTranscript?(transcript)
                    checkForPhrases(in: transcript, isPartial: true)
                }
                
            case "final", "utterance_end":
                // Committed/final transcript
                if let transcript = json["text"] as? String, !transcript.isEmpty {
                    appendToBuffer(transcript)
                    committedTranscript = getRecentTranscript()
                    onCommittedTranscript?(transcript)
                    checkForPhrases(in: transcript, isPartial: false)
                    currentPartialTranscript = ""
                }
                
            case "error":
                if let errorMsg = json["message"] as? String {
                    error = .apiError(errorMsg)
                    print("🎤 ElevenLabs STT Error: \(errorMsg)")
                }
                
            default:
                // Handle other message types
                if let transcript = json["transcript"] as? String {
                    currentPartialTranscript = transcript
                    onPartialTranscript?(transcript)
                }
            }
        }
        
        // Alternative format: check for "partial" vs "final" fields
        if let partial = json["partial"] as? String {
            currentPartialTranscript = partial
            onPartialTranscript?(partial)
            checkForPhrases(in: partial, isPartial: true)
        }
        
        if let finalText = json["final"] as? String, !finalText.isEmpty {
            appendToBuffer(finalText)
            committedTranscript = getRecentTranscript()
            onCommittedTranscript?(finalText)
            checkForPhrases(in: finalText, isPartial: false)
            currentPartialTranscript = ""
        }
    }
    
    private func appendToBuffer(_ text: String) {
        transcriptBuffer.append((text: text, timestamp: Date()))
        pruneTranscriptBuffer()
    }
    
    private func pruneTranscriptBuffer() {
        let cutoff = Date().addingTimeInterval(-bufferDuration)
        transcriptBuffer.removeAll { $0.timestamp < cutoff }
    }
    
    private func checkForPhrases(in transcript: String, isPartial: Bool) {
        let lowercased = transcript.lowercased()
        
        // Check cooldown
        if let lastDetection = lastPhraseDetectionTime,
           Date().timeIntervalSince(lastDetection) < phraseCooldown {
            return
        }
        
        // Check for clip phrases
        for phrase in clipPhrases {
            if lowercased.contains(phrase) {
                lastPhraseDetectionTime = Date()
                let context = getRecentTranscript()
                onPhraseDetected?(.clipThat(transcript: context))
                print("🎤 ElevenLabs STT: Detected '\(phrase)' - triggering clip")
                return
            }
        }
        
        // Check for question phrase
        if lowercased.contains(questionPhrase) {
            // Extract the question (everything after "hey clip")
            if let range = lowercased.range(of: questionPhrase) {
                let question = String(transcript[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                if !question.isEmpty {
                    lastPhraseDetectionTime = Date()
                    onPhraseDetected?(.heyClip(question: question))
                    print("🎤 ElevenLabs STT: Detected 'hey clip' with question: \(question)")
                }
            }
        }
    }
    
    private func handleWebSocketError(_ error: Error) {
        print("🎤 ElevenLabs STT WebSocket error: \(error.localizedDescription)")
        self.error = .connectionFailed(error.localizedDescription)
        
        // Attempt to reconnect after a delay
        isConnected = false
        isTranscribing = false
        
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            if !self.isConnected {
                try? await self.connect()
            }
        }
    }
    
    private func startPingTimer() {
        stopPingTimer()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            self?.sendPing()
        }
    }
    
    private func stopPingTimer() {
        pingTimer?.invalidate()
        pingTimer = nil
    }
    
    private func sendPing() {
        webSocketTask?.sendPing { [weak self] error in
            if let error = error {
                Task { @MainActor in
                    self?.handleWebSocketError(error)
                }
            }
        }
    }
}

// MARK: - URLSessionWebSocketDelegate

extension ElevenLabsSTTService: URLSessionWebSocketDelegate {
    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        Task { @MainActor in
            print("🎤 ElevenLabs STT: WebSocket opened")
            self.isConnected = true
        }
    }
    
    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        Task { @MainActor in
            print("🎤 ElevenLabs STT: WebSocket closed with code \(closeCode)")
            self.isConnected = false
            self.isTranscribing = false
        }
    }
}

// MARK: - Supporting Types

/// Detected phrase type
enum DetectedPhrase {
    case clipThat(transcript: String)
    case heyClip(question: String)
}

/// STT service errors
enum STTError: Error, LocalizedError {
    case apiKeyMissing
    case invalidURL
    case connectionFailed(String)
    case apiError(String)
    
    var errorDescription: String? {
        switch self {
        case .apiKeyMissing:
            return "ElevenLabs API key not found. Set ELEVENLABS_API_KEY environment variable."
        case .invalidURL:
            return "Invalid WebSocket URL"
        case .connectionFailed(let message):
            return "Connection failed: \(message)"
        case .apiError(let message):
            return "API error: \(message)"
        }
    }
}
