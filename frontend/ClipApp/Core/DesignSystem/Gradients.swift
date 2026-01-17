import SwiftUI

// MARK: - Signature Gradients

enum AppGradients {
    // Primary brand gradient - Ray-Ban inspired warm tones
    static let brand = LinearGradient(
        colors: [
            Color(red: 0.91, green: 0.30, blue: 0.24),  // Ray-Ban Red
            Color(red: 0.95, green: 0.45, blue: 0.35),  // Warm Coral
            Color(red: 0.98, green: 0.60, blue: 0.40)   // Sunset Orange
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // Subtle ambient gradient for backgrounds
    static let ambient = LinearGradient(
        colors: [
            Color(red: 0.12, green: 0.12, blue: 0.14),
            Color(red: 0.08, green: 0.08, blue: 0.10)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    // Glass tint for overlays
    static let glassTint = LinearGradient(
        colors: [
            Color.white.opacity(0.15),
            Color.white.opacity(0.05)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // Card overlay gradient
    static let cardOverlay = LinearGradient(
        colors: [
            Color.black.opacity(0),
            Color.black.opacity(0.5)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    // Metallic ring effect
    static let metallicRing = AngularGradient(
        colors: [
            Color(white: 0.9),
            Color(white: 0.6),
            Color(white: 0.85),
            Color(white: 0.5),
            Color(white: 0.9)
        ],
        center: .center
    )

    // Status glow
    static let connectedGlow = RadialGradient(
        colors: [
            Color.green.opacity(0.6),
            Color.green.opacity(0)
        ],
        center: .center,
        startRadius: 0,
        endRadius: 20
    )
}

// MARK: - Accent Colors

enum AppAccents {
    static let primary = Color(red: 0.91, green: 0.30, blue: 0.24)
    static let secondary = Color(red: 0.95, green: 0.45, blue: 0.35)
    static let warm = Color(red: 0.98, green: 0.60, blue: 0.40)
    static let connected = Color(red: 0.30, green: 0.85, blue: 0.45)
}
