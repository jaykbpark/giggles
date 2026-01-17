import SwiftUI
import AVKit

struct ClipDetailView: View {
    let clip: ClipMetadata
    var namespace: Namespace.ID
    @Binding var selectedClip: ClipMetadata?
    
    @State private var isPlaying = true
    @State private var showControls = true
    @State private var controlsTimer: Timer?

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
                        .fill(.white.opacity(0.15))
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(.white)
                        .offset(x: isPlaying ? 0 : 3)
                }
            }
            .buttonStyle(PlayButtonStyle())
            
            // Top and bottom controls
            VStack {
                // Top bar
                HStack {
                    Spacer()
                    
                    // Close button
                    Button(action: close) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(
                                Circle()
                                    .fill(.white.opacity(0.15))
                            )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 60)
                
                Spacer()
                
                // Bottom info
                VStack(alignment: .leading, spacing: 8) {
                    // Duration badge
                    HStack {
                        Text(clip.formattedDuration)
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.8))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(.white.opacity(0.15))
                            )
                        
                        Spacer()
                    }
                    
                    // Title
                    Text(clip.title)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                    
                    // Date
                    Text(clip.formattedDate)
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 50)
            }
        }
    }
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
            selectedClip: $selectedClip
        )
    }
}

#Preview {
    ClipDetailViewPreview()
}
