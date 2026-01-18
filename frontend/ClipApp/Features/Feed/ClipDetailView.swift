import SwiftUI
import AVKit
import AVFoundation
import Photos

struct ClipDetailView: View {
    let clip: ClipMetadata
    var namespace: Namespace.ID
    @Binding var selectedClip: ClipMetadata?
    @ObservedObject var viewState: GlobalViewState
    
    @State private var isPlaying = true
    @State private var showControls = true
    @State private var controlsTimer: Timer?
    
    // Audio narration state
    @State private var audioPlayer: AVPlayer?
    @State private var isPlayingAudio = false
    @State private var isGeneratingAudio = false
    @State private var audioError: String?
    
    // Share state
    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []
    
    private let photoManager = PhotoManager()

    private var currentClip: ClipMetadata {
        viewState.clips.first(where: { $0.id == clip.id }) ?? clip
    }

    var body: some View {
        ZStack {
            // Fullscreen black background
            Color.black
                .ignoresSafeArea(.all)
            
            // Video player area - fullscreen
            videoPlayerArea
                .matchedGeometryEffect(id: clip.id, in: namespace)
                .ignoresSafeArea(.all)
                .onTapGesture {
                    toggleControls()
                }
            
            // Overlay controls (fade in/out)
            if showControls {
                controlsOverlay
                    .transition(.opacity)
            }
        }
        .ignoresSafeArea(.all)
        .statusBarHidden(true)
        .onAppear {
            isPlaying = true
            startControlsTimer()
        }
        .onDisappear {
            controlsTimer?.invalidate()
            stopAudio()
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: shareItems)
        }
    }
    
    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showControls.toggle()
        }
        if showControls {
            startControlsTimer()
        }
    }
    
    private func startControlsTimer() {
        controlsTimer?.invalidate()
        controlsTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                showControls = false
            }
        }
    }

    private func close() {
        HapticManager.playLight()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            selectedClip = nil
        }
    }
    

    private var videoPlayerArea: some View {
        ZStack {
            // Dark gradient background (placeholder for actual video)
            LinearGradient(
                colors: [Color(white: 0.1), Color(white: 0.05)],
                startPoint: .top,
                endPoint: .bottom
            )
            
            // Placeholder content - replace with actual AVPlayer
            VStack(spacing: 16) {
                Image(systemName: "video.fill")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
    }
    
    private var controlsOverlay: some View {
        ZStack {
            // Gradient overlays for better control visibility
            VStack(spacing: 0) {
                // Top gradient
                LinearGradient(
                    colors: [.black.opacity(0.7), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 140)
                
                Spacer()
                
                // Bottom gradient
                LinearGradient(
                    colors: [.clear, .black.opacity(0.7)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 180)
            }
            .ignoresSafeArea()
            
            // Center play/pause button - absolutely centered
            Button {
                HapticManager.playLight()
                isPlaying.toggle()
                startControlsTimer()
            } label: {
                ZStack {
                    Circle()
                        .fill(.clear)
                        .frame(width: 80, height: 80)
                        .glassEffect(.regular.interactive(), in: .circle)
                    
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(.white)
                        .offset(x: isPlaying ? 0 : 3)
                }
            }
            .buttonStyle(PlayButtonStyle())
            .accessibilityLabel(isPlaying ? "Pause clip" : "Play clip")
            
            // Top and bottom controls
            VStack {
                // Top bar
                HStack(spacing: 10) {
                    Spacer()
                    
                    // Share button
                    Button {
                        HapticManager.playLight()
                        Task {
                            await shareClip()
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .glassEffect(.regular.interactive(), in: .circle)
                    }
                    .accessibilityLabel("Share clip")
                    
                    // Listen button (audio narration)
                    Button {
                        HapticManager.playLight()
                        Task {
                            await toggleAudioNarration()
                        }
                    } label: {
                        Group {
                            if isGeneratingAudio {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: isPlayingAudio ? "speaker.wave.2.fill" : "speaker.wave.2")
                            }
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .glassEffect(.regular.interactive(), in: .circle)
                    }
                    .accessibilityLabel(isPlayingAudio ? "Stop narration" : "Listen to narration")
                    .disabled(isGeneratingAudio)

                    Button {
                        HapticManager.playLight()
                        viewState.toggleStar(for: clip.id)
                    } label: {
                        Image(systemName: currentClip.isStarred ? "star.fill" : "star")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(currentClip.isStarred ? AppColors.accent : .white)
                            .frame(width: 40, height: 40)
                            .glassEffect(.regular.interactive(), in: .circle)
                    }
                    .accessibilityLabel(currentClip.isStarred ? "Remove star" : "Star clip")

                    // Close button
                    Button(action: close) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .glassEffect(.regular.interactive(), in: .circle)
                    }
                    .accessibilityLabel("Close clip")
                }
                .padding(.horizontal, 20)
                .padding(.top, 60)
                
                Spacer()
                
                // Bottom info
                VStack(alignment: .leading, spacing: 8) {
                    // Duration badge
                    HStack {
                        Text(currentClip.formattedDuration)
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.8))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .glassEffect(in: .capsule)
                        
                        Spacer()
                    }
                    
                    // Title
                    Text(currentClip.title)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)

                    if let state = currentClip.clipState {
                        stateRow(state)
                    }

                    if let context = currentClip.context {
                        contextRow(context)
                    }
                    
                    // Date
                    Text(currentClip.formattedDate)
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 50)
            }
        }
    }

    @ViewBuilder
    private func contextRow(_ context: ClipContext) -> some View {
        HStack(spacing: 8) {
            if let calendarTitle = context.calendarTitle {
                Label(calendarTitle, systemImage: "calendar")
            }
            if let locationName = context.locationName {
                Label(locationName, systemImage: "mappin.and.ellipse")
            }
            if let weatherSummary = context.weatherSummary {
                Label(weatherSummary, systemImage: "cloud.sun")
            }
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.white.opacity(0.7))
        .lineLimit(1)
    }

    private func stateRow(_ state: ClipState) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(stateColor(state))
                .frame(width: 6, height: 6)
            Text(state.stateSummary)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)
        }
    }

    private func stateColor(_ state: ClipState) -> Color {
        switch state.stressLevel {
        case 0..<0.34:
            return Color.green.opacity(0.9)
        case 0.34..<0.67:
            return Color.orange.opacity(0.9)
        default:
            return Color.red.opacity(0.9)
        }
    }
    
    // MARK: - Audio Narration
    
    @MainActor
    private func toggleAudioNarration() async {
        if isPlayingAudio {
            // Stop audio
            audioPlayer?.pause()
            audioPlayer = nil
            isPlayingAudio = false
            return
        }
        
        // Generate and play audio
        isGeneratingAudio = true
        audioError = nil
        
        do {
            let audioURL = try await ElevenLabsService.shared.generateNarration(
                transcript: currentClip.transcript,
                clipId: currentClip.id,
                state: currentClip.clipState
            )
            
            let player = AVPlayer(url: audioURL)
            audioPlayer = player
            
            // Play audio
            player.play()
            isPlayingAudio = true
            
            // Listen for completion
            NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player.currentItem,
                queue: .main
            ) { _ in
                isPlayingAudio = false
                audioPlayer = nil
            }
            
        } catch {
            audioError = error.localizedDescription
            print("❌ Failed to generate audio narration: \(error)")
        }
        
        isGeneratingAudio = false
    }
    
    private func stopAudio() {
        audioPlayer?.pause()
        audioPlayer = nil
        isPlayingAudio = false
    }
    
    // MARK: - Share
    
    @MainActor
    private func shareClip() async {
        var itemsToShare: [Any] = []
        
        // Try to get video from Photo Library
        if let asset = photoManager.fetchAsset(for: currentClip.localIdentifier) {
            do {
                let videoURL = try await photoManager.getVideoURL(for: asset)
                itemsToShare.append(videoURL)
            } catch {
                print("⚠️ Could not get video URL: \(error.localizedDescription)")
                // Fallback to text
            }
        }
        
        // Always include text metadata as fallback or additional context
        let shareText = """
        \(currentClip.title)
        
        \(currentClip.transcript)
        
        \(currentClip.formattedDate)
        """
        itemsToShare.append(shareText)
        
        shareItems = itemsToShare
        showShareSheet = true
    }

}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    @Environment(\.dismiss) var dismiss
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )
        
        // Don't exclude any activity types - show all native options
        controller.excludedActivityTypes = nil
        
        // Configure for iPad (needs popover)
        if let popover = controller.popoverPresentationController {
            popover.sourceView = UIView()
            popover.sourceRect = CGRect(x: UIScreen.main.bounds.width / 2, y: UIScreen.main.bounds.height / 2, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        
        // Handle completion
        controller.completionWithItemsHandler = { _, completed, _, _ in
            dismiss()
        }
        
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Play Button Style

struct PlayButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}


// MARK: - Preview

struct ClipDetailViewPreview: View {
    @Namespace private var namespace
    @State private var selectedClip: ClipMetadata? = MockData.clips[0]

    var body: some View {
        ClipDetailView(
            clip: MockData.clips[0],
            namespace: namespace,
            selectedClip: $selectedClip,
            viewState: GlobalViewState()
        )
    }
}

#Preview {
    ClipDetailViewPreview()
}
