import SwiftUI

// MARK: - Timeline View

struct TimelineView: View {
    let clips: [ClipMetadata]
    let isLoading: Bool
    @Binding var selectedClip: ClipMetadata?
    var namespace: Namespace.ID
    
    @State private var timelineAppeared = false
    @State private var emptyFloat = false
    
    var body: some View {
        if isLoading {
            loadingState
        } else if clips.isEmpty {
            emptyState
        } else {
            timelineContent
        }
    }
    
    // MARK: - Loading State
    
    private var loadingState: some View {
        VStack(spacing: 32) {
            ForEach(0..<4, id: \.self) { index in
                HStack(spacing: 16) {
                    if index % 2 == 0 {
                        skeletonCard
                        Spacer(minLength: 60)
                    } else {
                        Spacer(minLength: 60)
                        skeletonCard
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 40)
    }
    
    private var skeletonCard: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(AppColors.warmSurface)
            .frame(maxWidth: 280, minHeight: 100)
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(AppColors.timelineLine.opacity(0.4), lineWidth: 1)
            }
            .shimmering()
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 28) {
            Spacer()
            
            // Illustration container
            ZStack {
                Circle()
                    .fill(AppColors.warmSurface)
                    .frame(width: 120, height: 120)
                    .shadow(color: AppColors.cardShadow, radius: 12, y: 6)
                
                Image(systemName: "waveform")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.secondary)
            }
            .offset(y: emptyFloat ? -6 : 6)
            .animation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true), value: emptyFloat)
            
            VStack(spacing: 10) {
                Text("No moments yet")
                    .font(.system(size: 24, weight: .semibold))

                Text("Say \"Clip that\" while wearing your\nglasses to capture a moment")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
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
    
    // MARK: - Timeline Content
    
    private var timelineContent: some View {
        ScrollView {
            ZStack(alignment: .top) {
                // Timeline line
                timelineLine
                
                // Content
                LazyVStack(spacing: 0) {
                    ForEach(Array(clips.enumerated()), id: \.element.id) { index, clip in
                        let isLeft = index % 2 == 0
                        
                        TimelineMoment(
                            clip: clip,
                            isLeft: isLeft,
                            animationDelay: Double(index) * 0.08,
                            namespace: namespace
                        ) {
                            HapticManager.playLight()
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                selectedClip = clip
                            }
                        }
                    }
                }
                .padding(.top, 20)
            }
            .padding(.bottom, 140) // Extra padding for floating toolbar
        }
        .scrollIndicators(.hidden)
    }
    
    // MARK: - Timeline Line
    
    private var timelineLine: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            AppColors.timelineLine.opacity(0.2),
                            AppColors.timelineLine
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 2)
                .frame(maxHeight: .infinity)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
                .opacity(timelineAppeared ? 1 : 0)
                .scaleEffect(y: timelineAppeared ? 1 : 0, anchor: .top)
                .animation(.spring(response: 0.8, dampingFraction: 0.7).delay(0.2), value: timelineAppeared)
        }
        .onAppear {
            timelineAppeared = true
        }
    }
    
}

// MARK: - Timeline Moment

struct TimelineMoment: View {
    let clip: ClipMetadata
    let isLeft: Bool
    let animationDelay: Double
    var namespace: Namespace.ID
    let onTap: () -> Void
    
    @State private var isAppeared = false
    
    var body: some View {
        HStack(spacing: 0) {
            if !isLeft {
                Spacer(minLength: 0)
            }
            
            // Node on timeline
            if !isLeft {
                timelineNode
                    .padding(.trailing, 16)
            }
            
            // Card
            Button(action: onTap) {
                MomentCard(
                    clip: clip,
                    isLeft: isLeft,
                    animationDelay: animationDelay
                )
            }
            .buttonStyle(MomentCardButtonStyle())
            .matchedGeometryEffect(id: clip.id, in: namespace)
            
            // Node on timeline
            if isLeft {
                timelineNode
                    .padding(.leading, 16)
            }
            
            if isLeft {
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
    
    private var timelineNode: some View {
        ZStack {
            // Outer ring
            Circle()
                .stroke(AppColors.timelineLine.opacity(0.8), lineWidth: 1)
                .frame(width: 18, height: 18)
            
            // Accent center dot
            Circle()
                .fill(AppColors.accent)
                .frame(width: 7, height: 7)
                .opacity(isAppeared ? 1 : 0)
                .scaleEffect(isAppeared ? 1 : 0)
                .animation(.spring(response: 0.4, dampingFraction: 0.6).delay(animationDelay + 0.1), value: isAppeared)
        }
        .onAppear {
            isAppeared = true
        }
    }
}

// MARK: - Shimmer Effect

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0
    
    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { geo in
                    LinearGradient(
                        colors: [
                            .clear,
                            .white.opacity(0.2),
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 2)
                    .offset(x: -geo.size.width + phase * geo.size.width * 2)
                }
                .mask(content)
            }
            .onAppear {
                withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

extension View {
    func shimmering() -> some View {
        modifier(ShimmerModifier())
    }
}

// MARK: - Preview

struct TimelineViewPreview: View {
    @Namespace private var namespace
    
    var body: some View {
        ZStack {
            AppColors.warmBackground.ignoresSafeArea()
            
            TimelineView(
                clips: MockData.clips,
                isLoading: false,
                selectedClip: .constant(nil),
                namespace: namespace
            )
        }
    }
}

#Preview {
    TimelineViewPreview()
}
