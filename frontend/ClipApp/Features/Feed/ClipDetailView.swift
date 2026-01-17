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
                        .shadow(color: .black.opacity(0.1), radius: 20, y: 10)
                        .padding(.horizontal, 20)
                        .padding(.top, 60)

                    // Content Area
                    VStack(alignment: .leading, spacing: 32) {
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

            // Close Button
            HStack {
                Spacer()
                Button {
                    close()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background {
                            Circle()
                                .fill(.black.opacity(0.5))
                                .overlay {
                                    Circle()
                                        .strokeBorder(.white.opacity(0.2), lineWidth: 1)
                                }
                        }
                        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
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
            // Background
            AppColors.warmSurface

            // Play button
            VStack(spacing: 12) {
                Button {
                    HapticManager.playLight()
                    isPlaying.toggle()
                } label: {
                    ZStack {
                        Circle()
                            .fill(AppColors.warmBackground)
                            .frame(width: 72, height: 72)
                            .shadow(color: AppColors.cardShadow, radius: 12, y: 4)

                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)
                            .offset(x: isPlaying ? 0 : 2)
                    }
                }
                .buttonStyle(PlayButtonStyle())

                if !isPlaying {
                    Text("Tap to play")
                        .font(.system(size: 13))
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Time
            Text(clip.formattedTime)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColors.accent)
            
            // Title/Date
            Text(clip.dateGroupKey)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(AppColors.textPrimary)

            HStack(spacing: 16) {
                Label(clip.formattedDuration, systemImage: "clock")
                Label(clip.relativeDate, systemImage: "calendar")
            }
            .font(.system(size: 14))
            .foregroundStyle(AppColors.textSecondary)
        }
    }

    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Transcript")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppColors.textSecondary)

                Spacer()

                Button {
                    UIPasteboard.general.string = clip.transcript
                    HapticManager.playSuccess()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 14))
                        .foregroundStyle(AppColors.textSecondary)
                }
            }

            Text(clip.transcript)
                .font(.system(size: 16))
                .foregroundStyle(AppColors.textPrimary)
                .lineSpacing(6)
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(AppColors.warmSurface)
                }
        }
    }

    private var topicsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Topics")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(AppColors.textSecondary)

            FlowLayout(spacing: 8) {
                ForEach(clip.topics, id: \.self) { topic in
                    Text(topic)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColors.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background {
                            Capsule()
                                .fill(AppColors.warmSurface)
                        }
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
