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

// MARK: - CaptionSegment

/// A timed caption segment for displaying captions during playback
struct CaptionSegment: Codable, Hashable, Sendable, Identifiable {
    var id: UUID = UUID()
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    
    /// Duration of this caption segment
    var duration: TimeInterval {
        endTime - startTime
    }
    
    /// Check if this segment should be displayed at the given time
    func isActive(at time: TimeInterval) -> Bool {
        time >= startTime && time < endTime
    }
}

// MARK: - CaptionStyle

/// Style configuration for caption display
struct CaptionStyle: Codable, Hashable, Sendable {
    var fontSize: CGFloat = 18
    var fontWeight: String = "semibold"  // "regular", "medium", "semibold", "bold"
    var textColor: String = "#FFFFFF"
    var backgroundColor: String = "#000000"
    var backgroundOpacity: Double = 0.7
    var position: CaptionPosition = .bottom
    
    enum CaptionPosition: String, Codable, Hashable, Sendable {
        case top
        case center
        case bottom
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
    
    // Caption support
    var captionSegments: [CaptionSegment]? = nil // Timed caption chunks
    var showCaptions: Bool = true // User preference for showing captions
    var captionStyle: CaptionStyle? = nil // Custom caption styling

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
