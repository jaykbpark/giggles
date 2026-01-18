import SwiftUI
import AVFoundation
import Combine
import Photos
import CoreMedia

struct RootView: View {
    @StateObject private var viewState = GlobalViewState()
    @StateObject private var glassesManager = MetaGlassesManager.shared
    @StateObject private var captureCoordinator = ClipCaptureCoordinator.shared
    @StateObject private var memoryAssistant = MemoryAssistantService()
    @State private var selectedClip: ClipMetadata?
    @State private var showSearch = false
    @State private var showSearchSuggestions = false
    @State private var isRecording = false
    @State private var showRecordConfirmation = false
    @State private var recordPulse = false
    @State private var recordProgress: Double = 0
    @State private var showCompletionBurst = false
    @State private var completionRingScale: CGFloat = 1.0
    @State private var completionRingScale2: CGFloat = 1.0
    @State private var completionOpacity: Double = 0
    @State private var buttonBounceScale: CGFloat = 1.0
    @State private var cancellables = Set<AnyCancellable>()
    @State private var showBufferTooShortMessage = false
    @State private var showNoGlassesMessage = false
    @State private var isSavingClip = false
    @State private var showGlassesPreview = false
    @State private var showNoVideoFramesMessage = false
    @State private var showStreamErrorMessage = false
    @State private var streamErrorText = ""
    @State private var showPhotoSaveError = false
    @State private var photoSaveErrorText = ""
    @State private var showExportErrorMessage = false
    @State private var exportErrorText = ""
    @State private var selectedTab: AppTab = .clips
    
    // Trim view state
    @State private var showTrimView = false
    @State private var clipToTrim: URL?
    @State private var trimTranscript: String = ""
    
    @Namespace private var namespace
    
    enum AppTab: String, CaseIterable {
        case clips = "Clips"
        case ask = "Ask Clip"
        
        var icon: String {
            switch self {
            case .clips: return "play.rectangle.on.rectangle"
            case .ask: return "brain.head.profile"
            }
        }
    }

    var body: some View {
        ZStack {
            // Background
            AppGradients.warmAmbient
                .ignoresSafeArea()
            
            // Tab content with swipe gesture
            Group {
                if selectedTab == .clips {
                    clipsTabContent
                } else {
                    askTabContent
                }
            }
            .gesture(
                DragGesture(minimumDistance: 30, coordinateSpace: .local)
                    .onEnded { value in
                        let horizontalSwipe = value.translation.width
                        let threshold: CGFloat = 50
                        
                        if horizontalSwipe < -threshold && selectedTab == .clips {
                            // Swipe left → go to Ask
                            HapticManager.playLight()
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                selectedTab = .ask
                            }
                        } else if horizontalSwipe > threshold && selectedTab == .ask {
                            // Swipe right → go to Clips
                            HapticManager.playLight()
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                selectedTab = .clips
                            }
                        }
                    }
            )
            
            // Bottom tab bar (always visible except in detail view)
            if selectedClip == nil && !showSearch {
                VStack {
                    Spacer()
                    bottomTabBar
                }
            }
            
            // Overlays
            overlaysContent
        }
        .task {
            await setupCaptureCoordinator()
            // Only load from backend if we don't have local clips
            // GlobalViewState loads from local storage synchronously in init()
            if viewState.clips.isEmpty {
                await viewState.loadClipsFromBackend()
            }
        }
        .onChange(of: viewState.searchText) { _, newValue in
            Task { @MainActor in
                await viewState.refreshSemanticSearch(query: newValue)
            }
        }
        .onChange(of: showSearch) { _, newValue in
            if newValue {
                showSearchSuggestions = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        showSearchSuggestions = true
                    }
                }
            } else {
                showSearchSuggestions = false
            }
        }
    }
    
    // MARK: - Clips Tab Content
    
    private var clipsTabContent: some View {
        ZStack {
            VStack(spacing: 0) {
                headerBar

                FilterBar(viewState: viewState)
                    .padding(.bottom, 4)

                FeedView(
                    viewState: viewState,
                    clips: viewState.filteredClips,
                    isLoading: viewState.isLoading,
                    selectedClip: $selectedClip,
                    namespace: namespace
                )
            }
            .opacity(selectedClip != nil ? 0 : 1)
            .blur(radius: showSearch ? 6 : 0)
            .animation(.easeOut(duration: 0.25), value: showSearch)
            
            // Floating record button
            if selectedClip == nil && !showSearch {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        recordButton
                            .padding(.trailing, 24)
                            .padding(.bottom, 85) // Above floating tab
                    }
                }
                .transition(.opacity)
            }
        } // End clipsTabContent ZStack
    }
    
    // Live glasses preview (top-right corner) - should only be shown on clips tab
    private var glassesPreviewOverlay: some View {
        Group {
            if showGlassesPreview && selectedClip == nil && !showSearch && selectedTab == .clips {
                VStack {
                    HStack {
                        Spacer()
                        GlassesPreviewView()
                            .padding(.top, 70)
                            .padding(.trailing, 16)
                            .onTapGesture {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    showGlassesPreview = false
                                }
                            }
                            .onAppear {
                                print("👁️ [Preview] Preview overlay appeared")
                                print("   - showGlassesPreview: \(showGlassesPreview)")
                                print("   - selectedClip: \(selectedClip?.localIdentifier ?? "nil")")
                                print("   - showSearch: \(showSearch)")
                                print("   - selectedTab: \(selectedTab)")
                                print("   - isVideoStreaming: \(glassesManager.isVideoStreaming)")
                            }
                    }
                    Spacer()
                }
                .transition(.opacity)
                .zIndex(10)
            } else if showGlassesPreview {
                // Debug: Log why preview isn't showing
                Color.clear
                    .onAppear {
                        print("👁️ [Preview] Preview hidden - showGlassesPreview: \(showGlassesPreview), selectedClip: \(selectedClip != nil), showSearch: \(showSearch), selectedTab: \(selectedTab)")
                    }
            }
        }
    }
    
    // MARK: - Trim View Overlay
    
    @ViewBuilder
    private var trimViewOverlay: some View {
        if showTrimView, let videoURL = clipToTrim {
            TrimView(
                videoURL: videoURL,
                onSave: { startTime, endTime in
                    Task {
                        await handleTrimComplete(
                            sourceURL: videoURL,
                            startTime: startTime,
                            endTime: endTime,
                            transcript: trimTranscript
                        )
                    }
                    withAnimation {
                        showTrimView = false
                        clipToTrim = nil
                    }
                },
                onSaveFull: {
                    // Save without trimming
                    addClipToTimeline(exportedURL: videoURL, transcript: trimTranscript)
                    Task {
                        await handleExportedClip(url: videoURL, transcript: trimTranscript)
                    }
                    HapticManager.playSuccess()
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        showRecordConfirmation = true
                    }
                    withAnimation {
                        showTrimView = false
                        clipToTrim = nil
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation(.spring(response: 0.3)) {
                            showRecordConfirmation = false
                        }
                    }
                },
                onDiscard: {
                    // Discard clip without saving
                    HapticManager.playLight()
                    try? FileManager.default.removeItem(at: videoURL)
                    withAnimation {
                        showTrimView = false
                        clipToTrim = nil
                    }
                }
            )
            .transition(.opacity)
            .zIndex(300)
        }
        }
            
    // MARK: - Ask Tab Content
    
    private var askTabContent: some View {
        MemoryAssistantView(
            memoryAssistant: memoryAssistant,
            viewState: viewState,
            isEmbedded: true
        )
        .padding(.bottom, 70) // Space for floating tab
    }
    
    // MARK: - Floating Tab Switcher
    
    private var bottomTabBar: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Button {
                    HapticManager.playLight()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        selectedTab = tab
                    }
                } label: {
                    Image(systemName: tab.icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(selectedTab == tab ? .white : AppColors.textPrimary)
                        .frame(width: 48, height: 48)
                        .background {
                            if selectedTab == tab {
                                Circle()
                                    .fill(AppColors.accent)
                                    .matchedGeometryEffect(id: "tabIndicator", in: namespace)
                            }
                        }
                }
            }
        }
        .padding(6)
        .background {
            Capsule()
                .fill(.white.opacity(0.95))
                .shadow(color: .black.opacity(0.12), radius: 20, y: 8)
        }
        .padding(.bottom, 20)
    }
    
    // MARK: - Overlays Content
    
    @ViewBuilder
    private var overlaysContent: some View {
        // Live glasses preview
        glassesPreviewOverlay

        // Clip processing indicator
        processingIndicator
        
        // Detail view overlay with vertical paging
        if let clip = selectedClip {
            ClipPagerView(
                clips: viewState.filteredClips,
                initialClip: clip,
                selectedClip: $selectedClip,
                viewState: viewState,
                namespace: namespace
            )
            .transition(.asymmetric(insertion: .identity, removal: .opacity))
            .zIndex(100)
        }
        
        // Trim view
        trimViewOverlay
        
        // Search overlay
        if showSearch {
            searchOverlay
                .transition(.opacity)
                .zIndex(50)
        }
        
        // Record confirmation overlay
        if showRecordConfirmation {
            ClipConfirmation()
                .transition(.scale.combined(with: .opacity))
                .zIndex(200)
        }
        
        // Toast messages
        toastMessages
    }

    private var processingIndicator: some View {
        VStack {
            if isSavingClip || captureCoordinator.isExporting {
                HStack(spacing: 10) {
                    ProgressView(value: captureCoordinator.exportProgress)
                        .progressViewStyle(.linear)
                        .frame(width: 80)
                    
                    Text("Processing clip")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                    
                    if captureCoordinator.exportTotalFrames > 0 {
                        Text("\(Int(captureCoordinator.exportProgress * 100))%")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(AppColors.warmSurface)
                .glassEffect(in: .rect(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(AppColors.timelineLine.opacity(0.35), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.08), radius: 10, y: 6)
                .transition(.move(edge: .top).combined(with: .opacity))
                .padding(.top, 12)
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .zIndex(250)
        .animation(.easeInOut(duration: 0.2), value: isSavingClip || captureCoordinator.isExporting)
    }
    
    @ViewBuilder
    private var toastMessages: some View {
        // No glasses connected message
        if showNoGlassesMessage {
            toastView(icon: "eyeglasses", text: "Connect your Meta glasses to record", color: .black.opacity(0.8))
        }
        
        // Buffer too short message
        if showBufferTooShortMessage {
            toastView(icon: "clock", text: "Recording... try again in a second", color: .black.opacity(0.8))
        }
        
        // No video frames message
        if showNoVideoFramesMessage {
            toastView(icon: "video.slash", text: "Waiting for video from glasses...", color: .black.opacity(0.8))
        }
        
        // Stream error message
        if showStreamErrorMessage {
            toastView(icon: "exclamationmark.triangle", text: streamErrorText.isEmpty ? "Failed to start video stream" : streamErrorText, color: .red.opacity(0.8))
        }
        
        // Photo save error message
        if showPhotoSaveError {
            toastView(icon: "photo.badge.exclamationmark", text: photoSaveErrorText.isEmpty ? "Failed to save to Photos" : photoSaveErrorText, color: .red.opacity(0.8))
        }
        
        // Export error message
        if showExportErrorMessage {
            toastView(icon: "xmark.circle", text: exportErrorText.isEmpty ? "Export failed" : exportErrorText, color: .red.opacity(0.8))
        }
    }
    
    private func toastView(icon: String?, text: String, color: Color) -> some View {
        VStack {
            Spacer()
            VStack(spacing: 8) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .medium))
                }
                Text(text)
                    .font(.system(size: 14, weight: .medium))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.bottom, 120)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
    
    // MARK: - Capture Coordinator Setup
    
    private func setupCaptureCoordinator() async {
        // Request Photo Library permission for saving clips
        let photoManager = PhotoManager()
        await photoManager.requestAuthorization()
        
        // Set up callback when a clip is exported
        captureCoordinator.onClipExported = { [self] url, transcript in
            Task { @MainActor in
                // Show trim view for editing (can skip to save directly)
                captureClip(exportedURL: url, transcript: transcript, showTrim: true)
            }
        }
        
        captureCoordinator.onExportError = { error in
            print("❌ Clip export failed: \(error.localizedDescription)")
        }
        
        // Set up Memory Assistant callback for "Hey Clip" questions
        captureCoordinator.onQuestionAsked = { [self] question in
            Task { @MainActor in
                await handleMemoryQuestion(question)
            }
        }
        
        // Set up Memory Assistant completion callback
        memoryAssistant.onComplete = { [self] in
            captureCoordinator.questionProcessingComplete()
        }
        
        // Connect to Meta glasses
        do {
            try await glassesManager.connect()
            print("🕶️ Connected to glasses")
        } catch {
            print("⚠️ Failed to connect to glasses: \(error.localizedDescription)")
            // Continue anyway - audio capture still works via Bluetooth
        }
        
        // Start the capture coordinator (video + audio + wake word detection)
        do {
            try await captureCoordinator.startCapture()
            print("🎬 Capture coordinator started")
        } catch {
            print("⚠️ Failed to start capture: \(error.localizedDescription)")
        }
    }
    
    private func captureClip(exportedURL: URL? = nil, transcript: String = "", showTrim: Bool = false) {
        HapticManager.playSuccess()
        
        // Handle exported clip
        if let url = exportedURL {
            if showTrim {
                // Show trim view for editing
                clipToTrim = url
                trimTranscript = transcript
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    showTrimView = true
                }
            } else {
                // Direct save without trimming
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    showRecordConfirmation = true
                }
                
                addClipToTimeline(exportedURL: url, transcript: transcript)
                Task {
                    await handleExportedClip(url: url, transcript: transcript)
                }
                
                // Auto-dismiss confirmation
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation(.spring(response: 0.3)) {
                        showRecordConfirmation = false
                    }
                }
            }
        }
        
        // Send transcript to backend
        if !transcript.isEmpty {
            Task {
                await sendClipToBackend(transcript: transcript)
            }
        }
    }
    
    private func handleTrimComplete(sourceURL: URL, startTime: CMTime, endTime: CMTime, transcript: String) async {
        do {
            let exporter = ClipExporter()
            let trimmedURL = try await exporter.trimClip(
                sourceURL: sourceURL,
                startTime: startTime,
                endTime: endTime
            )
            
            // Calculate trimmed duration
            let trimmedDuration = endTime.seconds - startTime.seconds
            
            await MainActor.run {
                HapticManager.playSuccess()
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    showRecordConfirmation = true
                }
                
                addClipToTimeline(exportedURL: trimmedURL, transcript: transcript, duration: trimmedDuration)
            }
            
            await handleExportedClip(url: trimmedURL, transcript: transcript)
            
            // Clean up original file
            try? FileManager.default.removeItem(at: sourceURL)
            
            await MainActor.run {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation(.spring(response: 0.3)) {
                        showRecordConfirmation = false
                    }
                }
            }
        } catch {
            print("❌ Trim failed: \(error.localizedDescription)")
            // Fall back to saving untrimmed
            await handleExportedClip(url: sourceURL, transcript: transcript)
        }
    }
    
    private func handleExportedClip(url: URL, transcript: String = "") async {
        print("📼 Clip exported to: \(url.path)")
        
        // Log file size
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           let fileSize = attributes[.size] as? Int64 {
            let sizeInMB = Double(fileSize) / (1024 * 1024)
            print("📼 Clip size: \(String(format: "%.2f", sizeInMB)) MB")
        }
        
        // Persist master file in app sandbox for high-quality playback
        let localURL = persistClipToDocuments(from: url)
        if let localURL {
            print("✅ Saved master to local storage: \(localURL.lastPathComponent)")
        } else {
            print("⚠️ Failed to save master locally, proceeding with temp file")
        }
        
        // Save to Photo Library
        do {
            let photoManager = PhotoManager()
            let localIdentifier = try await photoManager.saveVideo(from: localURL ?? url)
            print("✅ Saved to Photo Library: \(localIdentifier)")
            
            // Update the clip's localIdentifier so it can load the thumbnail
            if let index = viewState.clips.firstIndex(where: { $0.localIdentifier == url.lastPathComponent }) {
                var updatedClip = viewState.clips[index]
                
                // Generate a better title from transcript if possible
                let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                let generatedTitle = trimmedTranscript.isEmpty || trimmedTranscript == "[Recording]"
                    ? nil
                    : await TitleGenerator.shared.generateTitle(from: trimmedTranscript)
                let finalTitle = generatedTitle?.isEmpty == false ? generatedTitle! : updatedClip.title
                
                // Generate captions from transcript if available
                var captionSegments: [CaptionSegment]? = nil
                if !transcript.isEmpty && transcript != "[Recording]" {
                    captionSegments = CaptionManager.shared.generateSegments(
                        from: transcript,
                        duration: updatedClip.duration
                    )
                    print("📝 Generated \(captionSegments?.count ?? 0) caption segments")
                }
                
                updatedClip = ClipMetadata(
                    id: updatedClip.id,
                    localIdentifier: localIdentifier,
                    title: finalTitle,
                    transcript: transcript.isEmpty ? updatedClip.transcript : transcript,
                    topics: updatedClip.topics,
                    capturedAt: updatedClip.capturedAt,
                    duration: updatedClip.duration,
                    isStarred: updatedClip.isStarred,
                    context: updatedClip.context,
                    audioNarrationURL: updatedClip.audioNarrationURL,
                    clipState: updatedClip.clipState,
                    thumbnailBase64: updatedClip.thumbnailBase64,
                    isPortrait: updatedClip.isPortrait,
                    localFileURL: localURL?.path ?? updatedClip.localFileURL,
                    captionSegments: captionSegments,
                    showCaptions: true,
                    captionStyle: updatedClip.captionStyle
                )
                viewState.clips[index] = updatedClip
                
                // Upload to backend asynchronously
                let uploadURL = localURL ?? url
                if FileManager.default.fileExists(atPath: uploadURL.path) {
                    Task.detached(priority: .background) {
                        do {
                            try await APIService.shared.uploadClip(
                                videoURL: uploadURL,
                                videoId: localIdentifier,
                                title: finalTitle,
                                timestamp: updatedClip.capturedAt
                            )
                            print("✅ Uploaded clip to backend: \(localIdentifier)")
                        } catch {
                            print("❌ Upload failed: \(error.localizedDescription)")
                        }
                    }
                } else {
                    print("⚠️ Upload skipped: missing file at \(uploadURL.path)")
                }
            }
            
            // Clean up temp file if we copied to local storage
            if let localURL, localURL != url {
                try? FileManager.default.removeItem(at: url)
            }
        } catch {
            print("❌ Failed to save to Photo Library: \(error.localizedDescription)")
            
            // Show error toast
            HapticManager.playError()
            photoSaveErrorText = error.localizedDescription
            withAnimation {
                showPhotoSaveError = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                withAnimation {
                    showPhotoSaveError = false
                }
            }
            
            // Even if Photos save fails, keep local master for playback
            if let localURL,
               let index = viewState.clips.firstIndex(where: { $0.localIdentifier == url.lastPathComponent }) {
                let updatedClip = viewState.clips[index]
                viewState.clips[index] = ClipMetadata(
                    id: updatedClip.id,
                    localIdentifier: updatedClip.localIdentifier,
                    title: updatedClip.title,
                    transcript: updatedClip.transcript,
                    topics: updatedClip.topics,
                    capturedAt: updatedClip.capturedAt,
                    duration: updatedClip.duration,
                    isStarred: updatedClip.isStarred,
                    context: updatedClip.context,
                    audioNarrationURL: updatedClip.audioNarrationURL,
                    clipState: updatedClip.clipState,
                    thumbnailBase64: updatedClip.thumbnailBase64,
                    isPortrait: updatedClip.isPortrait,
                    localFileURL: localURL.path,
                    captionSegments: updatedClip.captionSegments,
                    showCaptions: updatedClip.showCaptions,
                    captionStyle: updatedClip.captionStyle
                )
                
                // Upload to backend asynchronously if we still have a local file
                if FileManager.default.fileExists(atPath: localURL.path) {
                    Task.detached(priority: .background) {
                        do {
                            try await APIService.shared.uploadClip(
                                videoURL: localURL,
                                videoId: updatedClip.localIdentifier,
                                title: updatedClip.title,
                                timestamp: updatedClip.capturedAt
                            )
                            print("✅ Uploaded clip to backend (Photos failed): \(updatedClip.localIdentifier)")
                        } catch {
                            print("❌ Upload failed (Photos failed): \(error.localizedDescription)")
                        }
                    }
                }
            }
        }
    }
    
    private func persistClipToDocuments(from url: URL) -> URL? {
        do {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            guard let docs else { return nil }
            
            let clipsDir = docs.appendingPathComponent("Clips", isDirectory: true)
            try FileManager.default.createDirectory(at: clipsDir, withIntermediateDirectories: true)
            
            let ext = url.pathExtension.isEmpty ? "mov" : url.pathExtension
            let destURL = clipsDir.appendingPathComponent("clip_\(UUID().uuidString).\(ext)")
            
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            
            try FileManager.default.copyItem(at: url, to: destURL)
            return destURL
        } catch {
            print("⚠️ Failed to persist clip locally: \(error.localizedDescription)")
            return nil
        }
    }
    
    private func sendClipToBackend(transcript: String) async {
        // TODO: Implement backend API call
        print("📝 Clip triggered with transcript: \(transcript)")
    }
    
    // MARK: - Memory Assistant
    
    private func handleMemoryQuestion(_ question: String) async {
        HapticManager.playLight()
        print("🧠 Memory question asked: \"\(question)\"")
        
        // Use all clips for context
        await memoryAssistant.askQuestion(question, clips: viewState.clips)
    }
    
    private func addClipToTimeline(exportedURL: URL, transcript: String = "", duration: TimeInterval = 30.0) {
        // Generate captions from transcript if available
        var captionSegments: [CaptionSegment]? = nil
        let finalTranscript = transcript.isEmpty ? "[Recording]" : transcript
        
        if !transcript.isEmpty {
            captionSegments = CaptionManager.shared.generateSegments(
                from: transcript,
                duration: duration
            )
        }
        
        let newClip = ClipMetadata(
            id: UUID(),
            localIdentifier: exportedURL.lastPathComponent,
            title: "Clip \(Date().formatted(date: .omitted, time: .shortened))",
            transcript: finalTranscript,
            topics: ["Clip"],
            capturedAt: Date(),
            duration: duration,
            localFileURL: exportedURL.path,
            captionSegments: captionSegments,
            showCaptions: captionSegments != nil
        )
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            viewState.clips.insert(newClip, at: 0)
        }
    }
    
    // MARK: - Header Bar
    
    private var headerBar: some View {
        HStack(alignment: .center, spacing: 12) {
            // Wordmark - clean, no pill
            Text("clip")
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.6)
                .foregroundStyle(AppColors.textPrimary)
            
            // Compact glasses status indicator
            compactGlassesStatus
            
            Spacer()
            
            // Search button
            Button {
                HapticManager.playLight()
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    showSearch = true
                }
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .frame(width: 40, height: 40)
                    .background {
                        Circle()
                            .fill(.white.opacity(0.9))
                            .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
                    }
            }
            .accessibilityLabel("Search clips")
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }
    
    // MARK: - Compact Glasses Status
    
    private var compactGlassesStatus: some View {
        Button {
            HapticManager.playLight()
            Task {
                do {
                    try await ensureVideoStreamReady()

                    // Toggle preview visibility
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showGlassesPreview.toggle()
                        print("👁️ [Preview] Preview toggled to: \(showGlassesPreview)")
                    }
                } catch {
                    print("❌ [Preview] Glasses action failed: \(error)")
                    HapticManager.playError()
                    
                    // Show error message with helpful hint
                    let errorMsg = error.localizedDescription
                    var userMessage = "Failed to start preview: \(errorMsg)"
                    if errorMsg.contains("Internal SDK error") {
                        userMessage = "Stream error - try tapping glasses temple to wake them, then retry"
                    } else if errorMsg.contains("permission denied") || errorMsg.contains("Permission") {
                        userMessage = "Camera permission needed - tap glasses temple when prompted, or grant in Meta AI app"
                    }
                    
                    streamErrorText = userMessage
                    withAnimation { showStreamErrorMessage = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                        withAnimation { showStreamErrorMessage = false }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                // Glasses icon
                Image(systemName: "eyeglasses")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(glassesStatusColor)
                
                // Status text
                Text(glassesStatusText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
                
                // Animated dot for live status
                if glassesManager.connectionState == .connected && captureCoordinator.isCapturing {
                    Circle()
                        .fill(AppColors.connected)
                        .frame(width: 6, height: 6)
                        .modifier(PulseAnimation())
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                Capsule()
                    .fill(glassesStatusColor.opacity(0.1))
                    .overlay {
                        Capsule()
                            .stroke(glassesStatusColor.opacity(0.2), lineWidth: 1)
                    }
            }
        }
        .buttonStyle(.plain)
    }
    
    private var glassesStatusColor: Color {
        switch glassesManager.connectionState {
        case .connected:
            return captureCoordinator.isCapturing ? AppColors.connected : AppColors.accent
        case .connecting:
            return .orange
        case .disconnected, .error:
            return AppColors.textSecondary
        }
    }
    
    private var glassesStatusText: String {
        switch glassesManager.connectionState {
        case .connected:
            return captureCoordinator.isCapturing ? "Live" : "Connected"
        case .connecting:
            return "Syncing..."
        case .disconnected:
            return "Connect"
        case .error:
            return "Retry"
        }
    }

    private func ensureVideoStreamReady() async throws {
        // If not connected, connect first
        if glassesManager.connectionState != .connected {
            print("🔌 [Stream] Connecting to glasses...")
            try await glassesManager.connect()
            print("✅ [Stream] Connected successfully")
        }

        // If already streaming, nothing to do
        guard !glassesManager.isVideoStreaming else { return }

        print("📹 [Stream] Starting video stream...")
        print("💡 [Stream] Tip: Tap glasses temple to wake camera before starting")

        // Wait a moment to ensure glasses are ready
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

        var lastError: Error?
        for attempt in 1...3 {
            do {
                try await glassesManager.startVideoStream()
                print("✅ [Stream] Video stream started on attempt \(attempt)")
                // Wait a moment for first frame
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                return
            } catch {
                lastError = error
                let errorStr = error.localizedDescription
                print("⚠️ [Stream] Stream start attempt \(attempt) failed: \(errorStr)")

                // Handle permission denied - try reauthorizing
                if errorStr.contains("permission denied") || errorStr.contains("Permission") {
                    print("🔐 [Stream] Permission denied - trying to reauthorize...")
                    let authResult = await glassesManager.reauthorize()
                    print("🔐 [Stream] Reauthorize result: \(authResult)")

                    // Wait a moment for permission to be granted
                    try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

                    if attempt < 3 {
                        continue
                    }
                } else if errorStr.contains("Internal SDK error") && attempt < 3 {
                    // Internal errors often mean the glasses camera is asleep
                    let delay = UInt64(attempt * 3_000_000_000) // 3s, 6s delays
                    print("🔄 [Stream] Internal error - waiting \(attempt * 3)s then retrying...")
                    print("💡 [Stream] IMPORTANT: Tap glasses temple NOW to wake the camera!")
                    try? await Task.sleep(nanoseconds: delay)
                    continue
                }
            }
        }

        throw lastError ?? GlassesError.streamFailed("Failed to start video stream")
    }
    
    // MARK: - Record Button
    
    private var canRecord: Bool {
        glassesManager.connectionState.isConnected
    }
    
    private var recordButton: some View {
        Button {
            if canRecord {
                triggerRecording()
            } else {
                // Show toast prompting user to connect glasses
                HapticManager.playLight()
                withAnimation {
                    showNoGlassesMessage = true
                }
                // Auto-dismiss after 2.5 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    withAnimation {
                        showNoGlassesMessage = false
                    }
                }
            }
        } label: {
            ZStack {
                // Completion burst rings (behind everything)
                if showCompletionBurst {
                    // Primary burst ring
                    Circle()
                        .stroke(AppColors.accent, lineWidth: 3)
                        .frame(width: 80, height: 80)
                        .scaleEffect(completionRingScale)
                        .opacity(completionOpacity)
                    
                    // Secondary burst ring (slightly delayed feel via different scale)
                    Circle()
                        .stroke(AppColors.accent.opacity(0.6), lineWidth: 2)
                        .frame(width: 80, height: 80)
                        .scaleEffect(completionRingScale2)
                        .opacity(completionOpacity * 0.7)
                }
                
                if isRecording {
                    Circle()
                        .stroke(AppColors.accent.opacity(0.2), lineWidth: 1)
                        .frame(width: 88, height: 88)
                        .scaleEffect(recordPulse ? 1.05 : 0.9)
                        .opacity(recordPulse ? 0.1 : 0.5)
                }

                Circle()
                    .trim(from: 0, to: recordProgress)
                    .stroke(
                        (canRecord ? AppColors.accent : Color.gray).opacity(0.6),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 80, height: 80)

                // Glass halo
                Circle()
                    .fill(.clear)
                    .frame(width: 72, height: 72)
                    .glassEffect(.regular.interactive(), in: .circle)

                Circle()
                    .stroke((canRecord ? AppColors.accent : Color.gray).opacity(0.25), lineWidth: 1)
                    .frame(width: 72, height: 72)

                // Accent core
                Circle()
                    .fill(canRecord ? AppGradients.accent : AppGradients.disabled)
                    .frame(width: 56, height: 56)
                    .scaleEffect(buttonBounceScale)

                if isRecording {
                    Image(systemName: "checkmark")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                        .scaleEffect(buttonBounceScale)
                        .transition(.scale.combined(with: .opacity))
                } else if isSavingClip {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.9)
                } else {
                    Circle()
                        .fill(.white)
                        .frame(width: 22, height: 22)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            // Fixed frame prevents layout shift when pulse ring appears/disappears
            .frame(width: 96, height: 96)
        }
        .buttonStyle(RecordButtonStyle())
        .shadow(color: (canRecord ? AppColors.accent : Color.gray).opacity(showCompletionBurst ? 0.5 : 0.25), radius: showCompletionBurst ? 24 : 16, y: 10)
        .opacity(canRecord ? 1.0 : 0.6)
        .onLongPressGesture(minimumDuration: 0, pressing: { isPressing in
            if isPressing && canRecord {
                HapticManager.playLight()
            }
        }, perform: {})
        .accessibilityLabel(canRecord ? "Record clip" : "Record clip (glasses not connected)")
    }
    
    private func triggerRecording() {
        // Require glasses connection
        guard canRecord else { return }
        
        // Prevent double-tap
        guard !isRecording else { return }
        
        // Prevent double-tap while saving
        guard !isSavingClip else { return }

        HapticManager.playLight()
        
        // Set recording state immediately
        isRecording = true
        recordProgress = 0
        recordPulse = false
        
        // Reset burst state
        showCompletionBurst = false
        completionRingScale = 1.0
        completionRingScale2 = 1.0
        completionOpacity = 0
        buttonBounceScale = 1.0

        // Animate progress ring
        withAnimation(.linear(duration: 3.0)) {
            recordProgress = 1
        }

        // Pulse animation
        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
            recordPulse = true
        }
        
        // Reset the UI ring/checkmark after 3s regardless of export time
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            // Trigger completion burst animation
            showCompletionBurst = true
            completionOpacity = 1.0
            
            // Primary burst ring - expands outward
            withAnimation(.easeOut(duration: 0.5)) {
                completionRingScale = 2.2
                completionOpacity = 0
            }
            
            // Secondary burst ring - slightly delayed, different timing
            withAnimation(.easeOut(duration: 0.6).delay(0.05)) {
                completionRingScale2 = 2.0
            }
            
            // Button bounce effect
            withAnimation(.spring(response: 0.2, dampingFraction: 0.4)) {
                buttonBounceScale = 1.15
            }
            
            // Bounce back
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
                    buttonBounceScale = 1.0
                }
            }
            
            // Success haptic
            HapticManager.playSuccess()
            
            // Reset recording state
            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                isRecording = false
            }
            recordPulse = false
            recordProgress = 0
            
            // Clean up burst state after animation completes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                showCompletionBurst = false
                completionRingScale = 1.0
                completionRingScale2 = 1.0
            }
        }

        // Export the last 30 seconds from the rolling buffer
        Task {
            await MainActor.run {
                isSavingClip = true
            }
            
            do {
                if !captureCoordinator.isCapturing {
                    try await captureCoordinator.startCapture()
                }
                
                // Ensure video stream is running before export
                try await ensureVideoStreamReady()

                let url = try await captureCoordinator.triggerClipExport()
                let transcript = captureCoordinator.getRecentTranscript()
                await MainActor.run {
                    captureClip(exportedURL: url, transcript: transcript, showTrim: true)
                }
                print("✅ Clip exported: \(url.lastPathComponent)")
            } catch let error as ClipExportError {
                print("❌ Export failed (ClipExportError): \(error.localizedDescription)")
                
                // Show user-friendly error message
                await MainActor.run {
                    switch error {
                    case .bufferTooShort:
                        HapticManager.playError()
                        withAnimation {
                            showBufferTooShortMessage = true
                        }
                        // Auto-dismiss after 2 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            withAnimation {
                                showBufferTooShortMessage = false
                            }
                        }
                    case .noVideoFrames:
                        HapticManager.playError()
                        withAnimation {
                            showNoVideoFramesMessage = true
                        }
                        // Auto-dismiss after 3 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                            withAnimation {
                                showNoVideoFramesMessage = false
                            }
                        }
                    default:
                        // Handle other ClipExportError cases
                        HapticManager.playError()
                        exportErrorText = error.localizedDescription
                        withAnimation {
                            showExportErrorMessage = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                            withAnimation {
                                showExportErrorMessage = false
                            }
                        }
                    }
                }
            } catch let error as ClipExporter.ExportError {
                // Handle exporter-specific errors (timeout, writer failure, etc.)
                print("❌ Export failed (ExportError): \(error.localizedDescription)")
                await MainActor.run {
                    HapticManager.playError()
                    exportErrorText = error.localizedDescription
                    withAnimation {
                        showExportErrorMessage = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        withAnimation {
                            showExportErrorMessage = false
                        }
                    }
                }
            } catch {
                // Generic fallback for any other errors
                print("❌ Export failed (generic): \(error.localizedDescription)")
                await MainActor.run {
                    HapticManager.playError()
                    exportErrorText = "Export failed: \(error.localizedDescription)"
                    withAnimation {
                        showExportErrorMessage = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        withAnimation {
                            showExportErrorMessage = false
                        }
                    }
                }
            }
            
            // Always reset saving state
            await MainActor.run {
                isSavingClip = false
            }
        }
    }
    
    // MARK: - Search Overlay
    
    private var searchSuggestions: [String] {
        ["that funny moment", "when we talked about AI", "coffee meetup", "the demo yesterday", "travel plans"]
    }
    
    private var searchOverlay: some View {
        ZStack {
            // Soft dimmed background
            AppColors.warmBackground
                .opacity(0.96)
                .ignoresSafeArea()
                .overlay {
                    Color.black.opacity(0.08).ignoresSafeArea()
                }
                .onTapGesture {
                    dismissSearch()
                }
            
            VStack(spacing: 0) {
                // Search field
                HStack(spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(AppColors.textSecondary)
                        
                        TextField("Search your moments...", text: $viewState.searchText)
                            .font(.system(size: 16))
                            .foregroundStyle(AppColors.textPrimary)
                            .autocorrectionDisabled()
                        
                        if !viewState.searchText.isEmpty {
                            Button {
                                viewState.searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(AppColors.textSecondary.opacity(0.7))
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(AppColors.timelineLine.opacity(0.4), lineWidth: 1)
                    }
                    
                    // Close button
                    Button {
                        dismissSearch()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppColors.textSecondary)
                            .frame(width: 36, height: 36)
                            .glassEffect(.regular.interactive(), in: .circle)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 60)
                
                Text("Search is semantic. Try describing the moment.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(.top, 10)
                
                // Suggestions with glass pills
                if viewState.searchText.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("TRY SEARCHING")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(AppColors.textSecondary)
                            .padding(.top, 28)
                        
                        FlowLayout(spacing: 10) {
                            ForEach(Array(searchSuggestions.enumerated()), id: \.element) { index, suggestion in
                                Button {
                                    viewState.searchText = suggestion
                                } label: {
                                    Text(suggestion)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(AppColors.textPrimary)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 10)
                                        .glassEffect(.regular.interactive(), in: .capsule)
                                        .opacity(showSearchSuggestions ? 1 : 0)
                                        .offset(y: showSearchSuggestions ? 0 : 6)
                                        .animation(
                                            .spring(response: 0.4, dampingFraction: 0.85)
                                                .delay(Double(index) * 0.03),
                                            value: showSearchSuggestions
                                        )
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
                
                Spacer()
            }
        }
    }
    
    private func dismissSearch() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            showSearch = false
        }
    }
}

// MARK: - Glasses Status Card

struct GlassesStatusCard: View {
    var isListening: Bool = false
    var connectionState: GlassesConnectionState = .connected
    var deviceName: String = "Ray-Ban Meta"
    var isMockMode: Bool = false
    var debugStatus: String = ""
    var isPreviewVisible: Bool = false
    var onRetryTap: (() -> Void)? = nil
    var onCardTap: (() -> Void)? = nil
    
    private var statusColor: Color {
        switch connectionState {
        case .connected: return AppColors.connected
        case .connecting: return .orange
        case .disconnected: return .gray
        case .error: return .red
        }
    }
    
    private var statusText: String {
        if isMockMode && connectionState.isConnected {
            return "Mock Mode"
        }
        return connectionState.statusText
    }
    
    var body: some View {
        HStack(spacing: 14) {
            // Left: Stylized glasses icon
            StylizedGlassesIcon()
                .padding(.leading, 4)

            // Middle: Status info
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("RAY-BAN META")
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(0.8)
                    
                    if isMockMode {
                        Text("MOCK")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                    }
                }

                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)
                        .shadow(color: statusColor.opacity(0.6), radius: 3)

                    Text(statusText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                
                // Debug status
                if !debugStatus.isEmpty {
                    Text(debugStatus)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary.opacity(0.7))
                }
            }

            Spacer()
            
            // Listening indicator (pulsing mic)
            if isListening {
                ListeningIndicator()
            }

            // Right: Preview pill when connected, Retry button when not
            if connectionState.isConnected {
                // Preview button
                Button(action: { onCardTap?() }) {
                    HStack(spacing: 4) {
                        Image(systemName: isPreviewVisible ? "eye.fill" : "eye")
                            .font(.system(size: 12, weight: .medium))
                        Text("Preview")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(isPreviewVisible ? .white : AppColors.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(isPreviewVisible ? AppColors.accent : AppColors.accent.opacity(0.15))
                    .clipShape(Capsule())
                }
            } else {
                // Retry button when not connected
                Button(action: { onRetryTap?() }) {
                    Text("Retry")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.blue.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .glassEffect(in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isPreviewVisible ? AppColors.accent.opacity(0.6) : AppColors.timelineLine.opacity(0.5), lineWidth: isPreviewVisible ? 2 : 1)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onCardTap?()
        }
    }
}

// MARK: - Listening Indicator

struct ListeningIndicator: View {
    @State private var isPulsing = false
    
    var body: some View {
        ZStack {
            // Outer pulse ring
            Circle()
                .stroke(AppColors.accent.opacity(0.3), lineWidth: 2)
                .frame(width: 32, height: 32)
                .scaleEffect(isPulsing ? 1.3 : 1.0)
                .opacity(isPulsing ? 0 : 0.6)
            
            // Inner circle
            Circle()
                .fill(AppColors.accent.opacity(0.15))
                .frame(width: 28, height: 28)
            
            // Mic icon
            Image(systemName: "mic.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColors.accent)
        }
        .onAppear {
            withAnimation(
                .easeInOut(duration: 1.2)
                .repeatForever(autoreverses: false)
            ) {
                isPulsing = true
            }
        }
    }
}

// MARK: - Stylized Glasses Icon

struct StylizedGlassesIcon: View {
    var body: some View {
        HStack(spacing: 3) {
            // Left lens
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(.systemGray4), Color(.systemGray5)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 22, height: 14)
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color(.systemGray3), lineWidth: 1.5)
                }

            // Bridge
            Rectangle()
                .fill(Color(.systemGray3))
                .frame(width: 6, height: 2)

            // Right lens
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(.systemGray4), Color(.systemGray5)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 22, height: 14)
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color(.systemGray3), lineWidth: 1.5)
                }
        }
    }
}

// MARK: - Record Button Style

struct RecordButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Clip Confirmation

struct ClipConfirmation: View {
    @State private var checkScale: CGFloat = 0
    @State private var ringScale: CGFloat = 0.8
    @State private var ringOpacity: Double = 0
    @State private var checkProgress: CGFloat = 0

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                // Animated ring
                Circle()
                    .stroke(AppColors.accent.opacity(0.4), lineWidth: 2)
                    .frame(width: 88, height: 88)
                    .scaleEffect(ringScale)
                    .opacity(ringOpacity)
                
                // Warm surface circle background
                Circle()
                    .fill(AppColors.warmBackground)
                    .frame(width: 76, height: 76)
                    .overlay {
                        Circle()
                            .stroke(AppColors.timelineLine.opacity(0.4), lineWidth: 1)
                    }

                // Checkmark
                CheckmarkShape()
                    .trim(from: 0, to: checkProgress)
                    .stroke(AppColors.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    .frame(width: 30, height: 22)
                    .scaleEffect(checkScale)
            }

            VStack(spacing: 4) {
                Text("Clipped!")
                    .font(AppTypography.cardTitle)
                    .foregroundStyle(AppColors.textPrimary)

                Text("Last 30 seconds saved")
                    .font(AppTypography.metadata)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .padding(44)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppColors.warmSurface)
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(AppColors.timelineLine.opacity(0.4), lineWidth: 1)
                }
        }
        .shadow(color: AppColors.cardShadow, radius: 14, y: 8)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                ringScale = 1.1
                ringOpacity = 1
            }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6).delay(0.1)) {
                checkScale = 1
            }
            withAnimation(.easeOut(duration: 0.35).delay(0.12)) {
                checkProgress = 1
            }
        }
    }
}

struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let start = CGPoint(x: rect.minX, y: rect.midY)
        let mid = CGPoint(x: rect.midX * 0.75, y: rect.maxY)
        let end = CGPoint(x: rect.maxX, y: rect.minY)
        path.move(to: start)
        path.addLine(to: mid)
        path.addLine(to: end)
        return path
    }
}

// MARK: - Memory Assistant Indicator

struct MemoryAssistantIndicator: View {
    let state: MemoryAssistantState
    var question: String?
    var response: String?
    
    @State private var pulseScale: CGFloat = 1.0
    
    var body: some View {
        VStack {
            VStack(spacing: 12) {
                // Status icon with animation
                ZStack {
                    // Pulsing background
                    Circle()
                        .fill(stateColor.opacity(0.2))
                        .frame(width: 56, height: 56)
                        .scaleEffect(pulseScale)
                    
                    // Glass circle
                    Circle()
                        .fill(.clear)
                        .frame(width: 48, height: 48)
                        .glassEffect(in: .circle)
                    
                    // Icon
                    stateIcon
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(stateColor)
                }
                
                // Status text
                Text(state.displayText)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                
                // Question (if available)
                if let question = question, !question.isEmpty {
                    Text("\"\(question)\"")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 8)
                }
                
                // Response (if speaking)
                if state == .speaking, let response = response, !response.isEmpty {
                    Text(response)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                        .padding(.horizontal, 12)
                        .padding(.top, 4)
                }
            }
            .padding(.vertical, 20)
            .padding(.horizontal, 24)
            .frame(maxWidth: 300)
            .glassEffect(in: .rect(cornerRadius: 24))
            .shadow(color: .black.opacity(0.15), radius: 20, y: 10)
            .padding(.top, 100)
            
            Spacer()
        }
        .onAppear {
            startPulseAnimation()
        }
    }
    
    @ViewBuilder
    private var stateIcon: some View {
        switch state {
        case .idle:
            Image(systemName: "brain")
        case .listening:
            Image(systemName: "ear")
        case .thinking:
            ProgressView()
                .tint(stateColor)
        case .speaking:
            Image(systemName: "speaker.wave.2.fill")
        case .error:
            Image(systemName: "exclamationmark.triangle")
        }
    }
    
    private var stateColor: Color {
        switch state {
        case .idle: return .gray
        case .listening: return .blue
        case .thinking: return .orange
        case .speaking: return AppColors.accent
        case .error: return .red
        }
    }
    
    private func startPulseAnimation() {
        withAnimation(
            .easeInOut(duration: 1.2)
            .repeatForever(autoreverses: true)
        ) {
            pulseScale = 1.15
        }
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                      y: bounds.minY + result.positions[index].y),
                         proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }
                
                positions.append(CGPoint(x: x, y: y))
                rowHeight = max(rowHeight, size.height)
                x += size.width + spacing
                
                self.size.width = max(self.size.width, x)
            }
            
            self.size.height = y + rowHeight
        }
    }
}

// MARK: - Pulse Animation Modifier

struct PulseAnimation: ViewModifier {
    @State private var isPulsing = false
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing ? 1.3 : 1.0)
            .opacity(isPulsing ? 0.6 : 1.0)
            .animation(
                .easeInOut(duration: 0.8)
                .repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear {
                isPulsing = true
            }
    }
}

#Preview {
    RootView()
}
