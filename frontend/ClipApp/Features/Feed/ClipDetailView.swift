import SwiftUI
import AVKit

struct ClipDetailView: View {
    let clip: ClipMetadata
    var namespace: Namespace.ID
    @Binding var selectedClip: ClipMetadata?
    
    @State private var isPlaying = false
    @State private var appearAnimation = false
    @State private var showControls = true
    @State private var controlsTimer: Timer?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Fullscreen black background
                Color.black
                    .ignoresSafeArea()
                
                // Video player area - fullscreen
                videoPlayerArea
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .matchedGeometryEffect(id: clip.id, in: namespace)
                    .ignoresSafeArea()
                    .onTapGesture {
                        toggleControls()
                    }
                
                // Overlay controls (fade in/out)
                if showControls {
                    controlsOverlay
                        .transition(.opacity)
                }
            }
        }
        .statusBarHidden(true)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                appearAnimation = true
                isPlaying = true
            }
            startControlsTimer()
        }
        .onDisappear {
            controlsTimer?.invalidate()
        }
    }
    
    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.25)) {
            showControls.toggle()
        }
        if showControls {
            startControlsTimer()
        }
    }
    
    private func startControlsTimer() {
        controlsTimer?.invalidate()
        controlsTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            withAnimation(.easeInOut(duration: 0.25)) {
                showControls = false
            }
        }
    }

    private func close() {
        HapticManager.playLight()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            appearAnimation = false
            selectedClip = nil
        }
    }

    private var videoPlayerArea: some View {
        ZStack {
            // Background gradient (fallback/placeholder for actual video)
            LinearGradient(
                colors: [Color(.systemGray5), Color(.systemGray6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            // Placeholder content - in real app, use AVPlayer here
            VStack(spacing: 20) {
                Image(systemName: "video.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.secondary)
                
                Text(clip.title)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private var controlsOverlay: some View {
        ZStack {
            // Gradient overlays for better control visibility
            VStack {
                // Top gradient
                LinearGradient(
                    colors: [.black.opacity(0.6), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 120)
                
                Spacer()
                
                // Bottom gradient
                LinearGradient(
                    colors: [.clear, .black.opacity(0.6)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 200)
            }
            .ignoresSafeArea()
            
            VStack {
                // Top bar with close button
                HStack {
                    Spacer()
                    
                    Button(action: close) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(
                                Circle()
                                    .fill(.black.opacity(0.5))
                                    .overlay(
                                        Circle()
                                            .strokeBorder(.white.opacity(0.3), lineWidth: 1)
                                    )
                            )
                            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 60)
                
                Spacer()
                
                // Center play/pause button
                Button {
                    HapticManager.playLight()
                    isPlaying.toggle()
                    startControlsTimer()
                } label: {
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 80, height: 80)
                        
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundStyle(.white)
                            .offset(x: isPlaying ? 0 : 3)
                    }
                }
                .buttonStyle(PlayButtonStyle())
                
                Spacer()
                
                // Bottom info area
                VStack(alignment: .leading, spacing: 12) {
                    Text(clip.title)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                    
                    HStack(spacing: 16) {
                        Label(clip.formattedDate, systemImage: "calendar")
                        
                        if !clip.topics.isEmpty {
                            Label(clip.topics.first ?? "", systemImage: "tag")
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
                    
                    // Transcript preview
                    if !clip.transcript.isEmpty {
                        Text(clip.transcript)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(2)
                            .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .padding(.bottom, 30)
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

// MARK: - Flow Layout for Topics

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                       y: bounds.minY + result.positions[index].y),
                          proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: currentY + lineHeight), positions)
    }
}

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
