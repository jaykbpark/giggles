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

enum SortOrder: String, CaseIterable {
    case recent = "Recent"
    case oldest = "Oldest"
    case longest = "Longest"
    
    var icon: String {
        switch self {
        case .recent: return "arrow.down"
        case .oldest: return "arrow.up"
        case .longest: return "clock"
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
    
    // Filter & Sort
    @Published var sortOrder: SortOrder = .recent
    @Published var selectedTags: Set<String> = []

    var filteredClips: [ClipMetadata] {
        var result = clips

        // Apply search filter
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { clip in
                clip.title.lowercased().contains(query) ||
                clip.transcript.lowercased().contains(query) ||
                clip.topics.contains { $0.lowercased().contains(query) }
            }
        }

        // Apply legacy topic filter (single selection)
        if let topic = selectedTopic {
            result = result.filter { $0.topics.contains(topic) }
        }
        
        // Apply tag filter (multi-selection)
        if !selectedTags.isEmpty {
            result = result.filter { clip in
                !selectedTags.isDisjoint(with: Set(clip.topics))
            }
        }
        
        // Apply sorting
        switch sortOrder {
        case .recent:
            result.sort { $0.capturedAt > $1.capturedAt }
        case .oldest:
            result.sort { $0.capturedAt < $1.capturedAt }
        case .longest:
            result.sort { $0.duration > $1.duration }
        }

        return result
    }

    var allTopics: [String] {
        Array(Set(clips.flatMap { $0.topics })).sorted()
    }
    
    var hasActiveFilters: Bool {
        !selectedTags.isEmpty || sortOrder != .recent
    }

    func toggleViewMode() {
        withAnimation(.easeInOut(duration: 0.2)) {
            viewMode = viewMode == .grid ? .list : .grid
        }
    }
    
    func toggleTag(_ tag: String) {
        if selectedTags.contains(tag) {
            selectedTags.remove(tag)
        } else {
            selectedTags.insert(tag)
        }
    }

    func clearFilters() {
        searchText = ""
        selectedTopic = nil
        selectedTags = []
        sortOrder = .recent
    }
}
