import Foundation

/// Service for generating conversational responses using Google's Gemini API.
/// Used by the Memory Assistant to answer questions about captured clips.
actor GeminiService {
    static let shared = GeminiService()
    
    // MARK: - Configuration
    
    private let apiKey: String?
    private let baseURL = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent")!
    
    // MARK: - Initialization
    
    init() {
        // Get API key from environment variable or Info.plist
        if let envKey = ProcessInfo.processInfo.environment["GEMINI_API_KEY"], !envKey.isEmpty {
            self.apiKey = envKey
        } else if let infoKey = Bundle.main.object(forInfoDictionaryKey: "GEMINI_API_KEY") as? String,
                  !infoKey.isEmpty {
            self.apiKey = infoKey
        } else {
            self.apiKey = nil
        }
    }
    
    // MARK: - Public API
    
    /// Generate a conversational response to a question based on clip context.
    /// - Parameters:
    ///   - question: The user's question (e.g., "What did I do yesterday?")
    ///   - clips: Array of relevant clips with transcripts
    /// - Returns: A natural language response suitable for TTS
    func generateResponse(question: String, clips: [ClipMetadata]) async throws -> String {
        guard let apiKey = apiKey else {
            throw GeminiError.apiKeyMissing
        }
        
        // Build context from clips
        let context = buildContext(from: clips)
        
        // Create the prompt
        let prompt = buildPrompt(question: question, context: context)
        
        // Call Gemini API
        return try await callGemini(prompt: prompt, apiKey: apiKey)
    }
    
    // MARK: - Private Helpers
    
    private func buildContext(from clips: [ClipMetadata]) -> String {
        guard !clips.isEmpty else {
            return "No recent memories found."
        }
        
        var context = ""
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        
        for clip in clips.prefix(10) { // Limit to 10 most relevant clips
            let dateStr = dateFormatter.string(from: clip.capturedAt)
            var entry = "[\(dateStr)] \(clip.title): \(clip.transcript)"
            
            // Add location if available
            if let location = clip.context?.locationName {
                entry += " (at \(location))"
            }
            
            // Add emotional state if available
            if let state = clip.clipState {
                entry += " [Feeling: \(state.emotionLabel)]"
            }
            
            context += entry + "\n\n"
        }
        
        return context
    }
    
    private func buildPrompt(question: String, context: String) -> String {
        return """
        You are a smart, casual personal assistant that helps recall information from captured video clips.
        
        RULES:
        1. Keep responses brief (2-3 sentences max) - they will be spoken aloud
        2. Be direct and conversational - talk like a friend, not a caregiver
        3. NO condescending phrases like "oh dear", "don't worry", "it's okay" etc
        4. If you don't have the info, just say "I don't have that in your clips"
        5. Reference specific details when relevant (names, places, what was said)
        6. Natural phrasing for text-to-speech - no bullet points or formatting
        7. Jump right into the answer - no preamble
        
        CLIP HISTORY:
        \(context)
        
        QUESTION: "\(question)"
        
        Answer directly:
        """
    }
    
    private func callGemini(prompt: String, apiKey: String) async throws -> String {
        var urlComponents = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        urlComponents.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        
        guard let url = urlComponents.url else {
            throw GeminiError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": prompt]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.7,
                "maxOutputTokens": 150, // Keep responses short for TTS
                "topP": 0.9
            ],
            "safetySettings": [
                ["category": "HARM_CATEGORY_HARASSMENT", "threshold": "BLOCK_NONE"],
                ["category": "HARM_CATEGORY_HATE_SPEECH", "threshold": "BLOCK_NONE"],
                ["category": "HARM_CATEGORY_SEXUALLY_EXPLICIT", "threshold": "BLOCK_NONE"],
                ["category": "HARM_CATEGORY_DANGEROUS_CONTENT", "threshold": "BLOCK_NONE"]
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw GeminiError.apiError("HTTP \(httpResponse.statusCode): \(errorMessage)")
        }
        
        // Parse response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            throw GeminiError.parseError
        }
        
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Errors

enum GeminiError: Error, LocalizedError {
    case apiKeyMissing
    case apiError(String)
    case invalidResponse
    case invalidURL
    case parseError
    
    var errorDescription: String? {
        switch self {
        case .apiKeyMissing:
            return "Gemini API key not found. Set GEMINI_API_KEY environment variable."
        case .apiError(let message):
            return "Gemini API error: \(message)"
        case .invalidResponse:
            return "Invalid response from Gemini API"
        case .invalidURL:
            return "Invalid API URL"
        case .parseError:
            return "Failed to parse Gemini response"
        }
    }
}
