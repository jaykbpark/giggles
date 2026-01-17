import SwiftUI

struct FeedView: View {
    let clips: [ClipMetadata]
    let isLoading: Bool
    @Binding var selectedClip: ClipMetadata?
    var namespace: Namespace.ID
    
    @State private var showScrollTop = false
    @State private var emptyFloat = false
    
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
                    .shadow(color: AppColors.cardShadow, radius: 12, y: 6)
                
                Image(systemName: "video.badge.waveform")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(AppColors.textSecondary.opacity(0.5))
            }
            .offset(y: emptyFloat ? -6 : 6)
            .animation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true), value: emptyFloat)
            
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
        .onAppear {
            emptyFloat = true
        }
    }
    
    // MARK: - Feed Content
    
    private var feedContent: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottomLeading) {
                ScrollView {
                    GeometryReader { geo in
                        Color.clear
                            .preference(key: ScrollOffsetKey.self, value: geo.frame(in: .named("feedScroll")).minY)
                    }
                    .frame(height: 0)
                    .id("top")
                    
                    LazyVStack(spacing: 16) {
                        ForEach(clips) { clip in
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
                    .padding(.top, 12)
                    .padding(.bottom, 120) // Space for record button
                }
                .coordinateSpace(name: "feedScroll")
                .scrollIndicators(.hidden)
                .onPreferenceChange(ScrollOffsetKey.self) { value in
                    showScrollTop = value < -280
                }
                
                if showScrollTop {
                    Button {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                            proxy.scrollTo("top", anchor: .top)
                        }
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)
                            .frame(width: 40, height: 40)
                            .glassEffect(.regular.interactive(), in: .circle)
                    }
                    .padding(.leading, 20)
                    .padding(.bottom, 28)
                    .transition(.scale.combined(with: .opacity))
                }
            }
        }
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
                // Date pill + Time
                HStack(spacing: 8) {
                    Text(clip.dateGroupKey.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(AppColors.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background {
                            Capsule()
                                .fill(AppColors.warmBackground)
                        }
                    
                    Text(clip.formattedTime)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppColors.accent)
                    
                    Spacer()
                }
                
                // Title
                Text(clip.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(2)
                
                // Topics
                if !clip.topics.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(clip.topics.prefix(2), id: \.self) { topic in
                            Text(topic)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(AppColors.textSecondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background {
                                    Capsule()
                                        .stroke(AppColors.timelineLine.opacity(0.6), lineWidth: 1)
                                }
                        }
                    }
                }
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
                .shadow(color: AppColors.cardShadow, radius: 14, y: 8)
        }
    }
}

// MARK: - Skeleton Card

struct SkeletonClipCard: View {
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
        .shimmering()
    }
}

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
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
