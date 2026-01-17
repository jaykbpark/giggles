import SwiftUI

// MARK: - Launch Animation Phases

enum LaunchPhase: CaseIterable {
    case initial      // Warm background only
    case wordmark     // Logo fades in
    case transition   // Logo moves up
    case complete     // Hand off to main view
}

// MARK: - Launch View

struct LaunchView: View {
    @Binding var isComplete: Bool
    
    @State private var phase: LaunchPhase = .initial
    @State private var wordmarkOpacity: Double = 0
    @State private var wordmarkScale: CGFloat = 0.95
    @State private var wordmarkOffset: CGFloat = 0
    @State private var showTimeline: Bool = false
    
    var body: some View {
        ZStack {
            // Warm background
            AppColors.warmBackground
                .ignoresSafeArea()
            
            // Wordmark
            VStack(spacing: 4) {
                Text("clip")
                    .font(.system(size: 42, weight: .bold, design: .default))
                    .tracking(-1)
                    .foregroundStyle(AppColors.textPrimary)
                
                Text("your moments")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
                    .opacity(phase == .wordmark ? 1 : 0)
            }
            .scaleEffect(wordmarkScale)
            .opacity(wordmarkOpacity)
            .offset(y: wordmarkOffset)
        }
        .onAppear {
            startAnimation()
        }
    }
    
    private func startAnimation() {
        // Phase 1: Initial pause (0.2s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            // Phase 2: Wordmark fades in (0.3-0.8s)
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                phase = .wordmark
                wordmarkOpacity = 1
                wordmarkScale = 1.0
            }
        }
        
        // Phase 3: Wordmark moves up, prepare for transition (0.8-1.3s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) {
                phase = .transition
                wordmarkOffset = -60
            }
        }
        
        // Phase 4: Complete - hand off to main view (1.5s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                phase = .complete
                wordmarkOpacity = 0
            }
            
            // Small delay before completing
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isComplete = true
            }
        }
    }
}

// MARK: - Preview

#Preview {
    LaunchView(isComplete: .constant(false))
}
