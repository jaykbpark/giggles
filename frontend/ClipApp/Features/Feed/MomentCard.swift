import SwiftUI

// MARK: - Moment Card

struct MomentCard: View {
    let clip: ClipMetadata
    let isLeft: Bool
    let animationDelay: Double
    
    @State private var isAppeared = false
    
    var body: some View {
        HStack(spacing: 16) {
            if !isLeft {
                Spacer(minLength: 0)
            }
            
            // Card content with glass
            cardContent
                .frame(maxWidth: 260)
                .glassEffect(in: .rect(cornerRadius: 20))
                .opacity(isAppeared ? 1 : 0)
                .offset(x: isAppeared ? 0 : (isLeft ? -20 : 20))
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(animationDelay), value: isAppeared)
            
            if isLeft {
                Spacer(minLength: 0)
            }
        }
        .onAppear {
            isAppeared = true
        }
    }
    
    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Video thumbnail placeholder
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(.systemGray5), Color(.systemGray4)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 120)
                
                // Play icon
                Image(systemName: "play.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.white.opacity(0.8))
                
                // Duration badge overlay
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text(clip.formattedDuration)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background {
                                Capsule()
                                    .fill(.black.opacity(0.6))
                            }
                            .padding(8)
                    }
                }
            }
            
            // Time
            Text(clip.formattedTime)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppColors.accent)

            // Title
            Text(clip.title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(2)
            
            // Topics (if any)
            if !clip.topics.isEmpty {
                HStack(spacing: 6) {
                    ForEach(clip.topics.prefix(3), id: \.self) { topic in
                        Text(topic)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background {
                                Capsule()
                                    .stroke(.quaternary, lineWidth: 1)
                            }
                    }
                    
                    if clip.topics.count > 3 {
                        Text("+\(clip.topics.count - 3)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(10)
    }
}

// MARK: - Moment Card Button Style

struct MomentCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        AppColors.warmBackground.ignoresSafeArea()
        
        VStack(spacing: 24) {
            MomentCard(
                clip: MockData.clips[0],
                isLeft: true,
                animationDelay: 0
            )
            
            MomentCard(
                clip: MockData.clips[1],
                isLeft: false,
                animationDelay: 0.1
            )
        }
        .padding()
    }
}
