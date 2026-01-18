import SwiftUI
import AVFoundation
import Speech

/// A dedicated view for interacting with the Memory Assistant
/// Users can tap to speak or type their question
struct MemoryAssistantView: View {
    @ObservedObject var memoryAssistant: MemoryAssistantService
    @ObservedObject var viewState: GlobalViewState
    var isEmbedded: Bool = false // When true, no close button (used in tab view)
    @Environment(\.dismiss) private var dismiss
    
    @State private var questionText: String = ""
    @State private var isListening = false
    @State private var showingTextInput = false
    @FocusState private var isTextFieldFocused: Bool
    
    // Speech recognition
    @State private var speechRecognizer: SFSpeechRecognizer?
    @State private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    @State private var recognitionTask: SFSpeechRecognitionTask?
    @State private var audioEngine = AVAudioEngine()
    
    // Auto-submit on silence
    @State private var silenceTimer: Timer?
    @State private var lastSpeechTime: Date = Date()
    private let silenceThreshold: TimeInterval = 1.8 // Seconds of silence before auto-submit
    
    private let suggestedQuestions = [
        "What did I do yesterday?",
        "Who did I talk to today?",
        "What happened this morning?",
        "Tell me about my last conversation"
    ]
    
    @State private var gradientAngle: Double = 0
    
    var body: some View {
        ZStack {
            // Animated gradient background
            if isEmbedded {
                animatedBackground
                    .ignoresSafeArea()
            } else {
                AppGradients.warmAmbient
                    .ignoresSafeArea()
            }
            
            VStack(spacing: 0) {
                // Header
                header
                
                Spacer()
                
                // Main content
                if memoryAssistant.state.isActive {
                    // Show assistant state
                    assistantStateView
                } else if showingTextInput {
                    // Text input mode
                    textInputView
                } else {
                    // Default: voice input mode
                    voiceInputView
                }
                
                Spacer()
                
                // Suggested questions - show in embedded mode too
                if !memoryAssistant.state.isActive && !showingTextInput {
                    suggestionsView
                        .padding(.bottom, isEmbedded ? 20 : 0)
                }
            }
        }
        .onAppear {
            setupSpeechRecognition()
            // Auto-start listening when embedded (tab view)
            if isEmbedded {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    startListening()
                }
                // Start gradient animation
                withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                    gradientAngle = 360
                }
            }
        }
        .onDisappear {
            stopListening()
        }
        .onChange(of: memoryAssistant.state) { _, newState in
            // Auto-restart listening after response completes
            if isEmbedded && !newState.isActive && !isListening {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    if !memoryAssistant.state.isActive {
                        startListening()
                    }
                }
            }
        }
    }
    
    // MARK: - Animated Background
    
    private var animatedBackground: some View {
        ZStack {
            // Base warm color
            Color(red: 0.98, green: 0.96, blue: 0.93)
            
            // Floating gradient blobs
            GeometryReader { geo in
                // Blob 1 - peachy pink
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 1.0, green: 0.85, blue: 0.75).opacity(0.6),
                                Color(red: 1.0, green: 0.85, blue: 0.75).opacity(0)
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 200
                        )
                    )
                    .frame(width: 400, height: 400)
                    .offset(
                        x: geo.size.width * 0.3 + sin(gradientAngle * .pi / 180) * 30,
                        y: geo.size.height * 0.2 + cos(gradientAngle * .pi / 180) * 20
                    )
                    .blur(radius: 60)
                
                // Blob 2 - soft lavender
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.85, green: 0.8, blue: 0.95).opacity(0.5),
                                Color(red: 0.85, green: 0.8, blue: 0.95).opacity(0)
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 180
                        )
                    )
                    .frame(width: 350, height: 350)
                    .offset(
                        x: geo.size.width * -0.2 + cos(gradientAngle * .pi / 180 * 0.7) * 40,
                        y: geo.size.height * 0.5 + sin(gradientAngle * .pi / 180 * 0.7) * 30
                    )
                    .blur(radius: 50)
                
                // Blob 3 - warm amber accent
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                AppColors.accent.opacity(0.25),
                                AppColors.accent.opacity(0)
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 150
                        )
                    )
                    .frame(width: 300, height: 300)
                    .offset(
                        x: geo.size.width * 0.1 + sin(gradientAngle * .pi / 180 * 1.3) * 50,
                        y: geo.size.height * 0.7 + cos(gradientAngle * .pi / 180 * 1.3) * 40
                    )
                    .blur(radius: 40)
            }
        }
    }
    
    // MARK: - Header
    
    private var header: some View {
        Group {
            if isEmbedded {
                // Minimal header for embedded mode - just keyboard toggle on right
                HStack {
                    Spacer()
                    
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            showingTextInput.toggle()
                            if showingTextInput {
                                stopListening()
                                isTextFieldFocused = true
                            } else {
                                startListening()
                            }
                        }
                    } label: {
                        Image(systemName: showingTextInput ? "mic.fill" : "keyboard")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(AppColors.textSecondary)
                            .frame(width: 32, height: 32)
                            .glassEffect(.regular.interactive(), in: .circle)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            } else {
                // Full header for sheet mode
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppColors.textSecondary)
                            .frame(width: 40, height: 40)
                            .glassEffect(.regular.interactive(), in: .circle)
                    }
                    
                    Spacer()
                    
                    Text("Ask Clip")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                    
                    Spacer()
                    
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            showingTextInput.toggle()
                            if showingTextInput {
                                isTextFieldFocused = true
                            }
                        }
                    } label: {
                        Image(systemName: showingTextInput ? "mic.fill" : "keyboard")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppColors.textSecondary)
                            .frame(width: 40, height: 40)
                            .glassEffect(.regular.interactive(), in: .circle)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
        }
    }
    
    // MARK: - Voice Input View
    
    // App accent red color (matches #E85D4C)
    private let accentRed = Color(red: 0.91, green: 0.365, blue: 0.298)
    
    // Ring animations
    @State private var ring1Rotation: Double = 0
    @State private var ring2Rotation: Double = 0
    @State private var ring3Rotation: Double = 0
    
    // Amoeba-like blob morphing
    @State private var blobScale: CGFloat = 1.0
    @State private var blobStretchX: CGFloat = 1.0
    @State private var blobStretchY: CGFloat = 1.0
    @State private var blobRotation: Double = 0
    @State private var audioLevel: CGFloat = 0
    @State private var glowRadius: CGFloat = 20
    
    private var voiceInputView: some View {
        VStack(spacing: 0) {
            Spacer()
            
            // Audio-reactive visualization
            ZStack {
                // Spinning pink rings - different speeds and directions
                // Ring 1 - slowest, largest
                Circle()
                    .stroke(
                        AngularGradient(
                            colors: [accentRed.opacity(0.4), accentRed.opacity(0.1), accentRed.opacity(0.4)],
                            center: .center
                        ),
                        lineWidth: 1.5
                    )
                    .frame(width: 180, height: 180)
                    .rotationEffect(.degrees(ring1Rotation))
                
                // Ring 2 - medium speed, opposite direction
                Circle()
                    .stroke(
                        AngularGradient(
                            colors: [accentRed.opacity(0.5), accentRed.opacity(0.15), accentRed.opacity(0.5)],
                            center: .center
                        ),
                        lineWidth: 1.5
                    )
                    .frame(width: 140, height: 140)
                    .rotationEffect(.degrees(-ring2Rotation))
                
                // Ring 3 - fastest, smallest
                Circle()
                    .stroke(
                        AngularGradient(
                            colors: [accentRed.opacity(0.6), accentRed.opacity(0.2), accentRed.opacity(0.6)],
                            center: .center
                        ),
                        lineWidth: 2
                    )
                    .frame(width: 100, height: 100)
                    .rotationEffect(.degrees(ring3Rotation))
                
                // Morphing blob - stays centered, scales and stretches
                ZStack {
                    // Outer glow that grows with audio
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [accentRed.opacity(0.5), accentRed.opacity(0)],
                                center: .center,
                                startRadius: 20,
                                endRadius: glowRadius + 40
                            )
                        )
                        .frame(width: 120, height: 120)
                        .scaleEffect(blobScale * 1.2)
                        .blur(radius: 20)
                    
                    // The morphing amoeba blob
                    Ellipse()
                        .fill(
                            RadialGradient(
                                colors: [
                                    accentRed.opacity(0.95),
                                    accentRed.opacity(0.7)
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: 35
                            )
                        )
                        .frame(width: 50, height: 50)
                        .scaleEffect(x: blobStretchX, y: blobStretchY)
                        .scaleEffect(blobScale)
                        .rotationEffect(.degrees(blobRotation))
                        .shadow(color: accentRed.opacity(0.6), radius: glowRadius)
                    
                    // Inner highlight that follows the morph
                    Ellipse()
                        .fill(
                            RadialGradient(
                                colors: [.white.opacity(0.35), .clear],
                                center: .topLeading,
                                startRadius: 0,
                                endRadius: 20
                            )
                        )
                        .frame(width: 28, height: 28)
                        .scaleEffect(x: blobStretchX, y: blobStretchY)
                        .scaleEffect(blobScale)
                        .rotationEffect(.degrees(blobRotation))
                        .offset(x: -6, y: -6)
                    
                    // Send icon when there's text
                    if !questionText.isEmpty {
                        Button {
                            HapticManager.playLight()
                            stopListeningAndProcess()
                        } label: {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(.white)
                                .scaleEffect(x: 1/blobStretchX, y: 1/blobStretchY) // Counter-scale to keep icon normal
                        }
                    }
                }
            }
            .frame(width: 200, height: 200)
            .onAppear {
                startRingAnimations()
                startIdleMorphAnimation()
            }
            .onChange(of: audioLevel) { _, newLevel in
                morphBlobFromAudio(level: newLevel)
            }
            
            Spacer().frame(height: 40)
            
            // Live transcript area
            VStack(spacing: 12) {
                if questionText.isEmpty {
                    Text(isListening ? "Listening..." : "Starting...")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                    
                    Text("Ask me anything about your memories")
                        .font(.system(size: 14))
                        .foregroundStyle(AppColors.textSecondary.opacity(0.6))
                } else {
                    Text(questionText)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(AppColors.textPrimary)
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                }
            }
            .frame(height: 100)
            .padding(.horizontal, 32)
            .animation(.easeInOut(duration: 0.25), value: questionText)
            
            Spacer()
        }
    }
    
    private func startRingAnimations() {
        // Ring 1 - slow
        withAnimation(.linear(duration: 40).repeatForever(autoreverses: false)) {
            ring1Rotation = 360
        }
        // Ring 2 - medium, opposite
        withAnimation(.linear(duration: 30).repeatForever(autoreverses: false)) {
            ring2Rotation = 360
        }
        // Ring 3 - fast
        withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) {
            ring3Rotation = 360
        }
    }
    
    private func startIdleMorphAnimation() {
        // Amoeba-like organic flowing movement
        Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { _ in // ~60fps
            let time = Date().timeIntervalSinceReferenceDate
            
            if !isListening || audioLevel < 0.1 {
                // Slow, organic amoeba movement (reduced frequency multipliers for slower motion)
                let scale = 1.0 + sin(time * 0.4) * 0.06 + sin(time * 0.65) * 0.04
                let stretchX = 1.0 + sin(time * 0.3) * 0.08 + cos(time * 0.55) * 0.05
                let stretchY = 1.0 + cos(time * 0.35) * 0.08 + sin(time * 0.45) * 0.05
                let rotation = sin(time * 0.2) * 8 // Gentler rotation
                
                withAnimation(.linear(duration: 0.016)) {
                    blobScale = scale
                    blobStretchX = stretchX
                    blobStretchY = stretchY
                    blobRotation = rotation
                    glowRadius = 20 + sin(time * 0.25) * 5
                }
            }
        }
    }
    
    private func morphBlobFromAudio(level: CGFloat) {
        guard isListening && level > 0.05 else { return }
        
        let time = Date().timeIntervalSinceReferenceDate
        
        // Organic scale based on audio - smooth, not bouncy
        let baseScale = 1.0 + level * 0.5
        let organicScale = baseScale + sin(time * 1.5) * level * 0.15
        
        // Amoeba-like asymmetric stretch (slower oscillations)
        let stretchFactor = 0.15 + level * 0.2
        let stretchX = 1.0 + sin(time * 1.25) * stretchFactor
        let stretchY = 1.0 + cos(time * 1.1) * stretchFactor
        
        // Slow rotation influenced by audio
        let rotation = sin(time * 0.4) * 12 + level * 5
        
        // Glow pulses with audio
        let targetGlow = 20 + level * 25
        
        // Smooth easeInOut with slightly longer duration
        withAnimation(.easeInOut(duration: 0.2)) {
            blobScale = organicScale
            blobStretchX = stretchX
            blobStretchY = stretchY
            blobRotation = rotation
            glowRadius = targetGlow
        }
    }
    
    // MARK: - Text Input View
    
    private var textInputView: some View {
        VStack(spacing: 20) {
            Text("Type your question")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
            
            // Text field
            HStack(spacing: 12) {
                TextField("What would you like to know?", text: $questionText)
                    .font(.system(size: 16))
                    .foregroundStyle(AppColors.textPrimary)
                    .focused($isTextFieldFocused)
                    .submitLabel(.send)
                    .onSubmit {
                        submitQuestion()
                    }
                
                if !questionText.isEmpty {
                    Button {
                        submitQuestion()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(AppColors.accent)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .glassEffect(in: .rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AppColors.timelineLine.opacity(0.5), lineWidth: 1)
            }
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 40)
    }
    
    // MARK: - Assistant State View
    
    private var assistantStateView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Thinking state - just show spinner
            if memoryAssistant.state == .thinking {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(AppColors.accent)
                    
                    Text("Thinking...")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
            
            // Speaking state - show response only
            if memoryAssistant.state == .speaking, let response = memoryAssistant.lastResponse {
                VStack(spacing: 20) {
                    // Animated speaker icon
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(AppColors.accent)
                        .symbolEffect(.variableColor.iterative)
                    
                    // Response text
                    Text(response)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(AppColors.textPrimary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.horizontal, 32)
                    
                    // Stop button
                    Button {
                        memoryAssistant.stopSpeaking()
                    } label: {
                        Text("Stop")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                            .background(AppColors.accent.opacity(0.8))
                            .clipShape(Capsule())
                    }
                }
            }
            
            // Error state
            if case .error(let message) = memoryAssistant.state {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 32))
                        .foregroundStyle(.orange)
                    
                    Text(message)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }
            
            Spacer()
        }
    }
    
    @ViewBuilder
    private var stateIcon: some View {
        switch memoryAssistant.state {
        case .idle:
            Image(systemName: "brain")
        case .listening:
            Image(systemName: "ear")
        case .thinking:
            ProgressView()
                .tint(stateColor)
        case .speaking:
            Image(systemName: "speaker.wave.2.fill")
        case .error:
            Image(systemName: "exclamationmark.triangle")
        }
    }
    
    private var stateColor: Color {
        switch memoryAssistant.state {
        case .idle: return .gray
        case .listening: return .blue
        case .thinking: return .orange
        case .speaking: return AppColors.accent
        case .error: return .red
        }
    }
    
    // MARK: - Suggestions View
    
    private var suggestionsView: some View {
        VStack(spacing: 8) {
            if !isEmbedded {
                Text("TRY ASKING")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary.opacity(0.7))
                    .tracking(1)
            }
            
            // Horizontal scrolling pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(suggestedQuestions, id: \.self) { question in
                        Button {
                            HapticManager.playLight()
                            questionText = question
                            submitQuestion()
                        } label: {
                            Text(question)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(accentRed.opacity(0.9))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 11)
                                .background {
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [
                                                    accentRed.opacity(0.12),
                                                    accentRed.opacity(0.06)
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .overlay {
                                            Capsule()
                                                .stroke(accentRed.opacity(0.25), lineWidth: 1)
                                        }
                                }
                        }
                        .buttonStyle(ScaleButtonStyle())
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.bottom, isEmbedded ? 0 : 24)
    }
    
    // MARK: - Speech Recognition
    
    private func setupSpeechRecognition() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        
        SFSpeechRecognizer.requestAuthorization { status in
            // Authorization handled
        }
    }
    
    private func startListening() {
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            // Fallback to text input
            withAnimation {
                showingTextInput = true
                isTextFieldFocused = true
            }
            return
        }
        
        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("Audio session setup failed: \(error)")
            return
        }
        
        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }
        
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.requiresOnDeviceRecognition = true
        
        // Start recognition task
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { result, error in
            if let result = result {
                Task { @MainActor in
                    let newText = result.bestTranscription.formattedString
                    
                    // Check if text changed (user is speaking)
                    if newText != questionText && !newText.isEmpty {
                        questionText = newText
                        lastSpeechTime = Date()
                        
                        // Reset silence timer whenever speech is detected
                        silenceTimer?.invalidate()
                        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceThreshold, repeats: false) { _ in
                            Task { @MainActor in
                                // Auto-submit if we have text and enough silence
                                if !questionText.isEmpty && isListening {
                                    print("🎤 Auto-submitting after silence...")
                                    stopListeningAndProcess()
                                }
                            }
                        }
                    }
                }
            }
            
            if error != nil || (result?.isFinal ?? false) {
                // Recognition ended
            }
        }
        
        // Configure audio engine
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [self] buffer, _ in
            self.recognitionRequest?.append(buffer)
            
            // Calculate audio level for visualization
            let level = self.calculateAudioLevel(buffer: buffer)
            Task { @MainActor in
                self.audioLevel = level
            }
        }
        
        audioEngine.prepare()
        
        do {
            try audioEngine.start()
            isListening = true
            questionText = ""
        } catch {
            print("Audio engine failed to start: \(error)")
        }
    }
    
    private func calculateAudioLevel(buffer: AVAudioPCMBuffer) -> CGFloat {
        guard let channelData = buffer.floatChannelData?[0] else { return 0 }
        let frameLength = Int(buffer.frameLength)
        
        var sum: Float = 0
        for i in 0..<frameLength {
            sum += abs(channelData[i])
        }
        
        let average = sum / Float(frameLength)
        // Normalize and amplify for visible movement (0 to 1 range)
        let normalized = min(1.0, CGFloat(average) * 8)
        return normalized
    }
    
    private func stopListening() {
        // Cancel silence timer
        silenceTimer?.invalidate()
        silenceTimer = nil
        
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isListening = false
    }
    
    private func stopListeningAndProcess() {
        stopListening()
        
        // Process the question if we have one
        if !questionText.isEmpty {
            submitQuestion()
        }
    }
    
    private func submitQuestion() {
        guard !questionText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        
        let question = questionText.trimmingCharacters(in: .whitespaces)
        questionText = ""
        isTextFieldFocused = false
        
        Task {
            await memoryAssistant.askQuestion(question, clips: viewState.clips)
        }
    }
}

// MARK: - Scale Button Style

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Flowing Wave Shape

struct FlowingWaveShape: Shape {
    var phase: Double
    var amplitude: Double
    var frequency: Double
    
    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(phase, amplitude) }
        set {
            phase = newValue.first
            amplitude = newValue.second
        }
    }
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        
        let points = 100
        for i in 0...points {
            let angle = (Double(i) / Double(points)) * 2 * .pi
            let wave = sin(angle * frequency + phase) * amplitude
            let r = radius * (1 + wave * 0.15)
            
            let x = center.x + CGFloat(r) * cos(angle)
            let y = center.y + CGFloat(r) * sin(angle)
            
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        path.closeSubpath()
        
        return path
    }
}

// MARK: - Preview

#Preview {
    MemoryAssistantView(
        memoryAssistant: MemoryAssistantService(),
        viewState: GlobalViewState()
    )
}
