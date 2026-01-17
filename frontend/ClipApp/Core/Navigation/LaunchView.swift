import SwiftUI

struct LaunchView: View {
    @Binding var isComplete: Bool
    
    @State private var logoOpacity: Double = 0
    @State private var logoScale: CGFloat = 0.8
    @State private var dotScale: CGFloat = 0
    @State private var ringScale: CGFloat = 0.5
    @State private var ringOpacity: Double = 0
    @State private var backgroundShift = false
    
    var body: some View {
        ZStack {
            // Warm background
            LinearGradient(
                colors: [
                    AppColors.warmBackground,
                    AppColors.warmSurface
                ],
                startPoint: backgroundShift ? .topLeading : .top,
                endPoint: backgroundShift ? .bottomTrailing : .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 20) {
                // Animated logo mark
                ZStack {
                    // Expanding ring
                    Circle()
                        .stroke(AppColors.accent.opacity(0.3), lineWidth: 2)
                        .frame(width: 80, height: 80)
                        .scaleEffect(ringScale)
                        .opacity(ringOpacity)
                    
                    // Center dot
                    Circle()
                        .fill(AppColors.accent)
                        .frame(width: 16, height: 16)
                        .scaleEffect(dotScale)
                }
                .frame(width: 80, height: 80)
                
                // Wordmark
                Text("clip")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(AppColors.textPrimary)
            }
            .opacity(logoOpacity)
            .scaleEffect(logoScale)
        }
        .onAppear {
            startAnimation()
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                backgroundShift = true
            }
        }
    }
    
    private func startAnimation() {
        // Fade in logo
        withAnimation(.easeOut(duration: 0.4)) {
            logoOpacity = 1
            logoScale = 1
        }
        
        // Pop in dot
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6).delay(0.2)) {
            dotScale = 1
        }
        
        // Expand ring
        withAnimation(.easeOut(duration: 0.6).delay(0.3)) {
            ringScale = 1.2
            ringOpacity = 1
        }
        
        // Fade out ring
        withAnimation(.easeIn(duration: 0.3).delay(0.7)) {
            ringOpacity = 0
        }
        
        // Complete after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeOut(duration: 0.25)) {
                logoOpacity = 0
                logoScale = 1.05
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                HapticManager.playLight()
                isComplete = true
            }
        }
    }
}

#Preview {
    LaunchView(isComplete: .constant(false))
}
