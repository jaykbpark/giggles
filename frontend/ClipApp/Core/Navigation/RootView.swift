import SwiftUI
import AVFoundation
import Combine

struct RootView: View {
    @StateObject private var viewState = GlobalViewState()
    @StateObject private var glassesManager = MetaGlassesManager.shared
    @StateObject private var captureCoordinator = ClipCaptureCoordinator.shared
    @State private var selectedClip: ClipMetadata?
    @State private var showSearch = false
    @State private var isRecording = false
    @State private var showRecordConfirmation = false
    @State private var cancellables = Set<AnyCancellable>()
    @Namespace private var namespace

    var body: some View {
        ZStack {
            // Background
            AppGradients.warmAmbient
                .ignoresSafeArea()
            
            // Main content
            VStack(spacing: 0) {
                // Header
                headerBar
                
                // Glasses Status Card
                GlassesStatusCard(
                    isListening: captureCoordinator.isCapturing,
                    connectionState: glassesManager.connectionState,
                    batteryLevel: glassesManager.batteryLevel,
                    deviceName: glassesManager.deviceName,
                    isMockMode: glassesManager.isMockMode
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
                
                // Filter Bar
                FilterBar(viewState: viewState)
                    .padding(.bottom, 4)
                
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
        .task {
            await setupCaptureCoordinator()
        }
    }
    
    // MARK: - Capture Coordinator Setup
    
    private func setupCaptureCoordinator() async {
        // Set up callback when a clip is exported
        captureCoordinator.onClipExported = { [self] url in
            Task { @MainActor in
                captureClip(exportedURL: url)
            }
        }
        
        captureCoordinator.onExportError = { error in
            print("❌ Clip export failed: \(error.localizedDescription)")
        }
        
        // Connect to Meta glasses
        do {
            try await glassesManager.connect()
            print("🕶️ Connected to glasses")
        } catch {
            print("⚠️ Failed to connect to glasses: \(error.localizedDescription)")
            // Continue anyway - audio capture still works via Bluetooth
        }
        
        // Start the capture coordinator (video + audio + wake word detection)
        do {
            try await captureCoordinator.startCapture()
            print("🎬 Capture coordinator started")
        } catch {
            print("⚠️ Failed to start capture: \(error.localizedDescription)")
        }
    }
    
    private func captureClip(exportedURL: URL? = nil, transcript: String = "") {
        HapticManager.playSuccess()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            showRecordConfirmation = true
        }
        
        // Handle exported clip
        if let url = exportedURL {
            Task {
                await handleExportedClip(url: url)
            }
        }
        
        // Send transcript to backend
        if !transcript.isEmpty {
            Task {
                await sendClipToBackend(transcript: transcript)
            }
        }
        
        // Auto-dismiss confirmation
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.spring(response: 0.3)) {
                showRecordConfirmation = false
            }
        }
    }
    
    private func handleExportedClip(url: URL) async {
        // TODO: Save to photo library or upload to backend
        print("📼 Clip exported to: \(url.path)")
        
        // For now, just log the file size
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           let fileSize = attributes[.size] as? Int64 {
            let sizeInMB = Double(fileSize) / (1024 * 1024)
            print("📼 Clip size: \(String(format: "%.2f", sizeInMB)) MB")
        }
    }
    
    private func sendClipToBackend(transcript: String) async {
        // TODO: Implement backend API call
        print("📝 Clip triggered with transcript: \(transcript)")
    }
    
    // MARK: - Header Bar
    
    private var headerBar: some View {
        HStack(alignment: .center) {
            // Wordmark
            Text("clip")
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.6)
                .foregroundStyle(AppColors.textPrimary)
            
            Spacer()
            
            // Search button with glass
            Button {
                HapticManager.playLight()
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    showSearch = true
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(.clear)
                        .frame(width: 36, height: 36)
                        .glassEffect(.regular.interactive(), in: .circle)

                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppColors.timelineLine.opacity(0.4))
                .frame(height: 1)
                .padding(.horizontal, 20)
        }
    }
    
    // MARK: - Record Button
    
    private var recordButton: some View {
        Button {
            triggerRecording()
        } label: {
            ZStack {
                // Glass halo
                Circle()
                    .fill(.clear)
                    .frame(width: 72, height: 72)
                    .glassEffect(.regular.interactive(), in: .circle)

                Circle()
                    .stroke(AppColors.accent.opacity(0.25), lineWidth: 1)
                    .frame(width: 72, height: 72)

                // Accent core
                Circle()
                    .fill(AppGradients.accent)
                    .frame(width: 56, height: 56)

                if isRecording {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.white)
                        .frame(width: 18, height: 18)
                } else {
                    Circle()
                        .fill(.white)
                        .frame(width: 22, height: 22)
                }
            }
        }
        .buttonStyle(RecordButtonStyle())
        .shadow(color: AppColors.accent.opacity(0.25), radius: 16, y: 10)
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
            // Soft dimmed background
            AppColors.warmBackground
                .opacity(0.96)
                .ignoresSafeArea()
                .overlay {
                    Color.black.opacity(0.08).ignoresSafeArea()
                }
                .onTapGesture {
                    dismissSearch()
                }
            
            VStack(spacing: 0) {
                // Search field
                HStack(spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(AppColors.textSecondary)
                        
                        TextField("Search your moments...", text: $viewState.searchText)
                            .font(.system(size: 16))
                            .foregroundStyle(AppColors.textPrimary)
                            .autocorrectionDisabled()
                        
                        if !viewState.searchText.isEmpty {
                            Button {
                                viewState.searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(AppColors.textSecondary.opacity(0.7))
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .glassEffect(in: .rect(cornerRadius: 18))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(AppColors.timelineLine.opacity(0.4), lineWidth: 1)
                    }
                    
                    // Close button
                    Button {
                        dismissSearch()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppColors.textSecondary)
                            .frame(width: 36, height: 36)
                            .glassEffect(.regular.interactive(), in: .circle)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 60)
                
                Text("Search is semantic. Try describing the moment.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(.top, 10)
                
                // Suggestions with glass pills
                if viewState.searchText.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("TRY SEARCHING")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(AppColors.textSecondary)
                            .padding(.top, 28)
                        
                        FlowLayout(spacing: 10) {
                            ForEach(["that funny moment", "when we talked about AI", "coffee meetup", "the demo yesterday", "travel plans"], id: \.self) { suggestion in
                                Button {
                                    viewState.searchText = suggestion
                                } label: {
                                    Text(suggestion)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(AppColors.textPrimary)
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

// MARK: - Glasses Status Card

struct GlassesStatusCard: View {
    var isListening: Bool = false
    var connectionState: GlassesConnectionState = .connected
    var batteryLevel: Int = 82
    var deviceName: String = "Ray-Ban Meta"
    var isMockMode: Bool = false
    
    private var statusColor: Color {
        switch connectionState {
        case .connected: return AppColors.connected
        case .connecting: return .orange
        case .disconnected: return .gray
        case .error: return .red
        }
    }
    
    private var statusText: String {
        if isMockMode && connectionState.isConnected {
            return "Mock Mode"
        }
        return connectionState.statusText
    }
    
    var body: some View {
        HStack(spacing: 14) {
            // Left: Stylized glasses icon
            StylizedGlassesIcon()
                .padding(.leading, 4)

            // Middle: Status info
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("RAY-BAN META")
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(0.8)
                    
                    if isMockMode {
                        Text("MOCK")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                    }
                }

                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)
                        .shadow(color: statusColor.opacity(0.6), radius: 3)

                    Text(statusText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
            
            // Listening indicator (pulsing mic)
            if isListening {
                ListeningIndicator()
            }

            // Right: Battery with visual indicator (only show when connected)
            if connectionState.isConnected {
                GlassesBatteryView(level: batteryLevel)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .glassEffect(in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppColors.timelineLine.opacity(0.5), lineWidth: 1)
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
                .stroke(AppColors.accent.opacity(0.3), lineWidth: 2)
                .frame(width: 32, height: 32)
                .scaleEffect(isPulsing ? 1.3 : 1.0)
                .opacity(isPulsing ? 0 : 0.6)
            
            // Inner circle
            Circle()
                .fill(AppColors.accent.opacity(0.15))
                .frame(width: 28, height: 28)
            
            // Mic icon
            Image(systemName: "mic.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColors.accent)
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
        default: return .green
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

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                      y: bounds.minY + result.positions[index].y),
                         proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }
                
                positions.append(CGPoint(x: x, y: y))
                rowHeight = max(rowHeight, size.height)
                x += size.width + spacing
                
                self.size.width = max(self.size.width, x)
            }
            
            self.size.height = y + rowHeight
        }
    }
}

#Preview {
    RootView()
}
