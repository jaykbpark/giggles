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
