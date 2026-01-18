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
    
    private let suggestedQuestions = [
        "What did I do yesterday?",
        "Who did I talk to today?",
        "What happened this morning?",
        "Tell me about my last conversation"
    ]
    
    var body: some View {
        ZStack {
            // Background
            AppGradients.warmAmbient
                .ignoresSafeArea()
            
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
                
                // Suggested questions (only show in non-embedded mode when not listening)
                if !isEmbedded && !memoryAssistant.state.isActive && !showingTextInput && !isListening {
                    suggestionsView
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
    
    // MARK: - Header
    
    private var header: some View {
        HStack {
            if isEmbedded {
                // Spacer for balance when embedded
                Color.clear.frame(width: 40, height: 40)
            } else {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppColors.textSecondary)
                        .frame(width: 40, height: 40)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
            }
            
            Spacer()
            
            Text("Ask Clip")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(AppColors.textPrimary)
            
            Spacer()
            
            // Toggle between voice and text
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
        .padding(.top, isEmbedded ? 12 : 16)
    }
    
    // MARK: - Voice Input View
    
    private var voiceInputView: some View {
        VStack(spacing: 24) {
            // Instruction text - different for embedded (always listening) mode
            if isEmbedded {
                Text(isListening ? "Listening... ask me anything" : "Starting...")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(isListening ? AppColors.textPrimary : AppColors.textSecondary)
            } else {
                Text(isListening ? "Listening..." : "Tap to ask a question")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
            }
            
            // Big mic button / send button
            Button {
                HapticManager.playLight()
                if isEmbedded {
                    // In embedded mode, tap sends the question
                    if !questionText.isEmpty {
                        stopListeningAndProcess()
                    }
                } else {
                    // In sheet mode, tap toggles listening
                    if isListening {
                        stopListeningAndProcess()
                    } else {
                        startListening()
                    }
                }
            } label: {
                ZStack {
                    // Pulsing ring when listening
                    if isListening {
                        Circle()
                            .stroke(AppColors.accent.opacity(0.3), lineWidth: 2)
                            .frame(width: 140, height: 140)
                            .scaleEffect(1.2)
                            .opacity(0)
                            .animation(
                                .easeInOut(duration: 1.0).repeatForever(autoreverses: false),
                                value: isListening
                            )
                        
                        // Second pulsing ring for always-listening effect
                        Circle()
                            .stroke(AppColors.accent.opacity(0.2), lineWidth: 2)
                            .frame(width: 160, height: 160)
                            .scaleEffect(1.3)
                            .opacity(0)
                            .animation(
                                .easeInOut(duration: 1.5).repeatForever(autoreverses: false),
                                value: isListening
                            )
                    }
                    
                    // Glass background
                    Circle()
                        .fill(.clear)
                        .frame(width: 120, height: 120)
                        .glassEffect(in: .circle)
                    
                    // Colored ring - always accent when listening
                    Circle()
                        .stroke(
                            isListening ? AppColors.accent : AppColors.accent.opacity(0.3),
                            lineWidth: 3
                        )
                        .frame(width: 120, height: 120)
                    
                    // Inner circle
                    Circle()
                        .fill(AppGradients.accent)
                        .frame(width: 80, height: 80)
                        .scaleEffect(isListening ? 1.0 : 0.9)
                        .animation(.spring(response: 0.3), value: isListening)
                    
                    // Icon - show send arrow when there's text in embedded mode
                    if isEmbedded && !questionText.isEmpty {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(.white)
                    } else {
                        Image(systemName: "waveform")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(.white)
                            .symbolEffect(.variableColor.iterative, isActive: isListening)
                    }
                }
            }
            .buttonStyle(ScaleButtonStyle())
            .disabled(isEmbedded && questionText.isEmpty && isListening) // Only enable tap when there's text
            
            // Live transcript - larger and more prominent
            if isListening {
                Text(questionText.isEmpty ? "Say something like \"What did I do yesterday?\"" : questionText)
                    .font(.system(size: questionText.isEmpty ? 14 : 18, weight: .medium))
                    .foregroundStyle(questionText.isEmpty ? AppColors.textTertiary : AppColors.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .frame(minHeight: 60)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: questionText)
            }
        }
        .padding(.bottom, 40)
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
        VStack(spacing: 20) {
            // State icon
            ZStack {
                Circle()
                    .fill(stateColor.opacity(0.2))
                    .frame(width: 100, height: 100)
                
                Circle()
                    .fill(.clear)
                    .frame(width: 80, height: 80)
                    .glassEffect(in: .circle)
                
                stateIcon
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(stateColor)
            }
            
            // Status text
            Text(memoryAssistant.state.displayText)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
            
            // Question
            if let question = memoryAssistant.lastQuestion {
                Text("\"\(question)\"")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            // Response (when speaking)
            if memoryAssistant.state == .speaking, let response = memoryAssistant.lastResponse {
                Text(response)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(AppColors.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
            }
            
            // Cancel button
            if memoryAssistant.state == .speaking {
                Button {
                    memoryAssistant.stopSpeaking()
                } label: {
                    Text("Stop")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(AppColors.accent)
                        .clipShape(Capsule())
                }
                .padding(.top, 8)
            }
        }
        .padding(.bottom, 40)
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
        VStack(alignment: .leading, spacing: 12) {
            Text("TRY ASKING")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(AppColors.textSecondary)
                .padding(.leading, 4)
            
            ForEach(suggestedQuestions, id: \.self) { question in
                Button {
                    HapticManager.playLight()
                    questionText = question
                    submitQuestion()
                } label: {
                    HStack {
                        Text(question)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 32)
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
                    questionText = result.bestTranscription.formattedString
                }
            }
            
            if error != nil || (result?.isFinal ?? false) {
                // Recognition ended
            }
        }
        
        // Configure audio engine
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.recognitionRequest?.append(buffer)
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
    
    private func stopListening() {
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

// MARK: - Preview

#Preview {
    MemoryAssistantView(
        memoryAssistant: MemoryAssistantService(),
        viewState: GlobalViewState()
    )
}
