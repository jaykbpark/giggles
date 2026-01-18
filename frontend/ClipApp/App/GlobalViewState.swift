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

enum FeedTab: String, CaseIterable {
    case all = "All"
    case starred = "Starred"
}

@MainActor
final class GlobalViewState: ObservableObject {
    @Published var viewMode: ViewMode = .grid
    @Published var searchText: String = ""
    @Published var isSearching: Bool = false
    @Published var selectedTopic: String?
    @Published var clips: [ClipMetadata] = [] {
        didSet {
            saveClips()
        }
    }
    @Published var isLoading: Bool = false
    @Published var selectedFeedTab: FeedTab = .all
    @Published var currentState: ClipState? = nil
    
    // Filter & Sort
    @Published var sortOrder: SortOrder = .recent
    @Published var selectedTags: Set<String> = []
    
    // MARK: - Persistence
    
    private var clipsFileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("clips.json")
    }
    
    init() {
        loadClips()
    }
    
    private func loadClips() {
        guard FileManager.default.fileExists(atPath: clipsFileURL.path),
              let data = try? Data(contentsOf: clipsFileURL),
              let decoded = try? JSONDecoder().decode([ClipMetadata].self, from: data) else {
            // No persisted clips - start with empty array
            return
        }
        // Temporarily disable didSet to avoid re-saving
        clips = decoded
        print("📂 Loaded \(decoded.count) clips from storage")
    }
    
    private func saveClips() {
        do {
            let data = try JSONEncoder().encode(clips)
            try data.write(to: clipsFileURL)
            print("💾 Saved \(clips.count) clips to storage")
        } catch {
            print("⚠️ Failed to save clips: \(error.localizedDescription)")
        }
    }

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

        // Apply feed tab filter
        if selectedFeedTab == .starred {
            result = result.filter { $0.isStarred }
        }

        return result
    }

    var starredClips: [ClipMetadata] {
        clips
            .filter { $0.isStarred }
            .sorted { $0.capturedAt > $1.capturedAt }
    }

    var allTopics: [String] {
        Array(Set(clips.flatMap { $0.topics })).sorted()
    }
    
    var hasActiveFilters: Bool {
        !selectedTags.isEmpty || sortOrder != .recent || !searchText.isEmpty || selectedFeedTab != .all
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
        selectedFeedTab = .all
    }

    func toggleStar(for clipId: UUID) {
        updateClip(clipId) { clip in
            clip.isStarred.toggle()
        }
    }

    private func updateClip(_ clipId: UUID, update: (inout ClipMetadata) -> Void) {
        guard let index = clips.firstIndex(where: { $0.id == clipId }) else { return }
        var clip = clips[index]
        update(&clip)
        clips[index] = clip
    }
}
