import SwiftUI

/// A draggable timeline scrubber for video playback with glass effect styling
struct TimelineScrubber: View {
    @Binding var currentTime: TimeInterval
    let duration: TimeInterval
    let onSeek: (TimeInterval) -> Void
    
    @State private var isDragging = false
    @State private var dragProgress: CGFloat = 0
    
    private var progress: CGFloat {
        guard duration > 0 else { return 0 }
        return isDragging ? dragProgress : CGFloat(currentTime / duration)
    }
    
    var body: some View {
        VStack(spacing: 8) {
            // Time labels
            HStack {
                Text(formatTime(currentTime))
                    .font(AppTypography.metadata)
                    .foregroundStyle(.white.opacity(0.8))
                
                Spacer()
                
                Text(formatTime(duration))
                    .font(AppTypography.metadata)
                    .foregroundStyle(.white.opacity(0.6))
            }
            
            // Scrubber track
            GeometryReader { geometry in
                let width = geometry.size.width
                let handleSize: CGFloat = 16
                let trackHeight: CGFloat = 4
                let expandedTrackHeight: CGFloat = 6
                
                ZStack(alignment: .leading) {
                    // Background track
                    Capsule()
                        .fill(.white.opacity(0.2))
                        .frame(height: isDragging ? expandedTrackHeight : trackHeight)
                    
                    // Progress fill
                    Capsule()
                        .fill(.white)
                        .frame(width: max(0, width * progress), height: isDragging ? expandedTrackHeight : trackHeight)
                    
                    // Draggable handle
                    Circle()
                        .fill(.white)
                        .frame(width: handleSize, height: handleSize)
                        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                        .scaleEffect(isDragging ? 1.3 : 1.0)
                        .offset(x: max(0, min(width - handleSize, width * progress - handleSize / 2)))
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    if !isDragging {
                                        isDragging = true
                                        HapticManager.playLight()
                                    }
                                    
                                    let newProgress = max(0, min(1, value.location.x / width))
                                    dragProgress = newProgress
                                    
                                    let newTime = TimeInterval(newProgress) * duration
                                    onSeek(newTime)
                                }
                                .onEnded { value in
                                    isDragging = false
                                    
                                    let finalProgress = max(0, min(1, value.location.x / width))
                                    let finalTime = TimeInterval(finalProgress) * duration
                                    currentTime = finalTime
                                    onSeek(finalTime)
                                    
                                    HapticManager.playLight()
                                }
                        )
                }
                .frame(height: handleSize)
                .contentShape(Rectangle())
                .onTapGesture { location in
                    let tappedProgress = max(0, min(1, location.x / width))
                    let tappedTime = TimeInterval(tappedProgress) * duration
                    currentTime = tappedTime
                    onSeek(tappedTime)
                    HapticManager.playLight()
                }
            }
            .frame(height: 16)
        }
        .padding(.horizontal, 20)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isDragging)
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        
        TimelineScrubber(
            currentTime: .constant(15),
            duration: 30,
            onSeek: { _ in }
        )
        .padding()
    }
}
