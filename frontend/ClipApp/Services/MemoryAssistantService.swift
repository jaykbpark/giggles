import Foundation
import AVFoundation
import Combine

/// Memory Assistant state for UI feedback
enum MemoryAssistantState: Equatable {
    case idle
    case listening
    case thinking
    case speaking
    case error(String)
    
    var displayText: String {
        switch self {
        case .idle: return ""
        case .listening: return "Listening..."
        case .thinking: return "Thinking..."
        case .speaking: return "Speaking..."
        case .error(let msg): return msg
        }
    }
    
    var isActive: Bool {
        switch self {
        case .idle: return false
        default: return true
        }
    }
}

/// Orchestrates the Memory Assistant flow: Question → Search → Gemini → ElevenLabs → Speak
@MainActor
final class MemoryAssistantService: ObservableObject {
    
    // MARK: - Published State
    
    @Published private(set) var state: MemoryAssistantState = .idle
    @Published private(set) var lastQuestion: String?
    @Published private(set) var lastResponse: String?
    
    // MARK: - Audio Playback
    
    private var audioPlayer: AVPlayer?
    private var playerObserver: Any?
    
    // MARK: - Completion Callback
    
    /// Called when the assistant finishes processing (success or failure)
    var onComplete: (() -> Void)?
    
    // MARK: - Public API
    
    /// Process a question from the user using their clip history.
    /// - Parameters:
    ///   - question: The question asked (e.g., "What did I do yesterday?")
    ///   - clips: All available clips to search through
    func askQuestion(_ question: String, clips: [ClipMetadata]) async {
        // Update state
        state = .thinking
        lastQuestion = question
        lastResponse = nil
        
        print("🧠 Memory Assistant: Processing question: \"\(question)\"")
        
        do {
            // Step 1: Find relevant clips via semantic search
            let relevantClips = findRelevantClips(for: question, in: clips)
            print("🧠 Memory Assistant: Found \(relevantClips.count) relevant clips")
            
            // Step 2: Generate response using Gemini
            let response = try await GeminiService.shared.generateResponse(
                question: question,
                clips: relevantClips
            )
            print("🧠 Memory Assistant: Generated response: \"\(response)\"")
            
            lastResponse = response
            
            // Step 3: Speak the response using ElevenLabs
            state = .speaking
            try await speakResponse(response)
            
            // Success - return to idle
            state = .idle
            
        } catch {
            print("🧠 Memory Assistant: Error - \(error.localizedDescription)")
            state = .error(error.localizedDescription)
            
            // Reset to idle after showing error
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
                state = .idle
            }
        }
        
        // Notify completion
        onComplete?()
    }
    
    /// Stop any ongoing speech playback
    func stopSpeaking() {
        audioPlayer?.pause()
        audioPlayer = nil
        if state == .speaking {
            state = .idle
        }
    }
    
    /// Cancel current operation and return to idle
    func cancel() {
        stopSpeaking()
        state = .idle
        onComplete?()
    }
    
    // MARK: - Private Helpers
    
    /// Find clips relevant to the question using semantic matching
    private func findRelevantClips(for question: String, in clips: [ClipMetadata]) -> [ClipMetadata] {
        let lowercasedQuestion = question.lowercased()
        
        // Time-based filtering
        let calendar = Calendar.current
        let now = Date()
        
        // Check for time references in question
        var filteredClips = clips
        
        if lowercasedQuestion.contains("yesterday") {
            let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
            filteredClips = clips.filter { calendar.isDate($0.capturedAt, inSameDayAs: yesterday) }
        } else if lowercasedQuestion.contains("today") {
            filteredClips = clips.filter { calendar.isDateInToday($0.capturedAt) }
        } else if lowercasedQuestion.contains("this week") || lowercasedQuestion.contains("last few days") {
            let weekAgo = calendar.date(byAdding: .day, value: -7, to: now)!
            filteredClips = clips.filter { $0.capturedAt >= weekAgo }
        } else if lowercasedQuestion.contains("this morning") {
            let startOfDay = calendar.startOfDay(for: now)
            let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: now)!
            filteredClips = clips.filter { $0.capturedAt >= startOfDay && $0.capturedAt < noon }
        }
        
        // Keyword matching for relevance scoring
        let keywords = extractKeywords(from: question)
        
        // Score and sort clips by relevance
        let scoredClips = filteredClips.map { clip -> (ClipMetadata, Int) in
            var score = 0
            let clipText = "\(clip.title) \(clip.transcript) \(clip.topics.joined(separator: " "))".lowercased()
            
            for keyword in keywords {
                if clipText.contains(keyword) {
                    score += 2
                }
            }
            
            // Boost recent clips
            let hoursAgo = now.timeIntervalSince(clip.capturedAt) / 3600
            if hoursAgo < 24 {
                score += 3
            } else if hoursAgo < 72 {
                score += 1
            }
            
            // Boost clips with context
            if clip.context?.locationName != nil {
                score += 1
            }
            
            return (clip, score)
        }
        
        // Sort by score (descending) and return top results
        let sorted = scoredClips.sorted { $0.1 > $1.1 }
        
        // Return all clips if none matched well, otherwise return top scorers
        if sorted.first?.1 == 0 {
            // No good matches - return most recent clips
            return Array(clips.sorted { $0.capturedAt > $1.capturedAt }.prefix(5))
        }
        
        return sorted.prefix(10).map { $0.0 }
    }
    
    /// Extract meaningful keywords from a question
    private func extractKeywords(from question: String) -> [String] {
        let stopWords = Set(["what", "did", "do", "i", "me", "my", "the", "a", "an", "is", "was", "were", "are",
                             "have", "has", "had", "when", "where", "who", "how", "why", "about", "with",
                             "hey", "clip", "tell", "show", "find", "remember", "recall"])
        
        let words = question.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !stopWords.contains($0) && $0.count > 2 }
        
        return words
    }
    
    /// Speak text using ElevenLabs TTS
    private func speakResponse(_ text: String) async throws {
        print("🔊 Speaking: Getting audio from ElevenLabs...")
        let audioURL = try await ElevenLabsService.shared.speakText(text)
        print("🔊 Speaking: Got audio URL: \(audioURL)")
        
        // Configure audio session for playback
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try audioSession.setActive(true)
            print("🔊 Speaking: Audio session configured")
        } catch {
            print("🔊 Speaking: Audio session error: \(error)")
        }
        
        // Play the audio
        await MainActor.run {
            let playerItem = AVPlayerItem(url: audioURL)
            audioPlayer = AVPlayer(playerItem: playerItem)
            audioPlayer?.volume = 1.0
            
            // Listen for playback completion
            playerObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: playerItem,
                queue: .main
            ) { [weak self] _ in
                print("🔊 Speaking: Playback finished")
                self?.audioPlayer = nil
                if self?.playerObserver != nil {
                    NotificationCenter.default.removeObserver(self!.playerObserver!)
                    self?.playerObserver = nil
                }
            }
            
            print("🔊 Speaking: Starting playback...")
            audioPlayer?.play()
        }
        
        // Wait for audio to finish (with timeout)
        var waitTime: Double = 0
        let maxWait: Double = 60 // 60 second max
        while audioPlayer != nil && waitTime < maxWait {
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            waitTime += 0.1
        }
        
        // Deactivate audio session
        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
    }
}
