import SwiftUI

enum AppTypography {
    static let heroHeader = Font.system(size: 34, weight: .bold, design: .default)
    static let cardTitle = Font.system(size: 18, weight: .semibold, design: .rounded)
    static let body = Font.system(size: 16, weight: .regular, design: .default)
    static let metadata = Font.system(size: 14, weight: .medium, design: .monospaced)
    static let status = Font.system(size: 12, weight: .bold, design: .monospaced)
}

enum AppLayout {
    static let padding: CGFloat = 20
    static let cardRadius: CGFloat = 16
    static let searchPillRadius: CGFloat = 30
}
