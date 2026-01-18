import SwiftUI

#if canImport(SmartSpectraSwiftSDK)
import SmartSpectraSwiftSDK
#endif

struct StateView: View {
    @ObservedObject var viewState: GlobalViewState
    @ObservedObject var presageService: PresageService

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                liveStateCard

                sectionHeader("Today's State Summary")
                summaryCard

                sectionHeader("Moments That Matter")
                momentsCard

                sectionHeader("Emotion Timeline")
                emotionTimeline
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 80)
        }
        .background {
#if canImport(SmartSpectraSwiftSDK)
            SmartSpectraView()
                .frame(width: 1, height: 1)
                .opacity(0.001)
                .accessibilityHidden(true)
#endif
        }
    }

    private var liveStateCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(liveStateDot)
                    .frame(width: 8, height: 8)
                Text("Live")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)
            }

            if let state = presageService.currentState {
                Text(state.stateSummary)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
            } else {
                Text("Waiting for Presage signals")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppColors.warmSurface)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(AppColors.timelineLine.opacity(0.4), lineWidth: 1)
                }
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            StateMetricRow(title: "Stress", value: averageStress, accent: stateColor(for: averageStress))
            StateMetricRow(title: "Focus", value: averageFocus, accent: AppColors.accent)

            HStack {
                Text("Dominant emotion")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
                Spacer()
                Text(dominantEmotion)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppColors.warmSurface)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(AppColors.timelineLine.opacity(0.4), lineWidth: 1)
                }
        }
    }

    private var momentsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if highlightClips.isEmpty {
                Text("Capture more moments to see meaningful state shifts.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
            } else {
                ForEach(highlightClips, id: \.id) { clip in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(stateColor(for: clip.clipState?.stressLevel ?? 0))
                            .frame(width: 8, height: 8)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(clip.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(AppColors.textPrimary)
                                .lineLimit(1)
                            if let state = clip.clipState {
                                Text(state.stateSummary)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(AppColors.textSecondary)
                                    .lineLimit(1)
                            }
                        }

                        Spacer()

                        Text(clip.formattedTime)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppColors.warmSurface)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(AppColors.timelineLine.opacity(0.4), lineWidth: 1)
                }
        }
    }

    private var emotionTimeline: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(emotionChips, id: \.id) { chip in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(stateColor(for: chip.stress))
                            .frame(width: 6, height: 6)
                        Text("\(chip.emotion) · \(chip.time)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background {
                        Capsule()
                            .stroke(AppColors.timelineLine.opacity(0.5), lineWidth: 1)
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(AppColors.textSecondary)
    }

    private var liveStateDot: Color {
        guard let state = presageService.currentState else {
            return AppColors.textSecondary.opacity(0.4)
        }
        return stateColor(for: state.stressLevel)
    }

    private var todayStates: [ClipState] {
        viewState.clips.compactMap { clip in
            guard Calendar.current.isDateInToday(clip.capturedAt) else { return nil }
            return clip.clipState
        }
    }

    private var averageStress: Double {
        guard !todayStates.isEmpty else { return 0.3 }
        let total = todayStates.reduce(0) { $0 + $1.stressLevel }
        return total / Double(todayStates.count)
    }

    private var averageFocus: Double {
        guard !todayStates.isEmpty else { return 0.5 }
        let total = todayStates.reduce(0) { $0 + $1.focusLevel }
        return total / Double(todayStates.count)
    }

    private var dominantEmotion: String {
        let emotions = todayStates.map { $0.emotionLabel }
        guard !emotions.isEmpty else { return "Unknown" }
        return emotions.reduce(into: [:]) { counts, emotion in
            counts[emotion, default: 0] += 1
        }
        .max { $0.value < $1.value }?
        .key ?? "Unknown"
    }

    private var highlightClips: [ClipMetadata] {
        viewState.clips
            .filter { $0.clipState != nil }
            .sorted { lhs, rhs in
                let leftScore = max(lhs.clipState?.stressLevel ?? 0, lhs.clipState?.focusLevel ?? 0)
                let rightScore = max(rhs.clipState?.stressLevel ?? 0, rhs.clipState?.focusLevel ?? 0)
                return leftScore > rightScore
            }
            .prefix(3)
            .map { $0 }
    }

    private var emotionChips: [EmotionChip] {
        viewState.clips
            .filter { $0.clipState != nil }
            .prefix(8)
            .compactMap { clip in
                guard let state = clip.clipState else { return nil }
                return EmotionChip(
                    id: clip.id,
                    emotion: state.emotionLabel,
                    time: clip.formattedTime,
                    stress: state.stressLevel
                )
            }
    }

    private func stateColor(for stress: Double) -> Color {
        switch stress {
        case 0..<0.34:
            return Color.green.opacity(0.75)
        case 0.34..<0.67:
            return Color.orange.opacity(0.8)
        default:
            return Color.red.opacity(0.8)
        }
    }
}

private struct EmotionChip: Identifiable {
    let id: UUID
    let emotion: String
    let time: String
    let stress: Double
}

private struct StateMetricRow: View {
    let title: String
    let value: Double
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
                Spacer()
                Text("\(Int(value * 100))%")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
            }
            ProgressView(value: value)
                .tint(accent)
        }
    }
}
