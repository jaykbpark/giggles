import SwiftUI
import AVKit
import AVFoundation
import Photos

struct ClipDetailView: View {
    let clip: ClipMetadata
    var namespace: Namespace.ID
    @Binding var selectedClip: ClipMetadata?
    @ObservedObject var viewState: GlobalViewState
    
    // Pager integration props
    var isActive: Bool = true
    var onReachedEnd: (() -> Void)? = nil
    var onClose: (() -> Void)? = nil
    
    @State private var isPlaying = true
    @State private var showControls = true
    @State private var controlsTimer: Timer?
    
    // Video player state
    @State private var player: AVPlayer?
    @State private var videoURL: URL?
    @State private var isLoadingVideo = true
    @State private var videoLoadError: String?
    @State private var timeObserver: Any?
    @State private var endTimeObserver: NSObjectProtocol?
    @State private var videoDuration: TimeInterval = 0
    @State private var videoLoadTask: Task<Void, Never>?
    
    // Audio narration state
    @State private var audioEndObserver: NSObjectProtocol?
    @State private var audioPlayer: AVPlayer?
    @State private var isPlayingAudio = false
    @State private var isGeneratingAudio = false
    @State private var audioError: String?
    
    // Share state
    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []
    
    // Caption state
    @State private var showCaptions = true
    @State private var currentPlaybackTime: TimeInterval = 0
    @State private var playbackTimer: Timer?
    
    // End-of-clip bounce animation state
    @State private var bounceOffset: CGFloat = 0
    @State private var showNextHint = false
    @State private var hasTriggeredEndBounce = false
    
    // Scrubber seeking state
    @State private var isSeeking = false
    
    private let photoManager = PhotoManager()

    private var currentClip: ClipMetadata {
        viewState.clips.first(where: { $0.id == clip.id }) ?? clip
    }
    
    private var effectiveDuration: TimeInterval {
        videoDuration > 0 ? videoDuration : currentClip.duration
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
                .offset(y: bounceOffset)
            
            // Overlay controls (fade in/out)
            if showControls {
                controlsOverlay
                    .transition(.opacity)
            }
            
            // Next clip hint indicator
            if showNextHint {
                VStack {
                    Spacer()
                    
                    VStack(spacing: 8) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.8))
                        
                        Text("Swipe for next")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .padding(.bottom, 100)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
                .animation(.easeInOut(duration: 0.3), value: showNextHint)
            }
        }
        .ignoresSafeArea(.all)
        .statusBarHidden(true)
        .onAppear {
            startControlsTimer()
            configureAudioSession()
            if isActive {
                loadVideo()
            }
        }
        .onDisappear {
            cleanupPlayer()
            controlsTimer?.invalidate()
            stopAudio()
        }
        .onChange(of: isActive) { _, active in
            if active {
                loadVideo()
                if isPlaying {
                    player?.play()
                }
            } else {
                // Full cleanup when becoming inactive to prevent audio leaking
                cleanupPlayer()
                stopAudio()
                // Reset bounce state when becoming inactive
                hasTriggeredEndBounce = false
                showNextHint = false
                bounceOffset = 0
            }
        }
        .onChange(of: isPlaying) { _, playing in
            if playing && isActive {
                player?.play()
            } else {
                player?.pause()
            }
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
        if let onClose = onClose {
            onClose()
        } else {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                selectedClip = nil
            }
        }
    }
    
    // MARK: - Video Loading
    
    private func loadVideo() {
        guard player == nil else { return } // Already loaded
        
        isLoadingVideo = true
        videoLoadError = nil
        
        // Store task so it can be cancelled during cleanup
        videoLoadTask = Task {
            do {
                // Prefer local master file if available
                if let localPath = currentClip.localFileURL,
                   FileManager.default.fileExists(atPath: localPath) {
                    let localURL = URL(fileURLWithPath: localPath)
                    
                    // Check if cancelled or inactive before setting up player
                    guard !Task.isCancelled && isActive else { return }
                    
                    await MainActor.run {
                        guard isActive else { return }  // Double-check on main thread
                        videoURL = localURL
                        setupPlayer(with: localURL)
                    }
                    return
                }
                
                // Fetch video from Photo Library
                guard let asset = photoManager.fetchAsset(for: currentClip.localIdentifier) else {
                    throw PhotoManagerError.assetNotFound
                }
                let url = try await photoManager.getVideoURL(for: asset)
                
                // Check if cancelled or inactive before setting up player
                guard !Task.isCancelled && isActive else { return }
                
                await MainActor.run {
                    guard isActive else { return }  // Double-check on main thread
                    videoURL = url
                    setupPlayer(with: url)
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    videoLoadError = error.localizedDescription
                    isLoadingVideo = false
                    videoDuration = currentClip.duration
                    // Start simulated playback for testing
                    if isActive {
                        startPlaybackTimer()
                    }
                }
            }
        }
    }
    
    private func setupPlayer(with url: URL) {
        let playerItem = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)
        
        // Get actual video duration
        Task {
            if let asset = player?.currentItem?.asset {
                let duration = try? await asset.load(.duration)
                await MainActor.run {
                    videoDuration = duration?.seconds ?? currentClip.duration
                }
            }
        }
        
        // Add time observer for captions and scrubber
        timeObserver = player?.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
            queue: .main
        ) { [self] time in
            guard !isSeeking else { return }
            currentPlaybackTime = time.seconds
            checkForEndOfClip()
        }
        
        // Loop video and trigger end bounce - store observer to remove during cleanup
        endTimeObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { _ in
            triggerEndBounce()
            player?.seek(to: .zero)
            player?.play()
        }
        
        isLoadingVideo = false
        if isActive {
            isPlaying = true
            player?.play()
        }
    }
    
    private func cleanupPlayer() {
        // Cancel any pending video load task to prevent race conditions
        videoLoadTask?.cancel()
        videoLoadTask = nil
        
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        if let observer = endTimeObserver {
            NotificationCenter.default.removeObserver(observer)
            endTimeObserver = nil
        }
        player?.pause()
        player = nil
        playbackTimer?.invalidate()
        playbackTimer = nil
    }
    
    private func startPlaybackTimer() {
        // Simulated playback for clips without actual video
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            guard !isSeeking else { return }
            if isPlaying && isActive {
                currentPlaybackTime += 0.1
                checkForEndOfClip()
                if currentPlaybackTime >= effectiveDuration {
                    triggerEndBounce()
                    currentPlaybackTime = 0
                }
            }
        }
    }
    
    private func checkForEndOfClip() {
        // Trigger bounce hint when reaching 90% of clip duration
        let threshold = effectiveDuration * 0.90
        if currentPlaybackTime >= threshold && !hasTriggeredEndBounce && effectiveDuration > 0 {
            // Will trigger on actual end, not here
        }
    }
    
    private func triggerEndBounce() {
        guard !hasTriggeredEndBounce else { return }
        hasTriggeredEndBounce = true
        
        // Bounce animation
        withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
            bounceOffset = -30
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                bounceOffset = 0
            }
        }
        
        // Show swipe hint
        withAnimation(.easeInOut(duration: 0.3)) {
            showNextHint = true
        }
        
        // Hide hint after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeInOut(duration: 0.3)) {
                showNextHint = false
            }
        }
        
        // Reset bounce flag after animation completes for next loop
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            hasTriggeredEndBounce = false
        }
        
        onReachedEnd?()
        HapticManager.playLight()
    }
    
    private func togglePlayback() {
        isPlaying.toggle()
        if isPlaying && isActive {
            player?.play()
        } else {
            player?.pause()
        }
    }
    
    private func seekTo(time: TimeInterval) {
        let clampedTime = max(0, min(effectiveDuration, time))
        
        if let player = player {
            let cmTime = CMTime(seconds: clampedTime, preferredTimescale: 600)
            player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        }
        
        currentPlaybackTime = clampedTime
    }

    private var videoPlayerArea: some View {
        ZStack {
            // Dark gradient background
            LinearGradient(
                colors: [Color(white: 0.1), Color(white: 0.05)],
                startPoint: .top,
                endPoint: .bottom
            )
            
            // Video player or placeholder
            if isLoadingVideo {
                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .scaleEffect(1.5)
                    Text("Loading video...")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.6))
                }
            } else if let player = player {
                PlayerView(player: player)
            } else {
                // Fallback placeholder for clips without video
                VStack(spacing: 16) {
                    Image(systemName: videoLoadError != nil ? "exclamationmark.triangle" : "video.fill")
                        .font(.system(size: 48, weight: .light))
                        .foregroundStyle(.white.opacity(0.3))
                    
                    if let error = videoLoadError {
                        Text(error)
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.5))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                }
            }
            
            // Caption overlay
            if showCaptions, let segments = currentClip.captionSegments, !segments.isEmpty {
                CaptionOverlayView(
                    segments: segments,
                    currentTime: currentPlaybackTime,
                    style: currentClip.captionStyle ?? CaptionStyle()
                )
            }
        }
    }
    
    // MARK: - Video Playback
    
    private func configureAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        
        do {
            // First deactivate any existing session to ensure clean state
            // This helps recover from other audio modes (e.g., speech recognition's .record mode)
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            // Deactivation can fail if no session was active - this is OK
            print("ℹ️ Audio session deactivation note: \(error.localizedDescription)")
        }
        
        do {
            // Now configure for video playback
            try audioSession.setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay])
            try audioSession.setActive(true)
        } catch {
            print("⚠️ Failed to configure audio session for playback: \(error)")
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
                
                // Bottom gradient (extended for scrubber)
                LinearGradient(
                    colors: [.clear, .black.opacity(0.7)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 240)
            }
            .ignoresSafeArea()
            
            // Center play/pause button - absolutely centered with expanded hit area
            Button {
                HapticManager.playLight()
                togglePlayback()
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
                .frame(width: 120, height: 120)  // Larger frame for easier tapping
                .contentShape(Circle())           // Make entire area tappable
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
                    
                    // Caption toggle button
                    if currentClip.captionSegments != nil {
                        Button {
                            HapticManager.playLight()
                            showCaptions.toggle()
                        } label: {
                            Image(systemName: showCaptions ? "captions.bubble.fill" : "captions.bubble")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(showCaptions ? AppColors.accent : .white)
                                .frame(width: 40, height: 40)
                                .glassEffect(.regular.interactive(), in: .circle)
                        }
                        .accessibilityLabel(showCaptions ? "Hide captions" : "Show captions")
                    }

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
                
                // Bottom info and scrubber
                VStack(alignment: .leading, spacing: 12) {
                    // Timeline scrubber
                    TimelineScrubber(
                        currentTime: $currentPlaybackTime,
                        duration: effectiveDuration,
                        onSeek: { time in
                            isSeeking = true
                            seekTo(time: time)
                            startControlsTimer()
                            
                            // Reset seeking state after a brief delay
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                isSeeking = false
                            }
                        }
                    )
                    .padding(.horizontal, -20) // Compensate for parent padding
                    
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
            // Stop audio and clean up observer
            stopAudio()
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
            
            // Listen for completion - store observer to remove during cleanup
            audioEndObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player.currentItem,
                queue: .main
            ) { _ in
                isPlayingAudio = false
                audioPlayer = nil
                if let observer = audioEndObserver {
                    NotificationCenter.default.removeObserver(observer)
                    audioEndObserver = nil
                }
            }
            
        } catch {
            audioError = error.localizedDescription
            print("❌ Failed to generate audio narration: \(error)")
        }
        
        isGeneratingAudio = false
    }
    
    private func stopAudio() {
        if let observer = audioEndObserver {
            NotificationCenter.default.removeObserver(observer)
            audioEndObserver = nil
        }
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

// MARK: - Custom Video Player (No Default Controls)

/// A custom video player view that wraps AVPlayerLayer directly,
/// bypassing SwiftUI's VideoPlayer which shows default Apple controls on tap.
struct PlayerView: UIViewRepresentable {
    let player: AVPlayer
    
    func makeUIView(context: Context) -> PlayerUIView {
        PlayerUIView(player: player)
    }
    
    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        uiView.updatePlayer(player)
    }
}

/// The underlying UIView that hosts the AVPlayerLayer
class PlayerUIView: UIView {
    private var playerLayer: AVPlayerLayer
    
    init(player: AVPlayer) {
        playerLayer = AVPlayerLayer(player: player)
        super.init(frame: .zero)
        playerLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(playerLayer)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }
    
    func updatePlayer(_ player: AVPlayer) {
        playerLayer.player = player
    }
}

// MARK: - Preview

struct ClipDetailViewPreview: View {
    @Namespace private var namespace
    private let previewClip = ClipMetadata(
        id: UUID(),
        localIdentifier: "preview",
        title: "Preview Clip",
        transcript: "Preview transcript",
        topics: ["Preview"],
        capturedAt: Date(),
        duration: 30
    )
    @State private var selectedClip: ClipMetadata?

    var body: some View {
        ClipDetailView(
            clip: previewClip,
            namespace: namespace,
            selectedClip: $selectedClip,
            viewState: GlobalViewState()
        )
        .onAppear {
            selectedClip = previewClip
        }
    }
}

#Preview {
    ClipDetailViewPreview()
}
