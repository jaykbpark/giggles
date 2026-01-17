import SwiftUI

// MARK: - Moment Card

struct MomentCard: View {
    let clip: ClipMetadata
    let isLeft: Bool
    let animationDelay: Double
    
    @State private var isAppeared = false
    @State private var isPressed = false
    
    var body: some View {
        HStack(spacing: 16) {
            if !isLeft {
                Spacer(minLength: 0)
            }
            
            // Card content
            cardContent
                .frame(maxWidth: 280)
                .background {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(AppColors.warmSurface)
                        .shadow(color: AppColors.cardShadow, radius: 16, y: 8)
                }
                .scaleEffect(isPressed ? 0.97 : 1.0)
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
        VStack(alignment: .leading, spacing: 12) {
            // Time and duration
            HStack {
                Text(clip.formattedTime)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.accent)
                
                Spacer()
                
                // Duration badge
                Text(clip.formattedDuration)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background {
                        Capsule()
                            .fill(AppColors.warmBackground)
                    }
            }
            
            // Transcript preview
            Text(clip.transcript)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(2)
                .lineSpacing(2)
            
            // Topics (if any)
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
                                    .stroke(AppColors.timelineLine, lineWidth: 1)
                            }
                    }
                    
                    if clip.topics.count > 2 {
                        Text("+\(clip.topics.count - 2)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
            }
        }
        .padding(16)
    }
}

// MARK: - Moment Card Button Style

struct MomentCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
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
