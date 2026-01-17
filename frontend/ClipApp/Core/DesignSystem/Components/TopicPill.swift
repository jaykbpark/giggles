import SwiftUI

struct TopicPill: View {
    let topic: String
    var isSelected: Bool = false
    var action: (() -> Void)? = nil

    var body: some View {
        Button {
            action?()
        } label: {
            Text(topic)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(isSelected ? .white : .primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(Color.accentColor)
                    } else {
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .glassEffect(in: .capsule)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

struct TopicRow: View {
    let topics: [String]
    var selectedTopic: String? = nil
    var onSelect: ((String) -> Void)? = nil

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(topics, id: \.self) { topic in
                    TopicPill(
                        topic: topic,
                        isSelected: topic == selectedTopic
                    ) {
                        onSelect?(topic)
                    }
                }
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        TopicRow(topics: ["coffee", "friends", "catch-up"])
        TopicRow(topics: ["coding", "hackathon"], selectedTopic: "coding")
    }
    .padding()
}
