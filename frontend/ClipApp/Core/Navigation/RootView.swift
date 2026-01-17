import SwiftUI
import AVFoundation

struct RootView: View {
    @StateObject private var viewState = GlobalViewState()
    @StateObject private var wakeWordDetector = WakeWordDetector()
    @State private var selectedClip: ClipMetadata?
    @State private var showClipConfirmation = false
    @State private var showSearch = false
    @Namespace private var namespace

    var body: some View {
        ZStack {
            // Background
            AppColors.warmBackground
                .ignoresSafeArea()
            
            // Main content
            VStack(spacing: 0) {
                // Minimal header
                headerBar
                
                // Timeline
                TimelineView(
                    clips: viewState.filteredClips,
                    isLoading: viewState.isLoading,
                    selectedClip: $selectedClip,
                    namespace: namespace
                )
            }
            .opacity(selectedClip != nil ? 0 : 1)

            // Detail view overlay
            if let clip = selectedClip {
                ClipDetailView(clip: clip, namespace: namespace, selectedClip: $selectedClip)
                    .transition(.asymmetric(insertion: .identity, removal: .opacity))
                    .zIndex(100)
            }
            
            // Search overlay
            if showSearch {
                searchOverlay
                    .transition(.opacity)
                    .zIndex(50)
            }
        }
        .overlay {
            // Clip confirmation
            if showClipConfirmation {
                ClipConfirmation()
                    .transition(.scale.combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation(.spring(response: 0.3)) {
                                showClipConfirmation = false
                            }
                        }
                    }
            }
            
            // Listening indicator
            if wakeWordDetector.isListening {
                VStack {
                    ListeningPill()
                        .padding(.top, 60)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .task {
            await setupWakeWordDetection()
        }
    }
    
    // MARK: - Header Bar
    
    private var headerBar: some View {
        HStack(alignment: .center) {
            // Wordmark
            Text("clip")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(AppColors.textPrimary)
            
            Spacer()
            
            // Connection status dot
            if wakeWordDetector.isListening {
                Circle()
                    .fill(AppColors.connected)
                    .frame(width: 8, height: 8)
                    .padding(.trailing, 8)
            }
            
            // Search button
            Button {
                HapticManager.playLight()
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    showSearch = true
                }
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
    
    // MARK: - Search Overlay
    
    private var searchOverlay: some View {
        ZStack {
            // Dimmed background
            AppColors.warmBackground.opacity(0.98)
                .ignoresSafeArea()
                .onTapGesture {
                    dismissSearch()
                }
            
            VStack(spacing: 24) {
                // Search field
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                    
                    TextField("Search your moments...", text: $viewState.searchText)
                        .font(.system(size: 17))
                        .foregroundStyle(AppColors.textPrimary)
                        .autocorrectionDisabled()
                    
                    if !viewState.searchText.isEmpty {
                        Button {
                            viewState.searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }
                }
                .padding(16)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(AppColors.warmSurface)
                }
                
                // Quick suggestions
                if viewState.searchText.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Recent")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppColors.textSecondary)
                        
                        FlowLayout(spacing: 8) {
                            ForEach(["coffee", "meeting", "dinner", "travel"], id: \.self) { suggestion in
                                Button {
                                    viewState.searchText = suggestion
                                } label: {
                                    Text(suggestion)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(AppColors.textPrimary)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background {
                                            Capsule()
                                                .fill(AppColors.warmSurface)
                                        }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                Spacer()
                
                // Cancel button
                Button {
                    dismissSearch()
                } label: {
                    Text("Cancel")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(AppColors.accent)
                }
                .padding(.bottom, 20)
            }
            .padding(20)
            .padding(.top, 40)
        }
    }
    
    private func dismissSearch() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            showSearch = false
        }
    }
    
    // MARK: - Wake Word Detection Setup
    
    private func setupWakeWordDetection() async {
        await wakeWordDetector.requestAuthorization()
        
        wakeWordDetector.onClipTriggered = { [self] transcript in
            captureClip(transcript: transcript)
        }
    }

    private func captureClip(transcript: String = "") {
        HapticManager.playSuccess()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            showClipConfirmation = true
        }
        
        if !transcript.isEmpty {
            Task {
                await sendClipToBackend(transcript: transcript)
            }
        }
    }
    
    private func sendClipToBackend(transcript: String) async {
        print("📝 Clip triggered with transcript: \(transcript)")
    }
}

// MARK: - Listening Pill

struct ListeningPill: View {
    @State private var isPulsing = false
    
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(AppColors.accent)
                .frame(width: 8, height: 8)
                .scaleEffect(isPulsing ? 1.2 : 1.0)
                .animation(
                    .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                    value: isPulsing
                )
            
            Text("Listening...")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background {
            Capsule()
                .fill(AppColors.warmSurface)
                .shadow(color: AppColors.cardShadow, radius: 12, y: 4)
        }
        .onAppear {
            isPulsing = true
        }
    }
}

// MARK: - Clip Confirmation

struct ClipConfirmation: View {
    @State private var checkScale: CGFloat = 0
    @State private var ringScale: CGFloat = 0.8
    @State private var ringOpacity: Double = 0

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                // Animated ring
                Circle()
                    .stroke(AppColors.accent.opacity(0.3), lineWidth: 2)
                    .frame(width: 80, height: 80)
                    .scaleEffect(ringScale)
                    .opacity(ringOpacity)
                
                // Main circle
                Circle()
                    .fill(AppColors.warmSurface)
                    .frame(width: 72, height: 72)
                    .shadow(color: AppColors.cardShadow, radius: 16, y: 8)

                // Checkmark
                Image(systemName: "checkmark")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(AppColors.accent)
                    .scaleEffect(checkScale)
            }

            VStack(spacing: 4) {
                Text("Captured")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)

                Text("Moment saved")
                    .font(.system(size: 14))
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .padding(40)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(AppColors.warmBackground)
                .shadow(color: .black.opacity(0.15), radius: 40, y: 20)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                ringScale = 1
                ringOpacity = 1
            }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6).delay(0.1)) {
                checkScale = 1
            }
        }
    }
}

#Preview {
    RootView()
}
