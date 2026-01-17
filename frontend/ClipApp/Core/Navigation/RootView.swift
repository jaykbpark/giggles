import SwiftUI
import AVFoundation

struct RootView: View {
    @StateObject private var viewState = GlobalViewState()
    @StateObject private var wakeWordDetector = WakeWordDetector()
    @State private var selectedClip: ClipMetadata?
    @State private var showClipConfirmation = false
    @State private var isSearchFocused = false
    @Namespace private var namespace

    var body: some View {
        ZStack {
            NavigationStack {
                ZStack(alignment: .bottom) {
                    // Main content
                    ScrollView {
                        VStack(spacing: 0) {
                            // Header - animates away when searching
                            if !isSearchFocused {
                                GlassesStatusCard(isListening: wakeWordDetector.isListening)
                                    .padding(.horizontal, 20)
                                    .padding(.top, 8)
                                    .transition(.move(edge: .top).combined(with: .opacity))
                            }

                            contentView
                                .padding(.top, isSearchFocused ? 8 : 20)
                        }
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isSearchFocused)
                        .padding(.bottom, 160)
                    }
                    .background(Color(.systemBackground))
                    .onTapGesture {
                        // Dismiss keyboard when tapping outside
                        if isSearchFocused {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                isSearchFocused = false
                            }
                        }
                    }

                    // Bottom search bar
                    BottomSearchBar(
                        searchText: $viewState.searchText,
                        isSearchFocused: $isSearchFocused,
                        onCapture: { captureClip() }
                    )
                }
                .navigationTitle("Clips")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        viewModeToggle
                    }
                }
            }
            .opacity(selectedClip != nil ? 0 : 1)

            // Liquid Lens Player Overlay
            if let clip = selectedClip {
                ClipDetailView(clip: clip, namespace: namespace, selectedClip: $selectedClip)
                    .transition(.asymmetric(insertion: .identity, removal: .opacity))
                    .zIndex(100)
            }
        }
        .overlay {
            if showClipConfirmation {
                SpectacularConfirmation()
                    .transition(.scale.combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation(.spring(response: 0.3)) {
                                showClipConfirmation = false
                            }
                        }
                    }
            }
        }
        .task {
            await setupWakeWordDetection()
        }
    }
    
    // MARK: - Wake Word Detection Setup
    
    private func setupWakeWordDetection() async {
        // Request speech recognition authorization
        await wakeWordDetector.requestAuthorization()
        
        // Set up callback when "Clip That" is detected - receives last 30s of transcript
        wakeWordDetector.onClipTriggered = { [self] transcript in
            captureClip(transcript: transcript)
        }
        
        // Note: Call startListening when you have the audio format from Meta SDK
        // Example: wakeWordDetector.startListening(audioFormat: audioFormatFromMetaSDK)
        // Then feed audio buffers: wakeWordDetector.processAudioBuffer(buffer)
    }

    @ViewBuilder
    private var contentView: some View {
        if !viewState.searchText.isEmpty {
            searchResultsHeader
        }

        switch viewState.viewMode {
        case .grid:
            ClipsGridView(
                clips: viewState.filteredClips,
                isLoading: viewState.isLoading,
                selectedClip: $selectedClip,
                namespace: namespace
            )
        case .list:
            ClipsListView(
                clips: viewState.filteredClips,
                isLoading: viewState.isLoading,
                selectedClip: $selectedClip,
                namespace: namespace
            )
        }
    }

    private var searchResultsHeader: some View {
        HStack {
            Text("\(viewState.filteredClips.count) results")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Button("Clear") {
                withAnimation {
                    viewState.searchText = ""
                }
            }
            .font(.subheadline)
            .foregroundStyle(AppAccents.primary)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    private var viewModeToggle: some View {
        Button {
            HapticManager.playLight()
            viewState.toggleViewMode()
        } label: {
            Image(systemName: viewState.viewMode == .grid ? "list.bullet" : "square.grid.3x3")
                .fontWeight(.medium)
                .foregroundStyle(.primary)
        }
    }

    private func captureClip(transcript: String = "") {
        HapticManager.playSuccess()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            showClipConfirmation = true
        }
        
        // Send transcript to backend
        if !transcript.isEmpty {
            Task {
                await sendClipToBackend(transcript: transcript)
            }
        }
    }
    
    private func sendClipToBackend(transcript: String) async {
        // TODO: Implement backend API call
        // This is where you send the transcript along with localIdentifier
        print("📝 Clip triggered with transcript: \(transcript)")
        
        // Example:
        // try await APIService.shared.processClip(
        //     audioData: audioData,
        //     localIdentifier: localIdentifier,
        //     transcript: transcript
        // )
    }
}

// MARK: - Glasses Status Card (Spectacular Header)

struct GlassesStatusCard: View {
    var isListening: Bool = false
    
    var body: some View {
        HStack(spacing: 14) {
            // Left: Stylized glasses icon
            StylizedGlassesIcon()
                .padding(.leading, 4)

            // Middle: Status info
            VStack(alignment: .leading, spacing: 3) {
                Text("RAY-BAN META")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .tracking(0.5)

                HStack(spacing: 6) {
                    Circle()
                        .fill(AppAccents.connected)
                        .frame(width: 6, height: 6)
                        .shadow(color: AppAccents.connected.opacity(0.6), radius: 3)

                    Text("Connected")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
            
            // Listening indicator (pulsing mic)
            if isListening {
                ListeningIndicator()
            }

            // Right: Battery with visual indicator
            GlassesBatteryView(level: 82)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .glassEffect(in: .rect(cornerRadius: 18))
                .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
        }
    }
}

// MARK: - Listening Indicator

struct ListeningIndicator: View {
    @State private var isPulsing = false
    
    var body: some View {
        ZStack {
            // Outer pulse ring
            Circle()
                .stroke(AppAccents.primary.opacity(0.3), lineWidth: 2)
                .frame(width: 32, height: 32)
                .scaleEffect(isPulsing ? 1.3 : 1.0)
                .opacity(isPulsing ? 0 : 0.6)
            
            // Inner circle
            Circle()
                .fill(AppAccents.primary.opacity(0.15))
                .frame(width: 28, height: 28)
            
            // Mic icon
            Image(systemName: "mic.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppAccents.primary)
        }
        .onAppear {
            withAnimation(
                .easeInOut(duration: 1.2)
                .repeatForever(autoreverses: false)
            ) {
                isPulsing = true
            }
        }
    }
}

// MARK: - Stylized Glasses Icon

struct StylizedGlassesIcon: View {
    var body: some View {
        HStack(spacing: 3) {
            // Left lens
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(.systemGray4), Color(.systemGray5)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 22, height: 14)
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color(.systemGray3), lineWidth: 1.5)
                }

            // Bridge
            Rectangle()
                .fill(Color(.systemGray3))
                .frame(width: 6, height: 2)

            // Right lens
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(.systemGray4), Color(.systemGray5)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 22, height: 14)
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color(.systemGray3), lineWidth: 1.5)
                }
        }
    }
}

// MARK: - Glasses Battery View

struct GlassesBatteryView: View {
    let level: Int

    private var batteryColor: Color {
        switch level {
        case 0..<20: return .red
        case 20..<50: return .orange
        default: return AppAccents.connected
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            // Circular battery indicator
            ZStack {
                // Background track
                Circle()
                    .stroke(Color(.systemGray5), lineWidth: 4)
                    .frame(width: 36, height: 36)

                // Progress arc
                Circle()
                    .trim(from: 0, to: CGFloat(level) / 100)
                    .stroke(
                        batteryColor,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .frame(width: 36, height: 36)
                    .rotationEffect(.degrees(-90))

                // Percentage text
                Text("\(level)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
            }
        }
    }
}

// MARK: - Bottom Search Bar

struct BottomSearchBar: View {
    @Binding var searchText: String
    @Binding var isSearchFocused: Bool
    let onCapture: () -> Void
    @FocusState private var textFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Expanded search suggestions when focused
            if isSearchFocused {
                SearchSuggestions(onSelect: { suggestion in
                    searchText = suggestion
                    dismissSearch()
                })
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Main bar
            HStack(spacing: 14) {
                // Search field
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(isSearchFocused ? AppAccents.primary : Color(.tertiaryLabel))

                    TextField("Search your clips...", text: $searchText)
                        .font(.system(size: 16))
                        .focused($textFieldFocused)

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(Color(.tertiaryLabel))
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .glassEffect(in: .rect(cornerRadius: 14))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            isSearchFocused
                                ? LinearGradient(
                                    colors: [AppAccents.primary.opacity(0.6), AppAccents.warm.opacity(0.4)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                : LinearGradient(
                                    colors: [Color.white.opacity(0.15), Color.white.opacity(0.05)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                            lineWidth: isSearchFocused ? 1.5 : 0.5
                        )
                }
                .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
                .animation(.easeInOut(duration: 0.2), value: isSearchFocused)

                // Cancel or Snap button
                if isSearchFocused {
                    Button("Cancel") {
                        dismissSearch()
                    }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(AppAccents.primary)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    CameraShutterButton(action: onCapture)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
        .background {
            Color(.systemBackground)
                .shadow(color: .black.opacity(0.06), radius: 16, y: -4)
                .ignoresSafeArea()
        }
        .onChange(of: textFieldFocused) { _, focused in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                isSearchFocused = focused
            }
        }
        .onChange(of: isSearchFocused) { _, focused in
            textFieldFocused = focused
        }
    }

    private func dismissSearch() {
        textFieldFocused = false
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            isSearchFocused = false
        }
    }
}

// MARK: - Search Suggestions

struct SearchSuggestions: View {
    let onSelect: (String) -> Void

    private let suggestions = ["coffee", "meeting", "hackathon", "dinner", "travel"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick searches")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppAccents.primary.opacity(0.7))
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(suggestions, id: \.self) { suggestion in
                        SearchPillButton(text: suggestion) {
                            onSelect(suggestion)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.vertical, 16)
    }
}

// MARK: - Search Pill Button

struct SearchPillButton: View {
    let text: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background {
                    Capsule()
                        .fill(Color(.secondarySystemBackground))
                        .overlay {
                            Capsule()
                                .stroke(Color(.separator).opacity(0.3), lineWidth: 0.5)
                        }
                }
        }
        .buttonStyle(PillButtonStyle())
    }
}

struct PillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Snap Button (Camera Capture)

struct CameraShutterButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                // Outer ring - subtle metallic
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(white: 0.95),
                                Color(white: 0.85)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 62, height: 62)
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 3)

                // Inner dark bezel
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(white: 0.20),
                                Color(white: 0.12)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 54, height: 54)

                // White snap circle (like iPhone camera)
                Circle()
                    .fill(.white)
                    .frame(width: 44, height: 44)
                    .shadow(color: .black.opacity(0.1), radius: 2, y: 1)

                // Inner subtle ring for depth
                Circle()
                    .stroke(Color(white: 0.9), lineWidth: 2)
                    .frame(width: 36, height: 36)
            }
        }
        .buttonStyle(SnapButtonStyle())
    }
}

struct SnapButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.5), value: configuration.isPressed)
    }
}

struct ShutterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .brightness(configuration.isPressed ? -0.1 : 0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Spectacular Confirmation

struct SpectacularConfirmation: View {
    @State private var ringScale: CGFloat = 0.8
    @State private var checkScale: CGFloat = 0
    @State private var ringOpacity: Double = 0

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                // Animated rings
                ForEach(0..<3) { i in
                    Circle()
                        .stroke(
                            AppAccents.connected.opacity(0.3 - Double(i) * 0.1),
                            lineWidth: 2
                        )
                        .frame(width: 100 + CGFloat(i) * 20, height: 100 + CGFloat(i) * 20)
                        .scaleEffect(ringScale)
                        .opacity(ringOpacity)
                }

                // Main circle
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                AppAccents.connected.opacity(0.2),
                                AppAccents.connected.opacity(0.05)
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 50
                        )
                    )
                    .frame(width: 100, height: 100)

                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 90, height: 90)
                    .glassEffect(in: .circle)

                // Checkmark
                Image(systemName: "checkmark")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(AppAccents.connected)
                    .scaleEffect(checkScale)
            }

            VStack(spacing: 6) {
                Text("Captured")
                    .font(.system(size: 22, weight: .bold, design: .rounded))

                Text("30 seconds saved")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(48)
        .background {
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(.ultraThickMaterial)
                .glassEffect(in: .rect(cornerRadius: 36))
                .shadow(color: .black.opacity(0.25), radius: 40, y: 20)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                ringScale = 1
                ringOpacity = 1
            }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6).delay(0.15)) {
                checkScale = 1
            }
        }
    }
}

#Preview {
    RootView()
}
