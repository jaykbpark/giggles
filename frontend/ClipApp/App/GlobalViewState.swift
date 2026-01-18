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
    @Published var availableTags: [String] = []
    
    // MARK: - Persistence
    
    private var clipsFileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("clips.json")
    }
    
    init() {
        loadClips()
        Task {
            await refreshAvailableTags()
        }
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
    /// Only shows clips that exist in the backend database
    /// Maps backend videos to local clips by localIdentifier (PHAsset ID = videoId)
    func syncWithBackend() async {
        do {
            let backendVideos = try await APIService.shared.fetchAllVideos()
            print("🔄 Syncing with backend: \(backendVideos.count) videos found")
            
            // Create a lookup by videoId (which is the PHAsset localIdentifier)
            var backendLookup: [String: APIService.BackendVideo] = [:]
            for video in backendVideos {
                backendLookup[video.videoId] = video
            }
            
            // Filter local clips to only show those that exist in backend
            // Update metadata from backend (title, transcript)
            var filteredClips: [ClipMetadata] = []
            
            for clip in clips {
                // Match by localIdentifier (PHAsset ID) which is the backend videoId
                guard let backendVideo = backendLookup[clip.localIdentifier] else {
                    print("⏭️ Skipping clip without backend match: \(clip.localIdentifier)")
                    continue
                }
                
                // Update with backend data, keep local file info
                let newTitle = backendVideo.title.isEmpty ? clip.title : backendVideo.title
                let newTranscript = backendVideo.transcript.isEmpty ? clip.transcript : backendVideo.transcript
                let newTopics = backendVideo.tags ?? clip.topics
                
                let updatedClip = ClipMetadata(
                    id: clip.id,
                    localIdentifier: clip.localIdentifier,
                    serverVideoId: clip.serverVideoId,
                    title: newTitle,
                    transcript: newTranscript,
                    topics: newTopics,
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
                filteredClips.append(updatedClip)
                print("✅ Synced clip \(clip.localIdentifier): \(newTitle)")
            }
            
            clips = filteredClips
            print("💾 Backend sync complete: \(filteredClips.count) clips displayed")
            
        } catch {
            print("⚠️ Backend sync failed: \(error.localizedDescription)")
            // On failure, keep local clips but warn user
        }
        
        await refreshAvailableTags()
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
    
    var filterTags: [String] {
        availableTags.isEmpty ? allTopics : availableTags
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
    
    func refreshAvailableTags() async {
        do {
            let tags = try await APIService.shared.fetchTags()
            await applyAvailableTags(tags)
        } catch {
            availableTags = []
            print("❌ Failed to fetch tags: \(error.localizedDescription)")
        }
    }
    
    private func applyAvailableTags(_ tags: [String]) async {
        let normalized = tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let uniqueTags = Array(Set(normalized)).sorted()
        availableTags = uniqueTags
        
        let availableSet = Set(uniqueTags)
        let filteredSelection = selectedTags.intersection(availableSet)
        if filteredSelection != selectedTags {
            selectedTags = filteredSelection
            await refreshTagSearch(tags: filteredSelection)
        }
    }
}
