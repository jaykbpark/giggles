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
            // Background
            AppColors.warmBackground
                .ignoresSafeArea()
                .opacity(appearAnimation ? 1 : 0)

            // Scrollable Content
            ScrollView {
                VStack(spacing: 0) {
                    // Video player area
                    videoPlayerArea
                        .frame(height: UIScreen.main.bounds.width * 9/16)
                        .frame(maxHeight: 400)
                        .clipShape(RoundedRectangle(cornerRadius: appearAnimation ? 24 : 4, style: .continuous))
                        .matchedGeometryEffect(id: clip.id, in: namespace)
                        .shadow(color: .black.opacity(0.15), radius: 24, y: 12)
                        .padding(.horizontal, 20)
                        .padding(.top, 60)

                    // Content Area
                    VStack(alignment: .leading, spacing: 28) {
                        headerSection
                        transcriptSection
                        topicsSection
                    }
                    .padding(24)
                    .padding(.top, 8)
                    .opacity(appearAnimation ? 1 : 0)
                    .offset(y: appearAnimation ? 0 : 40)
                }
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)

            // Close Button with glass
            HStack {
                Spacer()
                Button {
                    close()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                        .glassEffect(.regular.interactive())
                }
                .opacity(appearAnimation ? 1 : 0)
            }
            .padding(.top, 16)
            .padding(.horizontal, 20)
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                appearAnimation = true
            }
        }
    }

    private func close() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            appearAnimation = false
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                selectedClip = nil
            }
        }
    }

    private var videoPlayerArea: some View {
        ZStack {
            // Glass background
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.clear)
                .glassEffect(in: .rect(cornerRadius: 24))

            // Play button
            VStack(spacing: 12) {
                Button {
                    HapticManager.playLight()
                    isPlaying.toggle()
                } label: {
                    ZStack {
                        Circle()
                            .fill(.clear)
                            .frame(width: 72, height: 72)
                            .glassEffect(.regular.interactive(), in: .circle)

                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 24, weight: .semibold))
                            .offset(x: isPlaying ? 0 : 2)
                    }
                }
                .buttonStyle(PlayButtonStyle())

                if !isPlaying {
                    Text("Tap to play")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Time badge with glass
            Text(clip.formattedTime)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColors.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .glassEffect(in: .capsule)
            
            // Date
            Text(clip.dateGroupKey)
                .font(.system(size: 28, weight: .bold))

            HStack(spacing: 16) {
                Label(clip.formattedDuration, systemImage: "clock")
                Label(clip.relativeDate, systemImage: "calendar")
            }
            .font(.system(size: 14))
            .foregroundStyle(.secondary)
        }
    }

    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Transcript")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    UIPasteboard.general.string = clip.transcript
                    HapticManager.playSuccess()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .glassEffect(.regular.interactive())
                }
            }

            Text(clip.transcript)
                .font(.system(size: 16))
                .lineSpacing(6)
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(in: .rect(cornerRadius: 16))
        }
    }

    private var topicsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Topics")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.secondary)

            FlowLayout(spacing: 8) {
                ForEach(clip.topics, id: \.self) { topic in
                    Text(topic)
                        .font(.system(size: 14, weight: .medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .glassEffect(in: .capsule)
                }
            }
        }
    }
}

// MARK: - Play Button Style

struct PlayButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Flow Layout

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
