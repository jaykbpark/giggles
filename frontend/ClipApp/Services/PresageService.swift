import Foundation
import Combine
import AVFoundation

#if canImport(SmartSpectraSwiftSDK)
import SmartSpectraSwiftSDK
#endif

@MainActor
final class PresageService: ObservableObject {
    static let shared = PresageService()

    @Published private(set) var currentState: ClipState?
    @Published private(set) var isRunning = false
    @Published private(set) var statusMessage: String = "Idle"

    private var pollTimer: Timer?

#if canImport(SmartSpectraSwiftSDK)
    private let sdk = SmartSpectraSwiftSDK.shared
    private let vitals = SmartSpectraVitalsProcessor.shared
#endif

    private init() {}

    func start() {
        guard !isRunning else { return }
        guard let apiKey = resolveApiKey() else {
            statusMessage = "Missing API key"
            currentState = neutralState
            return
        }

#if canImport(SmartSpectraSwiftSDK)
        sdk.setApiKey(apiKey)
        sdk.setSmartSpectraMode(.continuous)
        sdk.setMeasurementDuration(30.0)
        sdk.setCameraPosition(.front)
        sdk.setRecordingDelay(0)
        sdk.showControlsInScreeningView(false)

        vitals.startProcessing()
        vitals.startRecording()

        isRunning = true
        statusMessage = "Running"
        startPolling()
#else
        statusMessage = "SDK not available"
        currentState = neutralState
#endif
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        isRunning = false
        statusMessage = "Stopped"

#if canImport(SmartSpectraSwiftSDK)
        vitals.stopRecording()
        vitals.stopProcessing()
#endif
    }

    func snapshot() -> ClipState {
        currentState ?? neutralState
    }

    private var neutralState: ClipState {
        ClipState(stressLevel: 0.3, focusLevel: 0.5, emotionLabel: "Calm")
    }

    private func resolveApiKey() -> String? {
        if let envKey = ProcessInfo.processInfo.environment["PRESAGE_API_KEY"], !envKey.isEmpty {
            return envKey
        }
        if let envKey = ProcessInfo.processInfo.environment["SMARTSPECTRA_API_KEY"], !envKey.isEmpty {
            return envKey
        }
        if let infoKey = Bundle.main.object(forInfoDictionaryKey: "PRESAGE_API_KEY") as? String,
           !infoKey.isEmpty {
            return infoKey
        }
        return nil
    }

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateFromMetrics()
            }
        }
    }

    private func updateFromMetrics() {
#if canImport(SmartSpectraSwiftSDK)
        guard let metrics = sdk.metricsBuffer else {
            currentState = neutralState
            return
        }

        let pulse = Double(metrics.pulse.rate.last?.value ?? 70)
        let breathing = Double(metrics.breathing.rate.last?.value ?? 14)

        let stress = min(max((pulse - 55) / 60, 0), 1)
        let focus = min(max(1 - abs(breathing - 12) / 14, 0), 1)

        let emotion: String
        if stress > 0.7 {
            emotion = "Anxious"
        } else if focus > 0.7 {
            emotion = "Focused"
        } else {
            emotion = "Calm"
        }

        currentState = ClipState(
            stressLevel: stress,
            focusLevel: focus,
            emotionLabel: emotion
        )
#else
        currentState = neutralState
#endif
    }
}
