import UIKit

enum HapticManager {
    private static let impact = UIImpactFeedbackGenerator(style: .rigid)
    private static let lightImpact = UIImpactFeedbackGenerator(style: .soft)
    private static let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)

    static func playSuccess() {
        impact.prepare()
        impact.impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            impact.impactOccurred()
        }
    }

    static func playLight() {
        lightImpact.prepare()
        lightImpact.impactOccurred()
    }

    static func playError() {
        heavyImpact.prepare()
        for i in 0..<3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.1) {
                heavyImpact.impactOccurred()
            }
        }
    }
}
