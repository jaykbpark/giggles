import SwiftUI

/// A vertical paging container for browsing clips TikTok/Reels style
struct ClipPagerView: View {
    let clips: [ClipMetadata]
    let initialClip: ClipMetadata
    @Binding var selectedClip: ClipMetadata?
    @ObservedObject var viewState: GlobalViewState
    var namespace: Namespace.ID
    
    // Start as nil to prevent the first clip from briefly being "active"
    @State private var currentIndex: Int? = nil
    @State private var scrolledID: UUID?
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging: Bool = false
    
    /// Whether the drag has crossed the dismiss threshold
    private var canDismiss: Bool {
        dragOffset > 100
    }
    
    /// Progress of the drag (0 to 1, clamped)
    private var dragProgress: CGFloat {
        min(dragOffset / 100, 1.0)
    }
    
    var body: some View {
        ZStack(alignment: .leading) {
            // Only render content once currentIndex is determined
            // This prevents the first clip from briefly being active
            if let activeIndex = currentIndex {
                pagerContent(activeIndex: activeIndex)
            } else {
                // Placeholder while determining initial index
                Color.black
                    .ignoresSafeArea()
                    .onAppear {
                        // Set initial index before any ClipDetailView is created
                        let initialIndex = clips.firstIndex(where: { $0.id == initialClip.id })
                            ?? clips.firstIndex(where: { $0.localIdentifier == initialClip.localIdentifier })
                        if let initialIndex {
                            currentIndex = initialIndex
                            scrolledID = clips[initialIndex].id
                        } else {
                            // Fallback to first clip if not found
                            currentIndex = 0
                            scrolledID = clips.first?.id
                        }
                    }
            }
            
            // Stretchy back arrow indicator
            if isDragging && dragOffset > 10 {
                SwipeBackIndicator(progress: dragProgress, canDismiss: canDismiss)
                    .transition(.opacity)
            }
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    // Only track right-ward swipes from left edge (within 30pt)
                    if value.startLocation.x < 30 && value.translation.width > 0 {
                        if !isDragging {
                            isDragging = true
                        }
                        dragOffset = value.translation.width
                    }
                }
                .onEnded { value in
                    isDragging = false
                    // Dismiss if swiped far enough or with velocity
                    if dragOffset > 100 || value.predictedEndTranslation.width > 200 {
                        HapticManager.playLight()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            selectedClip = nil
                        }
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            dragOffset = 0
                        }
                    }
                }
        )
    }
    
    @ViewBuilder
    private func pagerContent(activeIndex: Int) -> some View {
        GeometryReader { geometry in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(clips.enumerated()), id: \.element.id) { index, clip in
                        ClipDetailView(
                            clip: clip,
                            namespace: namespace,
                            selectedClip: $selectedClip,
                            viewState: viewState,
                            isActive: index == activeIndex,
                            onReachedEnd: {
                                // Trigger bounce hint when clip ends
                            },
                            onClose: {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    selectedClip = nil
                                }
                            }
                        )
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .id(clip.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $scrolledID)
            .scrollDisabled(clips.count <= 1)
            .ignoresSafeArea()
            .onChange(of: scrolledID) { _, newID in
                if let newID = newID,
                   let newIndex = clips.firstIndex(where: { $0.id == newID }) {
                    if newIndex != currentIndex {
                        currentIndex = newIndex
                        HapticManager.playLight()
                    }
                }
            }
        }
        .background(Color.black)
        .ignoresSafeArea()
        .offset(x: dragOffset)
    }
}

// MARK: - Swipe Back Indicator

/// A stretchy arrow indicator that shows during edge swipe gesture
struct SwipeBackIndicator: View {
    let progress: CGFloat
    let canDismiss: Bool
    
    /// Size of the arrow circle based on progress
    private var circleSize: CGFloat {
        32 + (progress * 16) // 32 to 48
    }
    
    /// Arrow icon size
    private var arrowSize: CGFloat {
        14 + (progress * 4) // 14 to 18
    }
    
    /// Horizontal offset from left edge
    private var xOffset: CGFloat {
        -10 + (progress * 30) // Slides in from -10 to 20
    }
    
    var body: some View {
        ZStack {
            // Background pill/circle
            Capsule()
                .fill(canDismiss ? Color.white : Color.white.opacity(0.85))
                .frame(width: circleSize, height: circleSize)
                .shadow(color: .black.opacity(0.3), radius: 8, x: 2, y: 0)
            
            // Arrow icon
            Image(systemName: "chevron.left")
                .font(.system(size: arrowSize, weight: .bold))
                .foregroundStyle(canDismiss ? Color.black : Color.black.opacity(0.6))
                .scaleEffect(x: canDismiss ? 1.1 : 1.0, y: 1.0)
        }
        .offset(x: xOffset)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: canDismiss)
        .animation(.interactiveSpring(response: 0.15, dampingFraction: 0.8), value: progress)
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @Namespace private var namespace
        private let previewClip = ClipMetadata(
            id: UUID(),
            localIdentifier: "preview",
            title: "Preview Clip",
            transcript: "Preview transcript",
            topics: ["Preview"],
            capturedAt: Date(),
            duration: 30
        )
        @State private var selectedClip: ClipMetadata?
        
        var body: some View {
            ClipPagerView(
                clips: [previewClip],
                initialClip: previewClip,
                selectedClip: $selectedClip,
                viewState: GlobalViewState(),
                namespace: namespace
            )
            .onAppear {
                selectedClip = previewClip
            }
        }
    }
    
    return PreviewWrapper()
}
