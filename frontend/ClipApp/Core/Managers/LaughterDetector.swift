import AVFoundation
import SoundAnalysis
import Combine

/// Detects laughter in audio streams using iOS Sound Analysis framework
/// Can be used to auto-trigger clip capture when laughter is detected
@MainActor
final class LaughterDetector: NSObject, ObservableObject {
    
    // MARK: - Published State
    
    @Published private(set) var isListening = false
    @Published private(set) var lastDetectionTime: Date?
    @Published private(set) var currentConfidence: Float = 0
    @Published private(set) var detectionCount: Int = 0
    
    // MARK: - Configuration
    
    /// Confidence threshold for triggering (0.0 - 1.0)
    var confidenceThreshold: Float = 0.6
    
    /// Minimum duration of laughter to trigger (seconds)
    var minimumDuration: TimeInterval = 0.5
    
    /// Cooldown between triggers (seconds)
    var triggerCooldown: TimeInterval = 5.0
    
    /// Whether detection is enabled
    @Published var isEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "laughterDetectionEnabled")
        }
    }
    
    // MARK: - Callbacks
    
    /// Called when laughter is detected above threshold
    var onLaughterDetected: (() -> Void)?
    
    /// Called with continuous confidence updates
    var onConfidenceUpdate: ((Float) -> Void)?
    
    // MARK: - Private Properties
    
    private var analyzer: SNAudioStreamAnalyzer?
    private var analysisQueue = DispatchQueue(label: "com.clip.laughterdetector.analysis", qos: .userInitiated)
    private var audioFormat: AVAudioFormat?
    
    private var laughterStartTime: Date?
    private var lastTriggerTime: Date?
    
    // Sound classification request
    private var classificationRequest: SNClassifySoundRequest?
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        
        // Load saved preference
        isEnabled = UserDefaults.standard.bool(forKey: "laughterDetectionEnabled")
    }
    
    // MARK: - Public Methods
    
    /// Start listening for laughter on the given audio format
    /// - Parameter audioFormat: The format of the incoming audio buffers
    func startListening(audioFormat: AVAudioFormat) {
        guard isEnabled else {
            print("🎭 LaughterDetector: Detection disabled, not starting")
            return
        }
        
        guard !isListening else { return }
        
        self.audioFormat = audioFormat
        
        // Create analyzer
        analyzer = SNAudioStreamAnalyzer(format: audioFormat)
        
        // Create classification request for sound classification
        do {
            // Use the built-in sound classifier
            classificationRequest = try SNClassifySoundRequest(classifierIdentifier: .version1)
            classificationRequest?.windowDuration = CMTime(seconds: 1.0, preferredTimescale: 48000)
            
            // Add request to analyzer
            try analyzer?.add(classificationRequest!, withObserver: self)
            
            isListening = true
            print("🎭 LaughterDetector: Started listening")
        } catch {
            print("🎭 LaughterDetector: Failed to start - \(error.localizedDescription)")
        }
    }
    
    /// Process an audio buffer from the audio stream
    /// - Parameter buffer: PCM audio buffer to analyze
    func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard isListening, isEnabled else { return }
        
        analysisQueue.async { [weak self] in
            self?.analyzer?.analyze(buffer, atAudioFramePosition: 0)
        }
    }
    
    /// Stop listening for laughter
    func stopListening() {
        guard isListening else { return }
        
        analyzer?.removeAllRequests()
        analyzer = nil
        classificationRequest = nil
        
        isListening = false
        currentConfidence = 0
        laughterStartTime = nil
        
        print("🎭 LaughterDetector: Stopped listening")
    }
    
    /// Reset detection state
    func reset() {
        detectionCount = 0
        lastDetectionTime = nil
        laughterStartTime = nil
        currentConfidence = 0
    }
    
    // MARK: - Private Methods
    
    private func handleLaughterDetection(confidence: Float) {
        let now = Date()
        
        // Update current confidence
        Task { @MainActor in
            self.currentConfidence = confidence
            self.onConfidenceUpdate?(confidence)
        }
        
        // Check if above threshold
        if confidence >= confidenceThreshold {
            // Start tracking if not already
            if laughterStartTime == nil {
                laughterStartTime = now
            }
            
            // Check if duration threshold met
            if let startTime = laughterStartTime,
               now.timeIntervalSince(startTime) >= minimumDuration {
                
                // Check cooldown
                if let lastTrigger = lastTriggerTime,
                   now.timeIntervalSince(lastTrigger) < triggerCooldown {
                    return
                }
                
                // Trigger!
                lastTriggerTime = now
                laughterStartTime = nil
                
                Task { @MainActor in
                    self.detectionCount += 1
                    self.lastDetectionTime = now
                    self.onLaughterDetected?()
                    print("🎭 LaughterDetector: Laughter detected! (confidence: \(confidence))")
                }
            }
        } else {
            // Reset tracking if confidence drops
            laughterStartTime = nil
        }
    }
}

// MARK: - SNResultsObserving

extension LaughterDetector: SNResultsObserving {
    
    nonisolated func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let classificationResult = result as? SNClassificationResult else { return }
        
        // Look for laughter classification
        // The built-in classifier includes "laughter" as a category
        for classification in classificationResult.classifications {
            let identifier = classification.identifier.lowercased()
            
            // Check for laughter-related identifiers
            if identifier.contains("laugh") || identifier.contains("giggle") || identifier.contains("chuckle") {
                Task { @MainActor in
                    self.handleLaughterDetection(confidence: Float(classification.confidence))
                }
                return
            }
        }
        
        // No laughter detected, reset confidence
        Task { @MainActor in
            self.currentConfidence = 0
            self.laughterStartTime = nil
        }
    }
    
    nonisolated func request(_ request: SNRequest, didFailWithError error: Error) {
        print("🎭 LaughterDetector: Analysis failed - \(error.localizedDescription)")
    }
    
    nonisolated func requestDidComplete(_ request: SNRequest) {
        // Analysis completed for this request
    }
}

// MARK: - Debug Helpers

extension LaughterDetector {
    override var debugDescription: String {
        """
        LaughterDetector:
          Enabled: \(isEnabled)
          Listening: \(isListening)
          Current Confidence: \(String(format: "%.2f", currentConfidence))
          Detection Count: \(detectionCount)
          Threshold: \(confidenceThreshold)
          Cooldown: \(triggerCooldown)s
        """
    }
}
