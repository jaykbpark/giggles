import AVFoundation
import Combine

// MARK: - Audio Capture State

/// Represents the state of audio capture
enum AudioCaptureState: Equatable, Sendable {
    case idle
    case starting
    case capturing
    case error(AudioCaptureError)
    
    var isCapturing: Bool {
        if case .capturing = self { return true }
        return false
    }
    
    var statusText: String {
        switch self {
        case .idle: return "Idle"
        case .starting: return "Starting..."
        case .capturing: return "Capturing"
        case .error(let error): return error.localizedDescription
        }
    }
}

// MARK: - Errors

/// Errors that can occur during audio capture
enum AudioCaptureError: Error, Equatable, Sendable {
    case permissionDenied
    case audioSessionFailed(String)
    case engineStartFailed(String)
    case noBluetoothDevice
    case notCapturing
    
    var localizedDescription: String {
        switch self {
        case .permissionDenied:
            return "Microphone permission denied"
        case .audioSessionFailed(let reason):
            return "Audio session failed: \(reason)"
        case .engineStartFailed(let reason):
            return "Audio engine failed: \(reason)"
        case .noBluetoothDevice:
            return "No Bluetooth audio device connected"
        case .notCapturing:
            return "Audio capture not active"
        }
    }
}

// MARK: - Audio Capture Provider Protocol

/// Protocol defining the interface for audio capture providers.
/// Both mock and real Bluetooth implementations conform to this protocol.
protocol AudioCaptureProvider: AnyObject {
    
    // MARK: - State
    
    /// Current capture state
    var captureState: AudioCaptureState { get }
    
    /// Publisher for capture state changes
    var captureStatePublisher: AnyPublisher<AudioCaptureState, Never> { get }
    
    /// Whether audio is currently being captured
    var isCapturing: Bool { get }
    
    // MARK: - Audio Format
    
    /// The audio format of the captured stream
    var audioFormat: AVAudioFormat? { get }
    
    // MARK: - Audio Stream
    
    /// Publisher for audio buffers
    var audioBufferPublisher: AnyPublisher<AVAudioPCMBuffer, Never> { get }
    
    /// Publisher for timestamped audio buffers (for synchronization)
    var timestampedAudioPublisher: AnyPublisher<TimestampedAudioBuffer, Never> { get }
    
    // MARK: - Control
    
    /// Start capturing audio
    func startCapture() async throws
    
    /// Stop capturing audio
    func stopCapture()
}

// MARK: - Timestamped Audio Buffer

/// Audio buffer with timestamp for synchronization with video
struct TimestampedAudioBuffer: Sendable {
    let buffer: AVAudioPCMBuffer
    let hostTime: UInt64
    let sampleTime: AVAudioFramePosition
    
    /// Convert host time to seconds since boot
    var hostTimeSeconds: Double {
        var timebaseInfo = mach_timebase_info_data_t()
        mach_timebase_info(&timebaseInfo)
        let nanoseconds = hostTime * UInt64(timebaseInfo.numer) / UInt64(timebaseInfo.denom)
        return Double(nanoseconds) / 1_000_000_000.0
    }
}
