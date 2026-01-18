import SwiftUI

struct LaunchView: View {
    @Binding var isComplete: Bool
    
    // Logo animation states
    @State private var logoOpacity: Double = 0
    @State private var logoScale: CGFloat = 0.3
    @State private var logoRotation: Double = -30
    
    // Center dot states
    @State private var dotScale: CGFloat = 0
    @State private var dotGlow: CGFloat = 0
    
    // Ring states
    @State private var rings: [RingState] = []
    
    // Letter animation states
    @State private var letterOffsets: [CGFloat] = [50, 50, 50, 50]
    @State private var letterOpacities: [Double] = [0, 0, 0, 0]
    @State private var letterScales: [CGFloat] = [0.5, 0.5, 0.5, 0.5]
    
    // Particle states
    @State private var particles: [Particle] = []
    @State private var showParticles = false
    
    // Background states
    @State private var backgroundHue: Double = 0
    @State private var gradientRotation: Double = 0
    
    // Final burst
    @State private var burstScale: CGFloat = 0
    @State private var burstOpacity: Double = 0
    
    private let letters = ["c", "l", "i", "p"]
    
    var body: some View {
        ZStack {
            // Animated gradient background
            AngularGradient(
                colors: [
                    AppColors.warmBackground,
                    AppColors.warmSurface,
                    AppColors.warmBackground.opacity(0.9),
                    Color(red: 0.95, green: 0.93, blue: 0.90),
                    AppColors.warmBackground
                ],
                center: .center,
                angle: .degrees(gradientRotation)
            )
            .ignoresSafeArea()
            .blur(radius: 60)
            
            // Subtle radial overlay
            RadialGradient(
                colors: [
                    AppColors.accent.opacity(0.08),
                    .clear
                ],
                center: .center,
                startRadius: 50,
                endRadius: 300
            )
            .ignoresSafeArea()
            .scaleEffect(1 + dotGlow * 0.3)
            
            // Particles
            ForEach(particles) { particle in
                Circle()
                    .fill(particle.color)
                    .frame(width: particle.size, height: particle.size)
                    .offset(x: particle.x, y: particle.y)
                    .opacity(particle.opacity)
                    .blur(radius: particle.blur)
            }
            
            // Expanding rings
            ForEach(rings) { ring in
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                AppColors.accent.opacity(ring.opacity),
                                AppColors.accent.opacity(ring.opacity * 0.5)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: ring.lineWidth
                    )
                    .frame(width: 60, height: 60)
                    .scaleEffect(ring.scale)
            }
            
            // Final burst effect
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            AppColors.accent.opacity(0.4),
                            AppColors.accent.opacity(0.1),
                            .clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 200
                    )
                )
                .scaleEffect(burstScale)
                .opacity(burstOpacity)
            
            VStack(spacing: 24) {
                // Animated logo mark
                ZStack {
                    // Glow effect behind dot
                    Circle()
                        .fill(AppColors.accent)
                        .frame(width: 20, height: 20)
                        .blur(radius: 20 * dotGlow)
                        .opacity(dotGlow)
                    
                    // Center dot with gradient
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    AppColors.accent,
                                    AppColors.accent.opacity(0.8)
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: 10
                            )
                        )
                        .frame(width: 20, height: 20)
                        .scaleEffect(dotScale)
                        .shadow(color: AppColors.accent.opacity(0.5), radius: 10 * dotGlow)
                }
                .frame(width: 80, height: 80)
                
                // Animated wordmark
                HStack(spacing: 2) {
                    ForEach(0..<4, id: \.self) { index in
                        Text(letters[index])
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [
                                        AppColors.textPrimary,
                                        AppColors.textPrimary.opacity(0.8)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .offset(y: letterOffsets[index])
                            .opacity(letterOpacities[index])
                            .scaleEffect(letterScales[index])
                    }
                }
            }
            .opacity(logoOpacity)
            .scaleEffect(logoScale)
            .rotationEffect(.degrees(logoRotation))
        }
        .onAppear {
            startAnimation()
        }
    }
    
    private func startAnimation() {
        // Start background rotation
        withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
            gradientRotation = 360
        }
        
        // Phase 1: Logo container appears with spring
        withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
            logoOpacity = 1
            logoScale = 1
            logoRotation = 0
        }
        
        // Phase 2: Dot bursts in with particles
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            // Dot pop
            withAnimation(.spring(response: 0.35, dampingFraction: 0.5)) {
                dotScale = 1.3
            }
            
            // Dot settles
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6).delay(0.15)) {
                dotScale = 1
            }
            
            // Glow pulse
            withAnimation(.easeOut(duration: 0.4)) {
                dotGlow = 1
            }
            withAnimation(.easeIn(duration: 0.6).delay(0.4)) {
                dotGlow = 0.3
            }
            
            // Spawn particles
            spawnParticles()
            
            // Play haptic
            HapticManager.playLight()
        }
        
        // Phase 3: Multiple rings expand
        for i in 0..<3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4 + Double(i) * 0.15) {
                spawnRing(delay: 0, lineWidth: 3 - CGFloat(i) * 0.8)
            }
        }
        
        // Phase 4: Letters animate in with stagger
        for i in 0..<4 {
            let delay = 0.5 + Double(i) * 0.08
            
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(delay)) {
                letterOffsets[i] = 0
                letterOpacities[i] = 1
                letterScales[i] = 1
            }
            
            // Bounce effect
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5).delay(delay + 0.1)) {
                letterScales[i] = 1.1
            }
            withAnimation(.spring(response: 0.2, dampingFraction: 0.6).delay(delay + 0.2)) {
                letterScales[i] = 1
            }
        }
        
        // Phase 5: Final pulse and transition
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
            // Big haptic
            HapticManager.playSuccess()
            
            // Burst effect
            withAnimation(.easeOut(duration: 0.4)) {
                burstScale = 3
                burstOpacity = 0.6
            }
            withAnimation(.easeIn(duration: 0.3).delay(0.2)) {
                burstOpacity = 0
            }
            
            // Scale up and fade out
            withAnimation(.easeIn(duration: 0.35).delay(0.15)) {
                logoOpacity = 0
                logoScale = 1.15
            }
        }
        
        // Complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            isComplete = true
        }
    }
    
    private func spawnRing(delay: Double, lineWidth: CGFloat) {
        let ring = RingState(lineWidth: lineWidth)
        rings.append(ring)
        
        // Animate ring
        withAnimation(.easeOut(duration: 0.8).delay(delay)) {
            if let index = rings.firstIndex(where: { $0.id == ring.id }) {
                rings[index].scale = 2.5
                rings[index].opacity = 0
            }
        }
        
        // Clean up
        DispatchQueue.main.asyncAfter(deadline: .now() + delay + 1.0) {
            rings.removeAll { $0.id == ring.id }
        }
    }
    
    private func spawnParticles() {
        let particleCount = 12
        
        for i in 0..<particleCount {
            let angle = (Double(i) / Double(particleCount)) * 2 * .pi
            let distance: CGFloat = CGFloat.random(in: 80...150)
            let size = CGFloat.random(in: 4...10)
            
            var particle = Particle(
                x: 0,
                y: 0,
                targetX: cos(angle) * distance,
                targetY: sin(angle) * distance,
                size: size,
                color: i % 2 == 0 ? AppColors.accent : AppColors.accent.opacity(0.6),
                blur: CGFloat.random(in: 0...2)
            )
            
            particles.append(particle)
            
            // Animate particle outward
            withAnimation(.easeOut(duration: 0.6)) {
                if let index = particles.firstIndex(where: { $0.id == particle.id }) {
                    particles[index].x = particle.targetX
                    particles[index].y = particle.targetY
                }
            }
            
            // Fade out
            withAnimation(.easeIn(duration: 0.4).delay(0.3)) {
                if let index = particles.firstIndex(where: { $0.id == particle.id }) {
                    particles[index].opacity = 0
                }
            }
        }
        
        // Clean up particles
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            particles.removeAll()
        }
    }
}

// MARK: - Supporting Types

struct RingState: Identifiable {
    let id = UUID()
    var scale: CGFloat = 1
    var opacity: Double = 0.8
    var lineWidth: CGFloat
}

struct Particle: Identifiable {
    let id = UUID()
    var x: CGFloat
    var y: CGFloat
    let targetX: CGFloat
    let targetY: CGFloat
    let size: CGFloat
    let color: Color
    var opacity: Double = 1
    let blur: CGFloat
}

#Preview {
    LaunchView(isComplete: .constant(false))
}
