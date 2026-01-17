import SwiftUI
import Combine

enum ViewMode: String, CaseIterable {
    case grid
    case list

    var icon: String {
        switch self {
        case .grid: return "square.grid.3x3"
        case .list: return "list.bullet"
        }
    }
}

@MainActor
final class GlobalViewState: ObservableObject {
    @Published var viewMode: ViewMode = .grid
    @Published var searchText: String = ""
    @Published var isSearching: Bool = false
    @Published var selectedTopic: String?
    @Published var clips: [ClipMetadata] = MockData.clips
    @Published var isLoading: Bool = false

    var filteredClips: [ClipMetadata] {
        var result = clips

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { clip in
                clip.title.lowercased().contains(query) ||
                clip.transcript.lowercased().contains(query) ||
                clip.topics.contains { $0.lowercased().contains(query) }
            }
        }

        if let topic = selectedTopic {
            result = result.filter { $0.topics.contains(topic) }
        }

        return result
    }

    var allTopics: [String] {
        Array(Set(clips.flatMap { $0.topics })).sorted()
    }

    func toggleViewMode() {
        withAnimation(.easeInOut(duration: 0.2)) {
            viewMode = viewMode == .grid ? .list : .grid
        }
    }

    func clearFilters() {
        searchText = ""
        selectedTopic = nil
    }
}
