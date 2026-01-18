import SwiftUI

// MARK: - Warm Minimal Color System

enum AppColors {
    // Backgrounds
    static let background = Color("Background", bundle: nil)
    static let surface = Color("Surface", bundle: nil)
    
    // With fallbacks for when asset catalog isn't set up
    static let warmBackground = Color(red: 0.98, green: 0.976, blue: 0.969) // #FAF9F7
    static let warmSurface = Color(red: 0.961, green: 0.953, blue: 0.941)   // #F5F3F0
    
    // Text
    static let textPrimary = Color(red: 0.173, green: 0.157, blue: 0.145)   // #2C2825
    static let textSecondary = Color(red: 0.541, green: 0.518, blue: 0.49)  // #8A847D
    
    // Accent
    static let accent = Color(red: 0.91, green: 0.365, blue: 0.298)         // #E85D4C
    
    // Timeline
    static let timelineLine = Color(red: 0.878, green: 0.863, blue: 0.839)  // #E0DCD6
    static let timelineNode = Color(red: 0.91, green: 0.365, blue: 0.298)   // #E85D4C
    
    // Status
    static let connected = Color(red: 0.30, green: 0.75, blue: 0.45)        // Softer green
    
    // Shadows
    static let cardShadow = Color.black.opacity(0.06)
    
    // Card backgrounds
    static let cardBackground = Color(red: 0.95, green: 0.94, blue: 0.92)     // Light warm gray
    
    // Legacy compatibility
    static let glass = Material.ultraThinMaterial
}

// MARK: - Accent Colors (Legacy support)

enum AppAccents {
    static let primary = AppColors.accent
    static let secondary = Color(red: 0.95, green: 0.50, blue: 0.40)
    static let warm = Color(red: 0.98, green: 0.65, blue: 0.45)
    static let connected = AppColors.connected
}
