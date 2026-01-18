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
    
    enum UploadError: Error, LocalizedError {
        case invalidFile
        case badStatus(Int, String)
        
        var errorDescription: String? {
            switch self {
            case .invalidFile:
                return "Invalid or missing video file"
            case .badStatus(let code, let body):
                return "Upload failed (\(code)): \(body)"
            }
        }
    }
    
    struct BackendVideo: Codable {
        let videoId: String
        let title: String
        let transcript: String
        let timestamp: String
        let tags: [String]?
    }
    
    struct BackendVideosResponse: Codable {
        let success: Bool?
        let result: [BackendVideo]?
        let videos: [BackendVideo]?
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
    
    /// Upload a clip to the backend using multipart/form-data (POST /api/videos)
    func uploadClip(
        videoURL: URL,
        videoId: Int,
        title: String,
        timestamp: Date
    ) async throws {
        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            throw UploadError.invalidFile
        }
        
        let boundary = UUID().uuidString
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("/api/videos"))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        let timestampString = ISO8601DateFormatter().string(from: timestamp)
        let fileData = try Data(contentsOf: videoURL)
        let filename = videoURL.lastPathComponent
        
        var body = Data()
        body.appendFormField(name: "videoId", value: String(videoId), boundary: boundary)
        body.appendFormField(name: "title", value: title, boundary: boundary)
        body.appendFormField(name: "timestamp", value: timestampString, boundary: boundary)
        body.appendFileField(
            name: "videoData",
            filename: filename.isEmpty ? "clip.mov" : filename,
            mimeType: "video/quicktime",
            fileData: fileData,
            boundary: boundary
        )
        body.append("--\(boundary)--\r\n")
        request.httpBody = body
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UploadError.badStatus(-1, "No response")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw UploadError.badStatus(httpResponse.statusCode, bodyText)
        }
    }

    func fetchAllClips() async throws -> [ClipMetadata] {
        let url = Self.baseURL.appendingPathComponent("/api/videos")
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(BackendVideosResponse.self, from: data)
        let videos = response.result ?? response.videos ?? []
        return videos.map { mapBackendVideo($0) }
    }
    
    /// Fetch all videos from backend as raw BackendVideo objects (for sync)
    func fetchAllVideos() async throws -> [BackendVideo] {
        let url = Self.baseURL.appendingPathComponent("/api/videos")
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(BackendVideosResponse.self, from: data)
        return response.result ?? response.videos ?? []
    }
    
    func searchSemantic(_ query: String) async throws -> [ClipMetadata] {
        guard !query.isEmpty else { return [] }
        var components = URLComponents(url: Self.baseURL.appendingPathComponent("/api/search"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "type", value: "stringsearch"),
            URLQueryItem(name: "input", value: query)
        ]
        guard let url = components?.url else { return [] }
        let (data, _) = try await URLSession.shared.data(from: url)
        let videos = try decodeBackendVideos(from: data)
        return videos.map { mapBackendVideo($0) }
    }
    
    func searchTag(_ tag: String) async throws -> [ClipMetadata] {
        guard !tag.isEmpty else { return [] }
        var components = URLComponents(url: Self.baseURL.appendingPathComponent("/api/search"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "type", value: "tag"),
            URLQueryItem(name: "input", value: tag)
        ]
        guard let url = components?.url else { return [] }
        let (data, _) = try await URLSession.shared.data(from: url)
        let videos = try decodeBackendVideos(from: data)
        return videos.map { mapBackendVideo($0) }
    }
    
    private func decodeBackendVideos(from data: Data) throws -> [BackendVideo] {
        let decoder = JSONDecoder()
        if let wrapped = try? decoder.decode(BackendVideosResponse.self, from: data) {
            return wrapped.result ?? wrapped.videos ?? []
        }
        if let raw = try? decoder.decode([BackendVideo].self, from: data) {
            return raw
        }
        return []
    }
    
    private func mapBackendVideo(_ video: BackendVideo) -> ClipMetadata {
        let date = ISO8601DateFormatter().date(from: video.timestamp) ?? Date()
        return ClipMetadata(
            id: UUID(),
            localIdentifier: video.videoId,
            title: video.title,
            transcript: video.transcript,
            topics: video.tags ?? [],
            capturedAt: date,
            duration: 30.0,
            isStarred: false
        )
    }
}

private extension Data {
    mutating func appendFormField(name: String, value: String, boundary: String) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        append("\(value)\r\n")
    }
    
    mutating func appendFileField(
        name: String,
        filename: String,
        mimeType: String,
        fileData: Data,
        boundary: String
    ) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        append(fileData)
        append("\r\n")
    }
    
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
