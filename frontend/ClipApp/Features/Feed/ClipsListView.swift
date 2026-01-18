import SwiftUI

struct ClipsListView: View {
    let clips: [ClipMetadata]
    let isLoading: Bool
    @Binding var selectedClip: ClipMetadata?
    var namespace: Namespace.ID

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
            loadingList
        } else if clips.isEmpty {
            emptyState
        } else {
            clipsList
        }
    }

    private var loadingList: some View {
        VStack(spacing: 0) {
            ForEach(0..<6, id: \.self) { _ in
                SkeletonListRow()
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                Divider()
                    .padding(.leading, 20)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "video.slash")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text("No clips yet")
                .font(.title3)
                .fontWeight(.medium)

            Text("Tap the red button to capture a moment")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
        .padding()
    }

    private var clipsList: some View {
        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
            ForEach(groupedClips, id: \.0) { dateGroup, clips in
                Section {
                    ForEach(clips) { clip in
                        ModernListRow(clip: clip)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                HapticManager.playLight()
                                selectedClip = clip
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)

                        if clip.id != clips.last?.id {
                            Divider()
                                .padding(.leading, 106)
                        }
                    }
                } header: {
                    sectionHeader(dateGroup)
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.title3)
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(.systemBackground))
    }
}

// MARK: - Modern List Row

struct ModernListRow: View {
    let clip: ClipMetadata

    var body: some View {
        HStack(spacing: 14) {
            // Thumbnail
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(.systemGray5), Color(.systemGray6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Image(systemName: "video.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color(.systemGray3))

                // Duration overlay
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text(clip.formattedDuration)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background {
                                Capsule()
                                    .fill(.black.opacity(0.6))
                            }
                            .padding(6)
                    }
                }
            }
            .frame(width: 72, height: 72)

            // Content
            VStack(alignment: .leading, spacing: 6) {
                Text(clip.title)
                    .font(.body)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                Text(clip.transcript)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Text(timeString(from: clip.capturedAt))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
    }

    private func timeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}

struct ClipsListViewPreview: View {
    @Namespace private var namespace

    var body: some View {
        ScrollView {
            ClipsListView(
                clips: [],
                isLoading: false,
                selectedClip: .constant(nil),
                namespace: namespace
            )
        }
    }
}

#Preview {
    ClipsListViewPreview()
}
