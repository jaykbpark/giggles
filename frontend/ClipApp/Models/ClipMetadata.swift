import Foundation

// MARK: - ClipState (Placeholder - will be shared with Presage integration)

/// Human state data from Presage (stress, focus, emotion).
/// This is a placeholder that will be moved to a shared Models file when Presage is integrated.
struct ClipState: Codable, Hashable, Sendable {
    let stressLevel: Double // 0-1
    let focusLevel: Double // 0-1
    let emotionLabel: String // e.g., "Calm", "Happy", "Anxious"

    var stressLabel: String {
        switch stressLevel {
        case 0..<0.34: return "Low Stress"
        case 0.34..<0.67: return "Moderate Stress"
        default: return "High Stress"
        }
    }

    var focusLabel: String {
        switch focusLevel {
        case 0..<0.34: return "Low Focus"
        case 0.34..<0.67: return "Focused"
        default: return "Deep Focus"
        }
    }

    var stateSummary: String {
        "\(emotionLabel) · \(focusLabel) · \(stressLabel)"
    }
}

struct ClipMetadata: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let localIdentifier: String
    var title: String
    let transcript: String
    let topics: [String]
    let capturedAt: Date
    let duration: TimeInterval
    var isStarred: Bool = false
    var context: ClipContext? = nil
    var audioNarrationURL: String? = nil // URL to cached ElevenLabs audio narration
    var clipState: ClipState? = nil // Presage state data (optional)

    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: capturedAt)
    }
    
    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: capturedAt)
    }

    var relativeDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: capturedAt, relativeTo: Date())
    }

    var dateGroupKey: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(capturedAt) {
            return "Today"
        } else if calendar.isDateInYesterday(capturedAt) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE, MMM d"
            return formatter.string(from: capturedAt)
        }
    }
}

struct ClipContext: Codable, Hashable, Sendable {
    let calendarTitle: String?
    let locationName: String?
    let weatherSummary: String?
}
