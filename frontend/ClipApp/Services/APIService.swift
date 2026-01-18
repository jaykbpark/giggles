import Foundation

actor APIService {
    static let shared = APIService()
    
    /// Base URL for the Clip backend API.
    /// Override with CLIP_API_URL environment variable for testing different backends.
    private static var baseURL: URL {
        if let envURL = ProcessInfo.processInfo.environment["CLIP_API_URL"],
           let url = URL(string: envURL) {
            return url
        }
        // Production: Cloudflare tunnel
        return URL(string: "https://api.clippals.tech")!
    }

    private init() {}
    
    // MARK: - Health Check
    
    /// Check if the backend is reachable
    /// - Returns: Tuple with connection status and latency in milliseconds
    func checkHealth() async -> (isAlive: Bool, latencyMs: Int?) {
        let start = Date()
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("/health"))
        request.timeoutInterval = 5
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return (false, nil)
            }
            let latency = Int(Date().timeIntervalSince(start) * 1000)
            return (true, latency)
        } catch {
            #if DEBUG
            print("🔴 Health check failed: \(error.localizedDescription)")
            #endif
            return (false, nil)
        }
    }
    
    /// Get the current base URL (for debugging)
    static var currentBaseURL: String {
        baseURL.absoluteString
    }

    func processClip(audioData: Data, localIdentifier: String) async throws -> ClipMetadata {
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("/api/process"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "audio_blob": audioData.base64EncodedString(),
            "localIdentifier": localIdentifier
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(ClipMetadata.self, from: data)
    }

    func search(query: String) async -> [ClipMetadata] {
        guard !query.isEmpty else { return [] }

        let lowercased = query.lowercased()
        return MockData.clips.filter { clip in
            clip.title.lowercased().contains(lowercased) ||
            clip.transcript.lowercased().contains(lowercased) ||
            clip.topics.contains { $0.lowercased().contains(lowercased) }
        }
    }

    func fetchMetadata(for localIdentifier: String) async throws -> ClipMetadata? {
        return MockData.clips.first { $0.localIdentifier == localIdentifier }
    }
}
