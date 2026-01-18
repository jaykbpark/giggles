import AVFoundation
import Combine
import CoreMedia
import CoreVideo

// MARK: - Timestamped Video Frame

/// Video frame with timestamp for synchronization with audio
struct TimestampedVideoFrame: Sendable {
    let pixelBuffer: CVPixelBuffer
    let hostTime: UInt64
    let presentationTime: CMTime
    
    /// Convert host time to seconds since boot
    var hostTimeSeconds: Double {
        var timebaseInfo = mach_timebase_info_data_t()
        mach_timebase_info(&timebaseInfo)
        let nanoseconds = hostTime * UInt64(timebaseInfo.numer) / UInt64(timebaseInfo.denom)
        return Double(nanoseconds) / 1_000_000_000.0
    }
}

// MARK: - Connection State

/// Represents the connection state of the Meta glasses
enum GlassesConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case error(GlassesError)
    
    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
    
    var statusText: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting..."
        case .connected: return "Connected"
        case .error(let error): return error.localizedDescription
        }
    }
}

// MARK: - Errors

/// Errors that can occur during glasses operations
enum GlassesError: Error, LocalizedError, Equatable, Sendable {
    case notConnected
    case connectionFailed(String)
    case streamFailed(String)
    case permissionDenied
    case deviceNotFound
    case sdkNotAvailable
    case audioNotSupported
    
    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Glasses not connected"
        case .connectionFailed(let reason):
            return "Connection failed: \(reason)"
        case .streamFailed(let reason):
            return reason  // Already contains user-friendly message
        case .permissionDenied:
            return "Camera permission denied. Grant access via glasses tap or Meta AI app."
        case .deviceNotFound:
            return "No glasses found. Ensure they're paired in Meta AI app."
        case .sdkNotAvailable:
            return "Meta SDK not available"
        case .audioNotSupported:
            return "Audio streaming not yet supported by Meta SDK"
        }
    }
}

// MARK: - Stream Provider Protocol

/// Protocol defining the interface for glasses stream providers.
/// SDK implementations conform to this protocol.
protocol GlassesStreamProvider: AnyObject {
    
    // MARK: - Connection
    
    /// Current connection state
    var connectionState: GlassesConnectionState { get }
    
    /// Publisher for connection state changes
    var connectionStatePublisher: AnyPublisher<GlassesConnectionState, Never> { get }
    
    /// Connect to the glasses
    func connect() async throws
    
    /// Disconnect from the glasses
    func disconnect()
    
    // MARK: - Video Streaming
    
    /// Publisher for video frames from the glasses camera
    var videoFramePublisher: AnyPublisher<CVPixelBuffer, Never> { get }
    
    /// Publisher for timestamped video frames (for synchronization with audio)
    var timestampedVideoFramePublisher: AnyPublisher<TimestampedVideoFrame, Never> { get }
    
    /// Whether video is currently streaming
    var isVideoStreaming: Bool { get }
    
    /// Start the video stream
    func startVideoStream() async throws
    
    /// Stop the video stream
    func stopVideoStream()
    
    // MARK: - Audio Streaming
    
    /// The audio format of the stream (for speech recognition)
    var audioFormat: AVAudioFormat? { get }
    
    /// Publisher for audio buffers from the glasses microphone
    var audioBufferPublisher: AnyPublisher<AVAudioPCMBuffer, Never> { get }
    
    /// Whether audio is currently streaming
    var isAudioStreaming: Bool { get }
    
    /// Start the audio stream
    func startAudioStream() async throws
    
    /// Stop the audio stream
    func stopAudioStream()
    
    // MARK: - Device Info
    
    /// Battery level (0-100)
    var batteryLevel: Int { get }
    
    /// Device name (e.g., "Ray-Ban Meta")
    var deviceName: String { get }
}

// MARK: - Video Frame Info

/// Metadata about a video frame
struct VideoFrameInfo: Sendable {
    let timestamp: Date
    let width: Int
    let height: Int
    let frameNumber: UInt64
}
