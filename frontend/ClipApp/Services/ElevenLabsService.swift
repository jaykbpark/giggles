import Foundation
import AVFoundation

/// Service for generating state-aware audio narration using ElevenLabs TTS API.
/// Works with or without Presage state data - gracefully handles missing state.
actor ElevenLabsService {
    static let shared = ElevenLabsService()
    
    // MARK: - Configuration
    
    private let apiKey: String?
    private let baseURL = URL(string: "https://api.elevenlabs.io/v1")!
    
    // Default voice ID (Rachel - natural, versatile voice)
    // Can be customized per emotion/state later
    private let defaultVoiceId = "21m00Tcm4TlvDq8ikWAM"
    
    // MARK: - Cache
    
    private var audioCache: [String: URL] = [:]
    private let cacheDirectory: URL
    
    // MARK: - Initialization
    
    init() {
        // Get API key from environment variable or Info.plist (same pattern as PresageService)
        if let envKey = ProcessInfo.processInfo.environment["ELEVENLABS_API_KEY"], !envKey.isEmpty {
            self.apiKey = envKey
        } else if let infoKey = Bundle.main.object(forInfoDictionaryKey: "ELEVENLABS_API_KEY") as? String,
                  !infoKey.isEmpty {
            self.apiKey = infoKey
        } else {
            self.apiKey = nil
        }
        
        // Setup cache directory
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        self.cacheDirectory = cacheDir.appendingPathComponent("elevenlabs_audio", isDirectory: true)
        
        // Create cache directory if needed
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    // MARK: - Public API
    
    /// Generate audio narration for a clip's transcript with optional state modulation.
    /// Returns cached audio URL if available, otherwise generates new audio.
    /// - Parameters:
    ///   - transcript: The text to narrate
    ///   - clipId: Unique identifier for caching
    ///   - state: Optional Presage state for voice modulation
    ///   - useHighQuality: If true, uses multilingual_v2 for better quality (slower). Default: false (uses turbo for speed)
    func generateNarration(
        transcript: String,
        clipId: UUID,
        state: ClipState? = nil,
        useHighQuality: Bool = false
    ) async throws -> URL {
        // Check cache first
        let cacheKey = cacheKey(for: clipId, state: state, quality: useHighQuality)
        if let cachedURL = audioCache[cacheKey],
           FileManager.default.fileExists(atPath: cachedURL.path) {
            return cachedURL
        }
        
        // Generate new audio
        guard apiKey != nil else {
            throw ElevenLabsError.apiKeyMissing
        }
        
        let audioURL = try await generateAudio(
            text: addStyleTags(transcript, state: state),
            voiceId: voiceId(for: state),
            modelId: useHighQuality ? "eleven_multilingual_v2" : "eleven_turbo_v2_5",
            voiceSettings: voiceSettings(for: state)
        )
        
        // Save to cache
        let cachedURL = saveToCache(audioURL, key: cacheKey)
        audioCache[cacheKey] = cachedURL
        
        return cachedURL
    }
    
    /// Clear all cached audio files
    func clearCache() {
        audioCache.removeAll()
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    // MARK: - Private Helpers
    
    private func generateAudio(
        text: String,
        voiceId: String,
        modelId: String,
        voiceSettings: VoiceSettings
    ) async throws -> URL {
        let url = baseURL.appendingPathComponent("/text-to-speech/\(voiceId)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey!, forHTTPHeaderField: "xi-api-key")
        
        var payload: [String: Any] = [
            "text": text,
            "model_id": modelId,
            "voice_settings": [
                "stability": voiceSettings.stability,
                "similarity_boost": voiceSettings.similarityBoost,
                "style": voiceSettings.style,
                "use_speaker_boost": voiceSettings.useSpeakerBoost
            ]
        ]
        
        // Add text normalization for better quality (especially with Flash/Turbo models)
        if modelId.contains("turbo") || modelId.contains("flash") {
            payload["apply_text_normalization"] = true
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ElevenLabsError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ElevenLabsError.apiError("HTTP \(httpResponse.statusCode): \(errorMessage)")
        }
        
        // Save to temporary file
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp3")
        
        try data.write(to: tempURL)
        return tempURL
    }
    
    /// Add style tags to text based on state for emotional tone modulation
    /// Uses ElevenLabs style tag format: [tag]text[/tag]
    private func addStyleTags(_ text: String, state: ClipState?) -> String {
        guard let state = state else {
            return text
        }
        
        // Map emotion to style tags
        let emotionTag: String
        switch state.emotionLabel.lowercased() {
        case "calm", "relaxed", "peaceful":
            emotionTag = "whisper"
        case "anxious", "stressed", "worried":
            emotionTag = "urgent"
        case "happy", "excited", "energetic":
            emotionTag = "happy"
        case "focused", "concentrated":
            emotionTag = "neutral" // Clear, focused delivery
        default:
            return text // No tags for unknown emotions
        }
        
        // Wrap text with style tag if emotion is recognized
        if emotionTag != "neutral" {
            return "[\(emotionTag)]\(text)[/\(emotionTag)]"
        }
        
        return text
    }
    
    private func voiceId(for state: ClipState?) -> String {
        // For now, use default voice. Later can map emotion → voice IDs
        // Example: Calm → soothing voice, Anxious → slightly faster voice
        return defaultVoiceId
    }
    
    private func voiceSettings(for state: ClipState?) -> VoiceSettings {
        guard let state = state else {
            return VoiceSettings.default
        }
        
        // Modulate based on state
        var settings = VoiceSettings.default
        
        // Stress level → stability (higher stress = slightly less stable, more dynamic)
        settings.stability = max(0.3, min(0.7, 0.5 - (state.stressLevel * 0.2)))
        
        // Emotion → style (calm = 0.0, anxious = 0.3)
        switch state.emotionLabel.lowercased() {
        case "calm", "relaxed", "peaceful":
            settings.style = 0.0
        case "anxious", "stressed", "worried":
            settings.style = 0.3
        case "happy", "excited", "energetic":
            settings.style = 0.2
        default:
            settings.style = 0.1
        }
        
        // Focus level → similarity boost (higher focus = clearer, more consistent)
        settings.similarityBoost = 0.5 + (state.focusLevel * 0.3)
        
        return settings
    }
    
    private func cacheKey(for clipId: UUID, state: ClipState?, quality: Bool) -> String {
        var key = clipId.uuidString
        if let state = state {
            // Include state in cache key so different states get different audio
            key += "_\(state.stressLevel)_\(state.focusLevel)_\(state.emotionLabel)"
        }
        key += quality ? "_hq" : "_fast"
        return key
    }
    
    private func saveToCache(_ sourceURL: URL, key: String) -> URL {
        let cachedURL = cacheDirectory.appendingPathComponent("\(key).mp3")
        try? FileManager.default.copyItem(at: sourceURL, to: cachedURL)
        return cachedURL
    }
}

// MARK: - Voice Settings

private struct VoiceSettings {
    var stability: Double
    var similarityBoost: Double
    var style: Double
    var useSpeakerBoost: Bool
    
    static let `default` = VoiceSettings(
        stability: 0.5,
        similarityBoost: 0.75,
        style: 0.1,
        useSpeakerBoost: true
    )
}

// Note: ClipState is defined in ClipMetadata.swift to avoid duplication

// MARK: - Errors

enum ElevenLabsError: Error, LocalizedError {
    case apiKeyMissing
    case apiError(String)
    case invalidResponse
    
    var errorDescription: String? {
        switch self {
        case .apiKeyMissing:
            return "ElevenLabs API key not found. Set ELEVENLABS_API_KEY environment variable."
        case .apiError(let message):
            return "ElevenLabs API error: \(message)"
        case .invalidResponse:
            return "Invalid response from ElevenLabs API"
        }
    }
}
