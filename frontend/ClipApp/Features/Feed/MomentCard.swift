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
                .background {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(AppColors.warmSurface)
                        .overlay {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(AppColors.timelineLine.opacity(0.4), lineWidth: 1)
                        }
                }
                .opacity(isAppeared ? 1 : 0)
                .offset(x: isAppeared ? 0 : (isLeft ? -20 : 20))
                .rotationEffect(isAppeared ? .degrees(0) : .degrees(isLeft ? -1 : 1))
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(animationDelay), value: isAppeared)
            
            if isLeft {
                Spacer(minLength: 0)
            }
        }
        .onAppear {
            isAppeared = true
        }
        .accessibilityLabel("\(clip.title), \(clip.formattedTime)")
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
                    .overlay {
                        LinearGradient(
                            colors: [.clear, Color.black.opacity(0.25)],
                            startPoint: .center,
                            endPoint: .bottom
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                
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
            .overlay(alignment: .topTrailing) {
                if clip.isStarred {
                    Image(systemName: "star.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppColors.accent)
                        .padding(6)
                        .background(.black.opacity(0.35), in: Circle())
                        .padding(6)
                }
            }
            
            // Date pill + Time
            HStack(spacing: 8) {
                Text(clip.dateGroupKey)
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
            }

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
                                    .stroke(AppColors.timelineLine.opacity(0.6), lineWidth: 1)
                            }
                    }
                    
                    if clip.topics.count > 3 {
                        Text("+\(clip.topics.count - 3)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            if let context = clip.context {
                contextRow(context)
            }
        }
        .padding(10)
    }

    @ViewBuilder
    private func contextRow(_ context: ClipContext) -> some View {
        HStack(spacing: 8) {
            if let calendarTitle = context.calendarTitle {
                Label(calendarTitle, systemImage: "calendar")
            }
            if let locationName = context.locationName {
                Label(locationName, systemImage: "mappin.and.ellipse")
            }
            if let weatherSummary = context.weatherSummary {
                Label(weatherSummary, systemImage: "cloud.sun")
            }
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(AppColors.textSecondary)
        .lineLimit(1)
    }

}

// MARK: - Moment Card Button Style

struct MomentCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .shadow(
                color: AppColors.cardShadow,
                radius: configuration.isPressed ? 6 : 14,
                y: configuration.isPressed ? 3 : 8
            )
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        AppColors.warmBackground.ignoresSafeArea()
        
        let previewClip1 = ClipMetadata(
            id: UUID(),
            localIdentifier: "preview-1",
            title: "Preview Clip",
            transcript: "Preview transcript",
            topics: ["Preview"],
            capturedAt: Date(),
            duration: 30
        )
        let previewClip2 = ClipMetadata(
            id: UUID(),
            localIdentifier: "preview-2",
            title: "Second Preview",
            transcript: "Preview transcript",
            topics: ["Preview"],
            capturedAt: Date(),
            duration: 24
        )
        
        VStack(spacing: 24) {
            MomentCard(
                clip: previewClip1,
                isLeft: true,
                animationDelay: 0
            )
            
            MomentCard(
                clip: previewClip2,
                isLeft: false,
                animationDelay: 0.1
            )
        }
        .padding()
    }
}
