import SwiftUI

struct ClipsGridView: View {
    let clips: [ClipMetadata]
    let isLoading: Bool
    @Binding var selectedClip: ClipMetadata?
    var namespace: Namespace.ID

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    private var groupedClips: [(String, [ClipMetadata])] {
        let grouped = Dictionary(grouping: clips) { $0.dateGroupKey }
        return grouped.sorted { lhs, rhs in
            let lhsDate = clips.first { $0.dateGroupKey == lhs.key }?.capturedAt ?? Date.distantPast
            let rhsDate = clips.first { $0.dateGroupKey == rhs.key }?.capturedAt ?? Date.distantPast
            return lhsDate > rhsDate
        }
    }

    var body: some View {
        if isLoading {
            loadingGrid
        } else if clips.isEmpty {
            emptyState
        } else {
            clipsGrid
        }
    }

    private var loadingGrid: some View {
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(0..<12, id: \.self) { _ in
                SkeletonGridCell()
            }
        }
        .padding(.horizontal, 2)
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            // Stylized empty state with glasses
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                AppAccents.primary.opacity(0.1),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 60
                        )
                    )
                    .frame(width: 120, height: 120)

                Image(systemName: "video.slash")
                    .font(.system(size: 44))
                    .foregroundStyle(.tertiary)
            }

            VStack(spacing: 8) {
                Text("No clips yet")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))

                Text("Tap the shutter to capture a moment")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 300)
        .padding()
    }

    private var clipsGrid: some View {
        LazyVStack(alignment: .leading, spacing: 24, pinnedViews: .sectionHeaders) {
            ForEach(groupedClips, id: \.0) { dateGroup, clips in
                Section {
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(Array(clips.enumerated()), id: \.element.id) { index, clip in
                            SpectacularClipCell(clip: clip, index: index, namespace: namespace)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    HapticManager.playLight()
                                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                        selectedClip = clip
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, 2)
                } header: {
                    sectionHeader(dateGroup)
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 18, weight: .bold, design: .rounded))

            Spacer()

            // Subtle count badge
            Text("\(clips.count)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background {
                    Capsule()
                        .fill(Color(.tertiarySystemBackground))
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
    }
}

// MARK: - Spectacular Clip Cell

struct SpectacularClipCell: View {
    let clip: ClipMetadata
    let index: Int
    var namespace: Namespace.ID

    // Generate unique gradient based on clip
    private var cellGradient: LinearGradient {
        let gradients: [LinearGradient] = [
            LinearGradient(colors: [Color(red: 0.18, green: 0.18, blue: 0.22), Color(red: 0.12, green: 0.12, blue: 0.14)], startPoint: .topLeading, endPoint: .bottomTrailing),
            LinearGradient(colors: [Color(red: 0.22, green: 0.18, blue: 0.18), Color(red: 0.14, green: 0.11, blue: 0.11)], startPoint: .topLeading, endPoint: .bottomTrailing),
            LinearGradient(colors: [Color(red: 0.17, green: 0.19, blue: 0.22), Color(red: 0.11, green: 0.12, blue: 0.14)], startPoint: .topLeading, endPoint: .bottomTrailing),
            LinearGradient(colors: [Color(red: 0.20, green: 0.18, blue: 0.22), Color(red: 0.13, green: 0.11, blue: 0.14)], startPoint: .topLeading, endPoint: .bottomTrailing)
        ]
        return gradients[index % gradients.count]
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Background
                Rectangle()
                    .fill(cellGradient)

                // Subtle vignette
                RadialGradient(
                    colors: [Color.clear, Color.black.opacity(0.3)],
                    center: .center,
                    startRadius: geo.size.width * 0.3,
                    endRadius: geo.size.width * 0.8
                )

                // Play button
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.15))
                        .frame(width: 40, height: 40)

                    Image(systemName: "play.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .offset(x: 1)
                }

                // Duration badge
                VStack {
                    Spacer()
                    HStack {
                        Text(clip.formattedDuration)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background {
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(.black.opacity(0.6))
                            }
                        Spacer()
                    }
                    .padding(6)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .matchedGeometryEffect(id: clip.id, in: namespace)
            .frame(width: geo.size.width, height: geo.size.width)
            .clipped()
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

struct ClipsGridViewPreview: View {
    @Namespace private var namespace

    var body: some View {
        ScrollView {
            ClipsGridView(
                clips: [],
                isLoading: false,
                selectedClip: .constant(nil),
                namespace: namespace
            )
        }
    }
}

#Preview {
    ClipsGridViewPreview()
}
