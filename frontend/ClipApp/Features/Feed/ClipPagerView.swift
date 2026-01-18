import SwiftUI

/// A vertical paging container for browsing clips TikTok/Reels style
struct ClipPagerView: View {
    let clips: [ClipMetadata]
    let initialClip: ClipMetadata
    @Binding var selectedClip: ClipMetadata?
    @ObservedObject var viewState: GlobalViewState
    var namespace: Namespace.ID
    
    @State private var currentIndex: Int = 0
    @State private var scrolledID: UUID?
    @State private var dragOffset: CGFloat = 0
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(clips.enumerated()), id: \.element.id) { index, clip in
                        ClipDetailView(
                            clip: clip,
                            namespace: namespace,
                            selectedClip: $selectedClip,
                            viewState: viewState,
                            isActive: index == currentIndex,
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
            .onAppear {
                // Set initial scroll position
                if let initialIndex = clips.firstIndex(where: { $0.id == initialClip.id }) {
                    currentIndex = initialIndex
                    scrolledID = initialClip.id
                }
            }
        }
        .background(Color.black)
        .ignoresSafeArea()
        .offset(x: dragOffset)
        .gesture(
            DragGesture()
                .onChanged { value in
                    // Only track right-ward swipes from left edge (within 30pt)
                    if value.startLocation.x < 30 && value.translation.width > 0 {
                        dragOffset = value.translation.width
                    }
                }
                .onEnded { value in
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
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @Namespace private var namespace
        @State private var selectedClip: ClipMetadata? = MockData.clips[0]
        
        var body: some View {
            ClipPagerView(
                clips: MockData.clips,
                initialClip: MockData.clips[0],
                selectedClip: $selectedClip,
                viewState: GlobalViewState(),
                namespace: namespace
            )
        }
    }
    
    return PreviewWrapper()
}
