import Foundation

struct MockData {
    static let clips: [ClipMetadata] = [
        ClipMetadata(
            id: UUID(),
            localIdentifier: "mock-001",
            title: "Coffee with Sarah",
            transcript: "Hey! It's been so long. How's the new job going? I heard you got promoted. That's amazing! We should definitely do dinner next week. Maybe that new Italian place on Main Street?",
            topics: ["coffee", "friends", "catch-up"],
            capturedAt: Date().addingTimeInterval(-2 * 3600),
            duration: 58,
            isStarred: true,
            context: ClipContext(
                calendarTitle: "Coffee catch-up",
                locationName: "Cafe Luna",
                weatherSummary: "72°F"
            ),
            clipState: ClipState(stressLevel: 0.25, focusLevel: 0.45, emotionLabel: "Calm")
        ),
        ClipMetadata(
            id: UUID(),
            localIdentifier: "mock-002",
            title: "Hackathon Demo",
            transcript: "So what we built is an AI-powered clip search. You can say things like 'show me when we talked about the sunset' and it finds the exact moment. The judges were really impressed with the semantic understanding.",
            topics: ["coding", "hackathon", "demo"],
            capturedAt: Date().addingTimeInterval(-5 * 3600),
            duration: 60,
            isStarred: true,
            context: ClipContext(
                calendarTitle: "Demo Day",
                locationName: "Main Hall",
                weatherSummary: "68°F"
            ),
            clipState: ClipState(stressLevel: 0.6, focusLevel: 0.82, emotionLabel: "Focused")
        ),
        ClipMetadata(
            id: UUID(),
            localIdentifier: "mock-003",
            title: "Sunset at the Beach",
            transcript: "Look at those colors. The way the light hits the mountains is incredible. I could watch this every day. This is why I love living here.",
            topics: ["nature", "sunset", "relaxing"],
            capturedAt: Date().addingTimeInterval(-24 * 3600),
            duration: 55,
            context: ClipContext(
                calendarTitle: nil,
                locationName: "Ocean Point",
                weatherSummary: "Golden hour"
            ),
            clipState: ClipState(stressLevel: 0.12, focusLevel: 0.4, emotionLabel: "Peaceful")
        ),
        ClipMetadata(
            id: UUID(),
            localIdentifier: "mock-004",
            title: "Team Standup",
            transcript: "Alright, quick sync. I finished the auth module yesterday. Today I'm picking up the notification system. Any blockers? No? Great, let's ship it.",
            topics: ["work", "meeting", "engineering"],
            capturedAt: Date().addingTimeInterval(-26 * 3600),
            duration: 42,
            context: ClipContext(
                calendarTitle: "Daily Standup",
                locationName: "Studio A",
                weatherSummary: nil
            ),
            clipState: ClipState(stressLevel: 0.55, focusLevel: 0.66, emotionLabel: "Alert")
        ),
        ClipMetadata(
            id: UUID(),
            localIdentifier: "mock-005",
            title: "Street Performance",
            transcript: "Oh wow, listen to that saxophone. This is incredible. These guys are so talented. We should tip them. Do you have any cash?",
            topics: ["music", "street", "jazz"],
            capturedAt: Date().addingTimeInterval(-48 * 3600),
            duration: 60,
            context: ClipContext(
                calendarTitle: nil,
                locationName: "Market Street",
                weatherSummary: "Breezy"
            ),
            clipState: ClipState(stressLevel: 0.35, focusLevel: 0.5, emotionLabel: "Happy")
        ),
        ClipMetadata(
            id: UUID(),
            localIdentifier: "mock-006",
            title: "Morning Run",
            transcript: "Mile three, feeling good. Heart rate's around 145. The trail is pretty empty today. Perfect running weather.",
            topics: ["fitness", "running", "outdoors"],
            capturedAt: Date().addingTimeInterval(-72 * 3600),
            duration: 45,
            context: ClipContext(
                calendarTitle: nil,
                locationName: "Riverside Trail",
                weatherSummary: "Cool morning"
            ),
            clipState: ClipState(stressLevel: 0.7, focusLevel: 0.62, emotionLabel: "Energized")
        )
    ]
}
