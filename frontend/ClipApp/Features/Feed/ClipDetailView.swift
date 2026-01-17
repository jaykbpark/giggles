import SwiftUI
import AVKit

struct ClipDetailView: View {
    let clip: ClipMetadata
    var namespace: Namespace.ID
    @Binding var selectedClip: ClipMetadata?
    
    @State private var isPlaying = false
    @State private var appearAnimation = false

    var body: some View {
        ZStack(alignment: .top) {
            // 1. Ambiance/Aura Background
            auraBackground
                .ignoresSafeArea()
                .opacity(appearAnimation ? 1 : 0)

            // 2. Scrollable Content
            ScrollView {
                VStack(spacing: 0) {
                    // Spacer for the video player area (it floats above)
                    Color.clear
                        .frame(height: UIScreen.main.bounds.width * 16/9) // Match video aspect ratio
                        .frame(maxHeight: 500)

                    // Content Area
                    VStack(alignment: .leading, spacing: 24) {
                        headerSection
                        transcriptSection
                        topicsSection
                    }
                    .padding(20)
                    .background(
                        Rectangle()
                            .fill(Color(.systemBackground))
                            .mask(
                                LinearGradient(stops: [
                                    .init(color: .clear, location: 0),
                                    .init(color: .black, location: 0.05)
                                ], startPoint: .top, endPoint: .bottom)
                            )
                    )
                    .offset(y: appearAnimation ? 0 : 200)
                }
            }
            .scrollIndicators(.hidden)

            // 3. Morphing Video Player (Floating)
            videoPlayerArea
                .frame(height: UIScreen.main.bounds.width * 16/9)
                .frame(maxHeight: 500)
                .clipShape(RoundedRectangle(cornerRadius: appearAnimation ? 32 : 4, style: .continuous))
                .matchedGeometryEffect(id: clip.id, in: namespace)
                .shadow(color: .black.opacity(0.3), radius: 30, y: 10)
                .ignoresSafeArea(.container, edges: .top)

            // 4. Controls / Close Button
            HStack {
                Spacer()
                Button {
                    close()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
                .padding(.top, 50) // Safe area approximation
                .padding(.trailing, 20)
                .opacity(appearAnimation ? 1 : 0)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                appearAnimation = true
                isPlaying = true
            }
        }
    }

    private func close() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            appearAnimation = false
            selectedClip = nil
        }
    }

    private var auraBackground: some View {
        ZStack {
            Color(.systemBackground)
            
            // Abstract aura blob
            Circle()
                .fill(AppAccents.primary.opacity(0.3))
                .frame(width: 300, height: 300)
                .blur(radius: 100)
                .offset(x: -100, y: -200)
            
            Circle()
                .fill(Color.blue.opacity(0.2))
                .frame(width: 250, height: 250)
                .blur(radius: 80)
                .offset(x: 100, y: -100)
        }
    }

    private var videoPlayerArea: some View {
        ZStack {
            // Background gradient (fallback)
            LinearGradient(
                colors: [Color(.systemGray5), Color(.systemGray6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Play button overlay with glass effect
            VStack(spacing: 16) {
                Button {
                    HapticManager.playLight()
                    isPlaying.toggle()
                } label: {
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 80, height: 80)
                            .glassEffect(in: .circle)
                            .shadow(color: .black.opacity(0.15), radius: 12, y: 6)

                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.primary)
                            .offset(x: isPlaying ? 0 : 3)
                    }
                }
                .buttonStyle(ShutterButtonStyle())

                if !isPlaying {
                    Text("Tap to play")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(clip.title)
                .font(.title2)
                .fontWeight(.bold)

            HStack(spacing: 16) {
                Label(clip.formattedDuration, systemImage: "clock")
                Label(clip.formattedDate, systemImage: "calendar")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }

    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Transcript", systemImage: "text.quote")
                    .font(.headline)

                Spacer()

                Button {
                    UIPasteboard.general.string = clip.transcript
                    HapticManager.playSuccess()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Text(clip.transcript)
                .font(.body)
                .foregroundStyle(.secondary)
                .lineSpacing(6)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .glassEffect(in: .rect(cornerRadius: 16))
                }
        }
    }

    private var topicsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Topics", systemImage: "tag")
                .font(.headline)

            FlowLayout(spacing: 8) {
                ForEach(clip.topics, id: \.self) { topic in
                    TopicPill(topic: topic)
                }
            }
        }
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
