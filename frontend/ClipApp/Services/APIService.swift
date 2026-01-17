import Foundation

actor APIService {
    static let shared = APIService()
    private let baseURL = URL(string: "https://api.clip.app")!

    private init() {}

    func processClip(audioData: Data, localIdentifier: String) async throws -> ClipMetadata {
        var request = URLRequest(url: baseURL.appendingPathComponent("/api/process"))
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
