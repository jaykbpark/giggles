import SwiftUI

struct RootView: View {
    @StateObject private var viewState = GlobalViewState()
    @State private var selectedClip: ClipMetadata?
    @State private var showSearch = false
    @State private var isRecording = false
    @State private var showRecordConfirmation = false
    @Namespace private var namespace

    var body: some View {
        ZStack {
            // Background
            AppColors.warmBackground
                .ignoresSafeArea()
            
            // Main content
            VStack(spacing: 0) {
                // Header
                headerBar
                
                // Feed
                FeedView(
                    clips: viewState.filteredClips,
                    isLoading: viewState.isLoading,
                    selectedClip: $selectedClip,
                    namespace: namespace
                )
            }
            .opacity(selectedClip != nil ? 0 : 1)
            
            // Floating record button
            if selectedClip == nil && !showSearch {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        recordButton
                            .padding(.trailing, 24)
                            .padding(.bottom, 30)
                    }
                }
            }

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
            
            // Record confirmation overlay
            if showRecordConfirmation {
                ClipConfirmation()
                    .transition(.scale.combined(with: .opacity))
                    .zIndex(200)
            }
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
            
            // Search button with glass
            Button {
                HapticManager.playLight()
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    showSearch = true
                }
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(width: 40, height: 40)
                    .glassEffect(.regular.interactive())
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
    
    // MARK: - Record Button
    
    private var recordButton: some View {
        Button {
            triggerRecording()
        } label: {
            ZStack {
                Circle()
                    .fill(AppColors.accent)
                    .frame(width: 64, height: 64)
                
                if isRecording {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.white)
                        .frame(width: 20, height: 20)
                } else {
                    Circle()
                        .fill(.white)
                        .frame(width: 24, height: 24)
                }
            }
        }
        .buttonStyle(RecordButtonStyle())
        .shadow(color: AppColors.accent.opacity(0.35), radius: 12, y: 6)
    }
    
    private func triggerRecording() {
        HapticManager.playSuccess()
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            isRecording = true
        }
        
        // Simulate recording for 1 second then show confirmation
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isRecording = false
                showRecordConfirmation = true
            }
            
            // Auto-dismiss confirmation
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation(.spring(response: 0.3)) {
                    showRecordConfirmation = false
                }
            }
        }
    }
    
    // MARK: - Search Overlay
    
    private var searchOverlay: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    dismissSearch()
                }
            
            VStack(spacing: 0) {
                // Search field with glass
                HStack(spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.secondary)
                        
                        TextField("Search your moments...", text: $viewState.searchText)
                            .font(.system(size: 16))
                            .autocorrectionDisabled()
                        
                        if !viewState.searchText.isEmpty {
                            Button {
                                viewState.searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .glassEffect(in: .rect(cornerRadius: 16))
                    
                    // Close button
                    Button {
                        dismissSearch()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 36, height: 36)
                            .glassEffect(.regular.interactive())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 60)
                
                // Suggestions with glass pills
                if viewState.searchText.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("SUGGESTIONS")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 28)
                        
                        FlowLayout(spacing: 10) {
                            ForEach(["coffee", "meeting", "idea", "travel", "dinner"], id: \.self) { suggestion in
                                Button {
                                    viewState.searchText = suggestion
                                } label: {
                                    Text(suggestion)
                                        .font(.system(size: 14, weight: .medium))
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 10)
                                        .glassEffect(.regular.interactive(), in: .capsule)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
                
                Spacer()
            }
        }
    }
    
    private func dismissSearch() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            showSearch = false
            viewState.searchText = ""
        }
    }
}

// MARK: - Record Button Style

struct RecordButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
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
                    .stroke(AppColors.accent.opacity(0.4), lineWidth: 2)
                    .frame(width: 88, height: 88)
                    .scaleEffect(ringScale)
                    .opacity(ringOpacity)
                
                // Glass circle background
                Circle()
                    .fill(.clear)
                    .frame(width: 76, height: 76)
                    .glassEffect(in: .circle)

                // Checkmark
                Image(systemName: "checkmark")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(AppColors.accent)
                    .scaleEffect(checkScale)
            }

            VStack(spacing: 4) {
                Text("Clipped!")
                    .font(.system(size: 20, weight: .semibold))

                Text("Last 30 seconds saved")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(44)
        .glassEffect(in: .rect(cornerRadius: 32))
        .shadow(color: .black.opacity(0.2), radius: 40, y: 20)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                ringScale = 1.1
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
