import SwiftUI

struct FeedView: View {
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
            loadingState
        } else if clips.isEmpty {
            emptyState
        } else {
            feedContent
        }
    }
    
    // MARK: - Loading State
    
    private var loadingState: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(0..<5, id: \.self) { _ in
                    SkeletonClipCard()
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
        }
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 24) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(AppColors.warmSurface)
                    .frame(width: 120, height: 120)
                
                Image(systemName: "video.badge.waveform")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(AppColors.textSecondary.opacity(0.5))
            }
            
            VStack(spacing: 8) {
                Text("No clips yet")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                
                Text("Tap the record button or say\n\"Clip that\" to capture a moment")
                    .font(.system(size: 15))
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            
            Spacer()
            Spacer()
        }
        .padding(40)
    }
    
    // MARK: - Feed Content
    
    private var feedContent: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                ForEach(groupedClips, id: \.0) { dateGroup, groupClips in
                    sectionHeader(dateGroup)

                    ForEach(groupClips) { clip in
                        ClipCard(clip: clip, namespace: namespace)
                            .onTapGesture {
                                HapticManager.playLight()
                                withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                                    selectedClip = clip
                                }
                            }
                            .padding(.horizontal, 20)
                    }
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 120) // Space for record button
        }
        .scrollIndicators(.hidden)
    }
    
    // MARK: - Section Header
    
    private func sectionHeader(_ title: String) -> some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(AppColors.timelineLine.opacity(0.8))
                .frame(height: 1)
            
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(AppColors.textSecondary)
                .tracking(0.8)
            
            Rectangle()
                .fill(AppColors.timelineLine.opacity(0.8))
                .frame(height: 1)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 6)
    }
}

// MARK: - Clip Card

struct ClipCard: View {
    let clip: ClipMetadata
    var namespace: Namespace.ID
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Thumbnail area
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(.systemGray4), Color(.systemGray5)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .aspectRatio(16/9, contentMode: .fit)
                    .overlay {
                        LinearGradient(
                            colors: [.clear, Color.black.opacity(0.35)],
                            startPoint: .center,
                            endPoint: .bottom
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                
                // Play icon
                Image(systemName: "play.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .matchedGeometryEffect(id: clip.id, in: namespace)
            
            // Content area
            VStack(alignment: .leading, spacing: 8) {
                // Title
                Text(clip.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(2)
                
                // Metadata row
                HStack(spacing: 12) {
                    // Time
                    Label(clip.formattedTime, systemImage: "clock")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                    
                    // Topics
                    if let firstTopic = clip.topics.first {
                        Text("•")
                            .foregroundStyle(AppColors.textSecondary)
                        
                        Text(firstTopic)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppColors.accent)
                    }
                    
                    Spacer()
                }
                .padding(.top, 4)
            }
            .padding(16)
        }
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppColors.warmSurface)
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(AppColors.timelineLine.opacity(0.4), lineWidth: 1)
                }
                .shadow(color: AppColors.cardShadow, radius: 12, y: 6)
        }
    }
}

// MARK: - Skeleton Card

struct SkeletonClipCard: View {
    @State private var isAnimating = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppColors.warmSurface)
                .aspectRatio(16/9, contentMode: .fit)
            
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(AppColors.warmSurface)
                    .frame(height: 20)
                    .frame(maxWidth: 200)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(AppColors.warmSurface)
                    .frame(height: 16)
                    .frame(maxWidth: 280)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(AppColors.warmSurface)
                    .frame(height: 14)
                    .frame(maxWidth: 120)
            }
            .padding(16)
        }
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppColors.warmSurface)
        }
        .opacity(isAnimating ? 0.6 : 1.0)
        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isAnimating)
        .onAppear {
            isAnimating = true
        }
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @Namespace private var namespace
        
        var body: some View {
            ZStack {
                AppColors.warmBackground.ignoresSafeArea()
                
                FeedView(
                    clips: MockData.clips,
                    isLoading: false,
                    selectedClip: .constant(nil),
                    namespace: namespace
                )
            }
        }
    }
    
    return PreviewWrapper()
}
