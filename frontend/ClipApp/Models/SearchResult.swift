import Foundation

struct SearchResult: Codable, Sendable {
    let query: String
    let results: [RankedClip]
    let totalCount: Int
}

struct RankedClip: Codable, Identifiable, Sendable {
    let localIdentifier: String
    let relevanceScore: Double

    var id: String { localIdentifier }
}
