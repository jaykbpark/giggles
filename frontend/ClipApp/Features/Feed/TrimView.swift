import SwiftUI
import AVKit
import AVFoundation

/// A view for trimming video clips with draggable start/end handles
struct TrimView: View {
    let videoURL: URL
    let onSave: (CMTime, CMTime) -> Void
    let onSaveFull: () -> Void
    var onDiscard: (() -> Void)? = nil
    
    @State private var player: AVPlayer?
    @State private var duration: TimeInterval = 0
    @State private var startTime: TimeInterval = 0
    @State private var endTime: TimeInterval = 30
    @State private var currentTime: TimeInterval = 0
    @State private var isPlaying = false
    @State private var thumbnails: [UIImage] = []
    @State private var isDraggingStart = false
    @State private var isDraggingEnd = false
    @State private var timeObserver: Any?
    
    private let minimumDuration: TimeInterval = 1.0
    private let thumbnailCount = 10
    
    var trimmedDuration: TimeInterval {
        max(endTime - startTime, 0)
    }
    
    var body: some View {
        ZStack {
            // Background - warm minimal theme
            AppColors.warmBackground
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                headerBar
                
                Spacer()
                
                // Video preview
                videoPreview
                    .frame(maxWidth: .infinity)
                    .frame(height: UIScreen.main.bounds.height * 0.45)
                
                Spacer()
                
                // Timeline with handles
                timelineView
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                
                // Duration indicator
                durationIndicator
                    .padding(.bottom, 20)
                
                // Action buttons
                actionButtons
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
            }
        }
        .onAppear {
            setupPlayer()
            generateThumbnails()
        }
        .onDisappear {
            cleanupPlayer()
        }
    }
    
    // MARK: - Header
    
    private var headerBar: some View {
        HStack {
            Button {
                // Default to save full if no discard callback
                if let onDiscard = onDiscard {
                    onDiscard()
                } else {
                    onSaveFull()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .frame(width: 40, height: 40)
                    .background(AppColors.warmSurface)
                    .clipShape(Circle())
                    .overlay {
                        Circle()
                            .stroke(AppColors.timelineLine.opacity(0.4), lineWidth: 1)
                    }
            }
            
            Spacer()
            
            Text("Trim Clip")
                .font(AppTypography.cardTitle)
                .foregroundStyle(AppColors.textPrimary)
            
            Spacer()
            
            // Spacer to balance the close button
            Color.clear
                .frame(width: 40, height: 40)
        }
        .padding(.horizontal, 20)
        .padding(.top, 60)
    }
    
    // MARK: - Video Preview
    
    private var videoPreview: some View {
        ZStack {
            if let player = player {
                VideoPlayer(player: player)
                    .disabled(true) // Disable default controls
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(AppColors.timelineLine, lineWidth: 1)
                    }
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(AppColors.warmSurface)
                    .overlay {
                        ProgressView()
                            .tint(AppColors.accent)
                    }
            }
            
            // Play/Pause overlay
            Button {
                togglePlayback()
            } label: {
                ZStack {
                    Circle()
                        .fill(AppColors.warmSurface.opacity(0.9))
                        .frame(width: 64, height: 64)
                        .shadow(color: AppColors.cardShadow, radius: 8, y: 4)
                    
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(AppColors.accent)
                        .offset(x: isPlaying ? 0 : 2)
                }
            }
            .opacity(isPlaying ? 0 : 1)
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - Timeline View
    
    private var timelineView: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let handleWidth: CGFloat = 16
            let trimAreaWidth = width - handleWidth * 2
            
            ZStack(alignment: .leading) {
                // Thumbnail strip background
                HStack(spacing: 0) {
                    ForEach(Array(thumbnails.enumerated()), id: \.offset) { _, thumbnail in
                        Image(uiImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: trimAreaWidth / CGFloat(max(thumbnails.count, 1)))
                            .clipped()
                    }
                }
                .frame(height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, handleWidth)
                
                // Dimmed areas outside trim range
                HStack(spacing: 0) {
                    // Left dim
                    Rectangle()
                        .fill(AppColors.warmBackground.opacity(0.7))
                        .frame(width: handleWidth + (trimAreaWidth * startTime / max(duration, 1)))
                    
                    Spacer()
                    
                    // Right dim
                    Rectangle()
                        .fill(AppColors.warmBackground.opacity(0.7))
                        .frame(width: handleWidth + (trimAreaWidth * (1 - endTime / max(duration, 1))))
                }
                .frame(height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .allowsHitTesting(false)
                
                // Trim selection frame
                let startX = handleWidth + (trimAreaWidth * startTime / max(duration, 1)) - handleWidth
                let endX = handleWidth + (trimAreaWidth * endTime / max(duration, 1))
                let frameWidth = endX - startX
                
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppColors.accent, lineWidth: 3)
                    .frame(width: frameWidth, height: 56)
                    .offset(x: startX)
                    .allowsHitTesting(false)
                
                // Start handle
                trimHandle(isStart: true)
                    .offset(x: handleWidth + (trimAreaWidth * startTime / max(duration, 1)) - handleWidth)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                isDraggingStart = true
                                let newStartTime = max(0, min(endTime - minimumDuration, 
                                    (value.location.x - handleWidth) / trimAreaWidth * duration))
                                startTime = newStartTime
                                seekTo(time: startTime)
                            }
                            .onEnded { _ in
                                isDraggingStart = false
                            }
                    )
                
                // End handle
                trimHandle(isStart: false)
                    .offset(x: handleWidth + (trimAreaWidth * endTime / max(duration, 1)))
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                isDraggingEnd = true
                                let newEndTime = max(startTime + minimumDuration, 
                                    min(duration, (value.location.x - handleWidth) / trimAreaWidth * duration))
                                endTime = newEndTime
                                seekTo(time: endTime)
                            }
                            .onEnded { _ in
                                isDraggingEnd = false
                            }
                    )
                
                // Playhead
                let playheadX = handleWidth + (trimAreaWidth * currentTime / max(duration, 1))
                Rectangle()
                    .fill(AppColors.textPrimary)
                    .frame(width: 2, height: 64)
                    .offset(x: playheadX - 1)
                    .allowsHitTesting(false)
            }
        }
        .frame(height: 64)
    }
    
    private func trimHandle(isStart: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(AppColors.accent)
                .frame(width: 16, height: 56)
            
            VStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(.white.opacity(0.8))
                        .frame(width: 3, height: 8)
                }
            }
        }
    }
    
    // MARK: - Duration Indicator
    
    private var durationIndicator: some View {
        HStack(spacing: 16) {
            // Start time
            VStack(spacing: 2) {
                Text("START")
                    .font(AppTypography.status)
                    .foregroundStyle(AppColors.textSecondary)
                Text(formatTime(startTime))
                    .font(AppTypography.metadata)
                    .foregroundStyle(AppColors.textPrimary)
            }
            
            // Trimmed duration
            VStack(spacing: 2) {
                Text("DURATION")
                    .font(AppTypography.status)
                    .foregroundStyle(AppColors.textSecondary)
                Text(formatTime(trimmedDuration))
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppColors.accent)
            }
            .padding(.horizontal, 20)
            
            // End time
            VStack(spacing: 2) {
                Text("END")
                    .font(AppTypography.status)
                    .foregroundStyle(AppColors.textSecondary)
                Text(formatTime(endTime))
                    .font(AppTypography.metadata)
                    .foregroundStyle(AppColors.textPrimary)
            }
        }
    }
    
    // MARK: - Action Buttons
    
    private var actionButtons: some View {
        VStack(spacing: 12) {
            // Primary action buttons
            HStack(spacing: 16) {
                // Skip trim (save full clip)
                Button(action: onSaveFull) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.right.circle")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Save Full")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(AppColors.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(AppColors.warmSurface)
                    .clipShape(RoundedRectangle(cornerRadius: AppLayout.cardRadius))
                    .overlay {
                        RoundedRectangle(cornerRadius: AppLayout.cardRadius)
                            .stroke(AppColors.timelineLine.opacity(0.4), lineWidth: 1)
                    }
                }
                
                // Save trimmed button
                Button {
                    HapticManager.playSuccess()
                    let start = CMTime(seconds: startTime, preferredTimescale: 600)
                    let end = CMTime(seconds: endTime, preferredTimescale: 600)
                    onSave(start, end)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "scissors")
                            .font(.system(size: 16, weight: .bold))
                        Text("Trim & Save")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(AppGradients.accent)
                    .clipShape(RoundedRectangle(cornerRadius: AppLayout.cardRadius))
                }
            }
            
            // Discard option
            if let onDiscard = onDiscard {
                Button {
                    HapticManager.playLight()
                    onDiscard()
                } label: {
                    Text("Discard")
                        .font(AppTypography.metadata)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func setupPlayer() {
        let playerItem = AVPlayerItem(url: videoURL)
        player = AVPlayer(playerItem: playerItem)
        
        // Get duration
        Task {
            if let asset = player?.currentItem?.asset {
                let videoDuration = try? await asset.load(.duration)
                await MainActor.run {
                    duration = videoDuration?.seconds ?? 30
                    endTime = duration
                }
            }
        }
        
        // Add time observer
        timeObserver = player?.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
            queue: .main
        ) { [self] time in
            currentTime = time.seconds
            
            // Loop within trim range
            if currentTime >= endTime {
                seekTo(time: startTime)
            }
        }
    }
    
    private func cleanupPlayer() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
        }
        player?.pause()
        player = nil
    }
    
    private func togglePlayback() {
        if isPlaying {
            player?.pause()
        } else {
            // Start from trim start if outside range
            if currentTime < startTime || currentTime >= endTime {
                seekTo(time: startTime)
            }
            player?.play()
        }
        isPlaying.toggle()
    }
    
    private func seekTo(time: TimeInterval) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }
    
    private func generateThumbnails() {
        Task {
            let asset = AVAsset(url: videoURL)
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true
            imageGenerator.maximumSize = CGSize(width: 100, height: 100)
            
            guard let videoDuration = try? await asset.load(.duration) else { return }
            let durationSeconds = videoDuration.seconds
            
            var images: [UIImage] = []
            for i in 0..<thumbnailCount {
                let time = CMTime(seconds: durationSeconds * Double(i) / Double(thumbnailCount), preferredTimescale: 600)
                if let cgImage = try? imageGenerator.copyCGImage(at: time, actualTime: nil) {
                    images.append(UIImage(cgImage: cgImage))
                }
            }
            
            await MainActor.run {
                thumbnails = images
            }
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let fraction = Int((time.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", minutes, seconds, fraction)
    }
}

// MARK: - Preview

#Preview {
    TrimView(
        videoURL: URL(fileURLWithPath: "/dev/null"),
        onSave: { _, _ in },
        onSaveFull: { },
        onDiscard: { }
    )
}
