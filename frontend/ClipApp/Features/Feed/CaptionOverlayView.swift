import SwiftUI

/// A view that displays captions over video content, synchronized with playback time
struct CaptionOverlayView: View {
    let segments: [CaptionSegment]
    let currentTime: TimeInterval
    let style: CaptionStyle
    
    init(
        segments: [CaptionSegment],
        currentTime: TimeInterval,
        style: CaptionStyle = CaptionStyle()
    ) {
        self.segments = segments
        self.currentTime = currentTime
        self.style = style
    }
    
    /// The currently active caption segment
    private var activeSegment: CaptionSegment? {
        segments.first { $0.isActive(at: currentTime) }
    }
    
    var body: some View {
        GeometryReader { geometry in
            VStack {
                if style.position == .bottom {
                    Spacer()
                }
                
                if style.position == .center {
                    Spacer()
                }
                
                if let segment = activeSegment {
                    captionText(segment.text, in: geometry)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        .id(segment.id)
                }
                
                if style.position == .center {
                    Spacer()
                }
                
                if style.position == .top {
                    Spacer()
                }
            }
            .animation(.easeInOut(duration: 0.15), value: activeSegment?.id)
        }
    }
    
    @ViewBuilder
    private func captionText(_ text: String, in geometry: GeometryProxy) -> some View {
        Text(text)
            .font(.system(size: style.fontSize, weight: fontWeight))
            .foregroundStyle(Color(hex: style.textColor) ?? .white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill((Color(hex: style.backgroundColor) ?? .black).opacity(style.backgroundOpacity))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, style.position == .bottom ? 60 : 20)
            .padding(.top, style.position == .top ? 60 : 20)
            .frame(maxWidth: geometry.size.width * 0.9)
    }
    
    private var fontWeight: Font.Weight {
        switch style.fontWeight {
        case "regular": return .regular
        case "medium": return .medium
        case "semibold": return .semibold
        case "bold": return .bold
        default: return .semibold
        }
    }
}

// MARK: - Animated Caption View

/// A caption view with word-by-word animation (TikTok style)
struct AnimatedCaptionView: View {
    let segments: [CaptionSegment]
    let currentTime: TimeInterval
    let style: CaptionStyle
    
    init(
        segments: [CaptionSegment],
        currentTime: TimeInterval,
        style: CaptionStyle = CaptionStyle()
    ) {
        self.segments = segments
        self.currentTime = currentTime
        self.style = style
    }
    
    private var activeSegment: CaptionSegment? {
        segments.first { $0.isActive(at: currentTime) }
    }
    
    var body: some View {
        GeometryReader { geometry in
            VStack {
                if style.position == .bottom {
                    Spacer()
                }
                
                if style.position == .center {
                    Spacer()
                }
                
                if let segment = activeSegment {
                    animatedText(segment, in: geometry)
                        .id(segment.id)
                }
                
                if style.position == .center {
                    Spacer()
                }
                
                if style.position == .top {
                    Spacer()
                }
            }
        }
    }
    
    @ViewBuilder
    private func animatedText(_ segment: CaptionSegment, in geometry: GeometryProxy) -> some View {
        let words = segment.text.split(separator: " ").map(String.init)
        let wordDuration = segment.duration / Double(max(words.count, 1))
        let elapsedTime = currentTime - segment.startTime
        let currentWordIndex = Int(elapsedTime / wordDuration)
        
        HStack(spacing: 6) {
            ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                Text(word)
                    .font(.system(size: style.fontSize, weight: fontWeight))
                    .foregroundStyle(
                        index <= currentWordIndex
                            ? (Color(hex: style.textColor) ?? .white)
                            : (Color(hex: style.textColor) ?? .white).opacity(0.5)
                    )
                    .scaleEffect(index == currentWordIndex ? 1.1 : 1.0)
                    .animation(.spring(response: 0.2, dampingFraction: 0.7), value: currentWordIndex)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill((Color(hex: style.backgroundColor) ?? .black).opacity(style.backgroundOpacity))
        }
        .padding(.horizontal, 20)
        .padding(.bottom, style.position == .bottom ? 60 : 20)
        .frame(maxWidth: geometry.size.width * 0.9)
    }
    
    private var fontWeight: Font.Weight {
        switch style.fontWeight {
        case "regular": return .regular
        case "medium": return .medium
        case "semibold": return .semibold
        case "bold": return .bold
        default: return .semibold
        }
    }
}

// MARK: - Color Extension

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }
        
        let r, g, b, a: Double
        switch hexSanitized.count {
        case 6:
            r = Double((rgb & 0xFF0000) >> 16) / 255.0
            g = Double((rgb & 0x00FF00) >> 8) / 255.0
            b = Double(rgb & 0x0000FF) / 255.0
            a = 1.0
        case 8:
            r = Double((rgb & 0xFF000000) >> 24) / 255.0
            g = Double((rgb & 0x00FF0000) >> 16) / 255.0
            b = Double((rgb & 0x0000FF00) >> 8) / 255.0
            a = Double(rgb & 0x000000FF) / 255.0
        default:
            return nil
        }
        
        self.init(red: r, green: g, blue: b, opacity: a)
    }
}

// MARK: - Preview

#Preview("Static Captions") {
    ZStack {
        Color.black
        
        CaptionOverlayView(
            segments: [
                CaptionSegment(text: "Hello, this is a test caption", startTime: 0, endTime: 3),
                CaptionSegment(text: "And this is another one", startTime: 3, endTime: 6)
            ],
            currentTime: 1.5
        )
    }
}

#Preview("Animated Captions") {
    ZStack {
        Color.black
        
        AnimatedCaptionView(
            segments: [
                CaptionSegment(text: "Hello this is a test caption with animation", startTime: 0, endTime: 4)
            ],
            currentTime: 2.0
        )
    }
}
