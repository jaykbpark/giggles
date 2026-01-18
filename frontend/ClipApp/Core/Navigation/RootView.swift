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
    @State private var cancellables = Set<AnyCancellable>()
    @State private var showBufferTooShortMessage = false
    @State private var isSavingClip = false
    @State private var showGlassesPreview = false
    @State private var showNoVideoFramesMessage = false
    @State private var showStreamErrorMessage = false
    @State private var streamErrorText = ""
    @State private var showPhotoSaveError = false
    @State private var photoSaveErrorText = ""
    @State private var showPhotoSaveSuccess = false
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
            
            // Tab content
            if selectedTab == .clips {
                clipsTabContent
            } else {
                askTabContent
            }
            
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

                GlassesStatusCard(
                    isListening: captureCoordinator.isCapturing,
                    connectionState: glassesManager.connectionState,
                    deviceName: glassesManager.deviceName,
                    debugStatus: glassesManager.sdkDebugStatus,
                    isPreviewVisible: showGlassesPreview,
                    onRetryTap: {
                        Task {
                            try? await glassesManager.connect()
                        }
                    },
                    onCardTap: {
                        Task {
                            do {
                                // Start video stream if not already streaming
                                if !glassesManager.isVideoStreaming {
                                    try await glassesManager.startVideoStream()
                                }
                                
                                // Ensure capture coordinator is running to fill the buffer
                                // This is important if the initial startCapture() failed (e.g., audio issues)
                                if !captureCoordinator.isCapturing {
                                    try await captureCoordinator.startCapture()
                                }
                                
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    showGlassesPreview.toggle()
                                }
                            } catch {
                                // Show error to user
                                print("Failed to start video stream: \(error)")
                                HapticManager.playError()
                                streamErrorText = error.localizedDescription
                                withAnimation {
                                    showStreamErrorMessage = true
                                }
                                // Auto-dismiss after 3 seconds
                                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                                    withAnimation {
                                        showStreamErrorMessage = false
                                    }
                                }
                            }
                        }
                    }
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

                FilterBar(viewState: viewState)
                    .padding(.bottom, 4)

                FeedView(
                    viewState: viewState,
                    clips: viewState.filteredClips,
                    isLoading: viewState.isLoading,
                    selectedClip: $selectedClip,
                    namespace: namespace
                )
                
                // Bottom spacing for tab bar
                Spacer().frame(height: 90)
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
                            .padding(.bottom, 100) // Above tab bar
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
                    }
                    Spacer()
                }
                .transition(.opacity)
                .zIndex(10)
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
        .padding(.bottom, 90) // Space for tab bar
    }
    
    // MARK: - Bottom Tab Bar
    
    private var bottomTabBar: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Button {
                    HapticManager.playLight()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        selectedTab = tab
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 16, weight: .semibold))
                        
                        if selectedTab == tab {
                            Text(tab.rawValue)
                                .font(.system(size: 14, weight: .semibold))
                        }
                    }
                    .foregroundStyle(selectedTab == tab ? .white : AppColors.textSecondary)
                    .padding(.horizontal, selectedTab == tab ? 20 : 16)
                    .padding(.vertical, 12)
                    .background {
                        if selectedTab == tab {
                            Capsule()
                                .fill(AppColors.accent)
                        }
                    }
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedTab)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .glassEffect(in: .capsule)
        .shadow(color: .black.opacity(0.1), radius: 20, y: 10)
        .padding(.horizontal, 40)
        .padding(.bottom, 20)
    }
    
    // MARK: - Overlays Content
    
    @ViewBuilder
    private var overlaysContent: some View {
        // Live glasses preview
        glassesPreviewOverlay
        
        // Detail view overlay
        if let clip = selectedClip {
            ClipDetailView(
                clip: clip,
                namespace: namespace,
                selectedClip: $selectedClip,
                viewState: viewState
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
        
        // Memory Assistant indicator (when on ask tab)
        if memoryAssistant.state.isActive && selectedTab == .ask {
            MemoryAssistantIndicator(
                state: memoryAssistant.state,
                question: memoryAssistant.lastQuestion,
                response: memoryAssistant.lastResponse
            )
            .transition(.move(edge: .top).combined(with: .opacity))
            .zIndex(250)
        }
        
        // Toast messages
        toastMessages
    }
    
    @ViewBuilder
    private var toastMessages: some View {
        // Buffer too short message
        if showBufferTooShortMessage {
            toastView(icon: nil, text: "Buffer too short. Wait a moment...", color: .black.opacity(0.8))
        }
        
        // No video frames message
        if showNoVideoFramesMessage {
            toastView(icon: "video.slash", text: "No video feed. Tap glasses card to start.", color: .black.opacity(0.8))
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
        
        // Photo save success message
        if showPhotoSaveSuccess {
            VStack {
                Spacer()
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .medium))
                    Text("Saved to Photos")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(AppColors.connected.opacity(0.9))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.bottom, 120)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
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
        
        // Save to Photo Library
        do {
            let photoManager = PhotoManager()
            let localIdentifier = try await photoManager.saveVideo(from: url)
            print("✅ Saved to Photo Library: \(localIdentifier)")
            
            // Update the clip's localIdentifier so it can load the thumbnail
            if let index = viewState.clips.firstIndex(where: { $0.localIdentifier == url.lastPathComponent }) {
                var updatedClip = viewState.clips[index]
                
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
                    title: updatedClip.title,
                    transcript: transcript.isEmpty ? updatedClip.transcript : transcript,
                    topics: updatedClip.topics,
                    capturedAt: updatedClip.capturedAt,
                    duration: updatedClip.duration,
                    isStarred: updatedClip.isStarred,
                    captionSegments: captionSegments,
                    showCaptions: true
                )
                viewState.clips[index] = updatedClip
            }
            
            // Show success toast
            withAnimation {
                showPhotoSaveSuccess = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation {
                    showPhotoSaveSuccess = false
                }
            }
            
            // Clean up temp file
            try? FileManager.default.removeItem(at: url)
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
            captionSegments: captionSegments,
            showCaptions: captionSegments != nil
        )
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            viewState.clips.insert(newClip, at: 0)
        }
    }
    
    private func addMockClipToTimeline() {
        let newClip = ClipMetadata(
            id: UUID(),
            localIdentifier: "mock-\(UUID().uuidString)",
            title: "Mock Clip \(Date().formatted(date: .omitted, time: .shortened))",
            transcript: "[Mock recording - no video]",
            topics: ["Mock", "Debug"],
            capturedAt: Date(),
            duration: 30.0
        )
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            viewState.clips.insert(newClip, at: 0)
        }
    }
    
    // MARK: - Header Bar
    
    private var headerBar: some View {
        HStack(alignment: .center) {
            // Wordmark
            Text("clip")
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.6)
                .foregroundStyle(AppColors.textPrimary)
            
            Spacer()
            
            // Search button with glass
            Button {
                HapticManager.playLight()
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    showSearch = true
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(.clear)
                        .frame(width: 36, height: 36)
                        .glassEffect(.regular.interactive(), in: .circle)

                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
            .accessibilityLabel("Search clips")
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppColors.timelineLine.opacity(0.4))
                .frame(height: 1)
                .padding(.horizontal, 20)
        }
    }
    
    // MARK: - Record Button
    
    private var recordButton: some View {
        Button {
            triggerRecording()
        } label: {
            ZStack {
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
                        AppColors.accent.opacity(0.6),
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
                    .stroke(AppColors.accent.opacity(0.25), lineWidth: 1)
                    .frame(width: 72, height: 72)

                // Accent core
                Circle()
                    .fill(AppGradients.accent)
                    .frame(width: 56, height: 56)

                if isRecording {
                    Image(systemName: "checkmark")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
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
        .shadow(color: AppColors.accent.opacity(0.25), radius: 16, y: 10)
        .onLongPressGesture(minimumDuration: 0, pressing: { isPressing in
            if isPressing {
                HapticManager.playLight()
            }
        }, perform: {})
        .accessibilityLabel("Record clip")
    }
    
    private func triggerRecording() {
        // Prevent double-tap
        guard !isRecording else { return }
        
        // Prevent double-tap while saving
        guard !isSavingClip else { return }

        HapticManager.playLight()
        
        // Set recording state immediately
        isRecording = true
        recordProgress = 0
        recordPulse = false

        // Animate progress ring
        withAnimation(.linear(duration: 1.0)) {
            recordProgress = 1
        }

        // Pulse animation
        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
            recordPulse = true
        }
        
        // Reset the UI ring/checkmark after 1s regardless of export time
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                isRecording = false
            }
            recordPulse = false
            recordProgress = 0
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
                let url = try await captureCoordinator.triggerClipExport()
                await MainActor.run {
                    captureClip(exportedURL: url)
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
                    .glassEffect(in: .rect(cornerRadius: 18))
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
            viewState.searchText = ""
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
                
                // Glass circle background
                Circle()
                    .fill(.clear)
                    .frame(width: 76, height: 76)
                    .glassEffect(in: .circle)

                // Checkmark
                CheckmarkShape()
                    .trim(from: 0, to: checkProgress)
                    .stroke(AppColors.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    .frame(width: 30, height: 22)
                    .scaleEffect(checkScale)
            }

            VStack(spacing: 4) {
                Text("Clipped!")
                    .font(.system(size: 20, weight: .semibold))

                Text("Last 30 seconds saved")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(44)
        .glassEffect(in: .rect(cornerRadius: 32))
        .shadow(color: .black.opacity(0.2), radius: 40, y: 20)
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

#Preview {
    RootView()
}
