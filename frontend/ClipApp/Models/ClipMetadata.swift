import Foundation

struct ClipMetadata: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let localIdentifier: String
    let title: String
    let transcript: String
    let topics: [String]
    let capturedAt: Date
    let duration: TimeInterval

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
