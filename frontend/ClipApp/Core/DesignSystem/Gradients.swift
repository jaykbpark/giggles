import SwiftUI

// MARK: - Warm Minimal Gradients

enum AppGradients {
    // Subtle warm gradient for backgrounds
    static let warmAmbient = LinearGradient(
        colors: [
            AppColors.warmBackground,
            AppColors.warmSurface
        ],
        startPoint: .top,
        endPoint: .bottom
    )
    
    // Card hover/press state
    static let cardPressed = LinearGradient(
        colors: [
            AppColors.warmSurface,
            AppColors.warmSurface.opacity(0.8)
        ],
        startPoint: .top,
        endPoint: .bottom
    )
    
    // Timeline fade for scroll edges
    static let timelineFadeTop = LinearGradient(
        colors: [
            AppColors.warmBackground,
            AppColors.warmBackground.opacity(0)
        ],
        startPoint: .top,
        endPoint: .bottom
    )
    
    static let timelineFadeBottom = LinearGradient(
        colors: [
            AppColors.warmBackground.opacity(0),
            AppColors.warmBackground
        ],
        startPoint: .top,
        endPoint: .bottom
    )
    
    // Accent gradient for special elements
    static let accent = LinearGradient(
        colors: [
            AppColors.accent,
            AppColors.accent.opacity(0.85)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    // Disabled state gradient (greyed out)
    static let disabled = LinearGradient(
        colors: [
            Color.gray.opacity(0.4),
            Color.gray.opacity(0.3)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Legacy Support

extension AppGradients {
    static let brand = LinearGradient(
        colors: [
            AppAccents.primary,
            AppAccents.secondary,
            AppAccents.warm
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    static let glassTint = LinearGradient(
        colors: [
            Color.white.opacity(0.08),
            Color.white.opacity(0.02)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
