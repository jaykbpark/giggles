import Foundation
import FoundationModels

/// Service for generating clip titles using on-device LLM (iOS 26 Foundation Models)
@MainActor
final class TitleGenerator {
    
    // MARK: - Singleton
    
    static let shared = TitleGenerator()
    
    // MARK: - State
    
    private(set) var isAvailable: Bool = false
    private(set) var unavailableReason: String?
    
    // MARK: - Initialization
    
    init() {
        checkAvailability()
    }
    
    // MARK: - Availability Check
    
    private func checkAvailability() {
        let model = SystemLanguageModel.default
        
        switch model.availability {
        case .available:
            isAvailable = true
            unavailableReason = nil
            print("✨ TitleGenerator: On-device LLM available")
            
        case .unavailable(.deviceNotEligible):
            isAvailable = false
            unavailableReason = "Device not eligible for Apple Intelligence"
            print("⚠️ TitleGenerator: Device not eligible")
            
        case .unavailable(.appleIntelligenceNotEnabled):
            isAvailable = false
            unavailableReason = "Apple Intelligence not enabled"
            print("⚠️ TitleGenerator: Apple Intelligence not enabled")
            
        case .unavailable(.modelNotReady):
            isAvailable = false
            unavailableReason = "Model still downloading"
            print("⚠️ TitleGenerator: Model not ready")
            
        case .unavailable(let other):
            isAvailable = false
            unavailableReason = "Unavailable: \(other)"
            print("⚠️ TitleGenerator: Unavailable - \(other)")
        }
    }
    
    // MARK: - Title Generation
    
    /// Generate a short title from a transcript using on-device LLM
    /// - Parameter transcript: The clip transcript text
    /// - Returns: A generated title (2-4 words) or nil if generation fails
    func generateTitle(from transcript: String) async -> String? {
        // Re-check availability
        checkAvailability()
        
        guard isAvailable else {
            print("❌ TitleGenerator: LLM not available - \(unavailableReason ?? "unknown")")
            return generateFallbackTitle(from: transcript)
        }
        
        do {
            let session = LanguageModelSession(
                instructions: """
                You are a title generator. Given a transcript, create a short, catchy title.
                Rules:
                - Use 2-4 words only
                - Be descriptive but concise
                - Capture the main topic or mood
                - Don't use quotes or punctuation
                - Don't include "Title:" or similar prefixes
                """
            )
            
            let prompt = "Generate a title for this transcript:\n\n\(transcript)"
            let response = try await session.respond(to: prompt)
            
            // Clean up the response
            let title = response.content
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\"", with: "")
                .replacingOccurrences(of: "Title:", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            print("✨ TitleGenerator: Generated '\(title)'")
            return title.isEmpty ? nil : title
            
        } catch {
            print("❌ TitleGenerator: Error - \(error.localizedDescription)")
            return generateFallbackTitle(from: transcript)
        }
    }
    
    // MARK: - Fallback
    
    /// Simple fallback title generation when LLM is unavailable
    private func generateFallbackTitle(from transcript: String) -> String? {
        // Extract first few meaningful words
        let words = transcript
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.count > 2 }
            .prefix(4)
        
        guard !words.isEmpty else { return nil }
        
        let title = words.joined(separator: " ")
        return title.count > 30 ? String(title.prefix(30)) + "..." : title
    }
}
