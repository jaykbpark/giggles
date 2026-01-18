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
    @Published var semanticResults: [ClipMetadata] = []
    @Published var tagResults: [ClipMetadata] = []
    @Published var isLoading: Bool = false
    @Published var selectedFeedTab: FeedTab = .all
    @Published var currentState: ClipState? = nil
    @Published var isSyncing: Bool = false
    
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
        // Sync with backend on app launch after a short delay
        // This prevents the "flash" where clips load, then reload after sync
        Task {
            // Wait for initial UI render to complete
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            await syncWithBackend()
        }
    }
    
    // MARK: - Backend Sync
    
    /// Sync local clips with backend data on app launch
    /// Maps backend videos to local clips by serverVideoId or timestamp
    func syncWithBackend() async {
        // Note: Removed isSyncing state changes to prevent unnecessary UI updates
        // The sync happens silently in the background
        
        do {
            let backendVideos = try await APIService.shared.fetchAllVideos()
            print("🔄 Syncing with backend: \(backendVideos.count) videos found")
            
            // Create a lookup by serverVideoId (the backend's videoId)
            var backendLookup: [Int: APIService.BackendVideo] = [:]
            for video in backendVideos {
                if let videoId = Int(video.videoId) {
                    backendLookup[videoId] = video
                }
            }
            
            // Update local clips with backend data
            // Only create new objects if data actually changed
            var updatedClips = clips
            var hasChanges = false
            
            for (index, clip) in updatedClips.enumerated() {
                // Match by serverVideoId if available
                if let serverVideoId = clip.serverVideoId,
                   let backendVideo = backendLookup[serverVideoId] {
                    // Check if backend has different data
                    let newTitle = backendVideo.title.isEmpty ? clip.title : backendVideo.title
                    let newTranscript = backendVideo.transcript.isEmpty ? clip.transcript : backendVideo.transcript
                    
                    // Only update if something actually changed
                    if newTitle != clip.title || newTranscript != clip.transcript {
                        updatedClips[index] = ClipMetadata(
                            id: clip.id,
                            localIdentifier: clip.localIdentifier,
                            serverVideoId: serverVideoId,
                            title: newTitle,
                            transcript: newTranscript,
                            topics: clip.topics,
                            capturedAt: clip.capturedAt,
                            duration: clip.duration,
                            isStarred: clip.isStarred,
                            context: clip.context,
                            audioNarrationURL: clip.audioNarrationURL,
                            clipState: clip.clipState,
                            thumbnailBase64: clip.thumbnailBase64,
                            isPortrait: clip.isPortrait,
                            localFileURL: clip.localFileURL,
                            captionSegments: clip.captionSegments,
                            showCaptions: clip.showCaptions,
                            captionStyle: clip.captionStyle
                        )
                        hasChanges = true
                        print("✅ Synced clip \(serverVideoId): \(newTitle)")
                    }
                }
            }
            
            // Only update if there were actual content changes
            if hasChanges {
                clips = updatedClips
                print("💾 Updated clips from backend sync")
            } else {
                print("✅ Backend sync complete - no changes needed")
            }
            
        } catch {
            print("⚠️ Backend sync failed: \(error.localizedDescription)")
            // Continue with local data - sync failure is non-fatal
        }
    }
    
    /// Get the current maximum serverVideoId from local clips
    var maxServerVideoId: Int {
        clips.compactMap { $0.serverVideoId }.max() ?? 0
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

        // Use backend semantic search results when searching
        if !searchText.isEmpty {
            result = semanticResults
        } else if !selectedTags.isEmpty {
            result = tagResults
        }

        // Apply legacy topic filter (single selection)
        if let topic = selectedTopic {
            result = result.filter { $0.topics.contains(topic) }
        }
        
        // Tag filtering handled via backend search when selectedTags is not empty

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
        
        // Ensure tag filtering is not blocked by an active semantic query
        if !searchText.isEmpty {
            searchText = ""
            semanticResults = []
        }
        
        let tags = selectedTags
        Task { @MainActor in
            await refreshTagSearch(tags: tags)
        }
    }

    func clearFilters() {
        searchText = ""
        selectedTopic = nil
        selectedTags = []
        semanticResults = []
        tagResults = []
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

    // MARK: - Backend Data

    func loadClipsFromBackend() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let fetched = try await APIService.shared.fetchAllClips()
            clips = fetched
            semanticResults = []
            tagResults = []
        } catch {
            print("❌ Failed to load clips from backend: \(error.localizedDescription)")
        }
    }

    func refreshSemanticSearch(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            semanticResults = []
            await loadClipsFromBackend()
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            semanticResults = try await APIService.shared.searchSemantic(trimmed)
        } catch {
            semanticResults = []
            print("❌ Semantic search failed: \(error.localizedDescription)")
        }
    }

    func refreshTagSearch(tags: Set<String>) async {
        guard !tags.isEmpty else {
            tagResults = []
            await loadClipsFromBackend()
            return
        }
        isLoading = true
        defer { isLoading = false }
        var merged: [ClipMetadata] = []
        var seen = Set<String>()
        for tag in tags {
            do {
                let results = try await APIService.shared.searchTag(tag)
                for clip in results where !seen.contains(clip.localIdentifier) {
                    seen.insert(clip.localIdentifier)
                    merged.append(clip)
                }
            } catch {
                print("❌ Tag search failed for \(tag): \(error.localizedDescription)")
            }
        }
        tagResults = merged
    }
}
