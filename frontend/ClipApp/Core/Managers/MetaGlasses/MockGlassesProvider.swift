import AVFoundation
import Combine
import CoreGraphics
import CoreMedia
import CoreVideo
import UIKit

/// Mock implementation of GlassesStreamProvider for development without physical glasses.
/// Generates synthetic video frames and audio buffers.
final class MockGlassesProvider: GlassesStreamProvider {
    
    // MARK: - Configuration
    
    private struct Config {
        static let videoWidth = 1280
        static let videoHeight = 720
        static let videoFPS: Double = 30
        static let audioSampleRate: Double = 16000  // Standard for speech recognition
        static let audioBufferSize: AVAudioFrameCount = 1024
        static let connectionDelayRange: ClosedRange<Double> = 1.0...2.0
    }
    
    // MARK: - Published State
    
    private let connectionStateSubject = CurrentValueSubject<GlassesConnectionState, Never>(.disconnected)
    private let videoFrameSubject = PassthroughSubject<CVPixelBuffer, Never>()
    private let timestampedVideoFrameSubject = PassthroughSubject<TimestampedVideoFrame, Never>()
    private let audioBufferSubject = PassthroughSubject<AVAudioPCMBuffer, Never>()
    
    // MARK: - Connection
    
    var connectionState: GlassesConnectionState {
        connectionStateSubject.value
    }
    
    var connectionStatePublisher: AnyPublisher<GlassesConnectionState, Never> {
        connectionStateSubject.eraseToAnyPublisher()
    }
    
    // MARK: - Video
    
    var videoFramePublisher: AnyPublisher<CVPixelBuffer, Never> {
        videoFrameSubject.eraseToAnyPublisher()
    }
    
    var timestampedVideoFramePublisher: AnyPublisher<TimestampedVideoFrame, Never> {
        timestampedVideoFrameSubject.eraseToAnyPublisher()
    }
    
    private(set) var isVideoStreaming = false
    private var videoTimer: Timer?
    private var frameCount: UInt64 = 0
    private var startTime: Date?
    private var videoStartHostTime: UInt64 = 0
    
    // MARK: - Audio
    
    private(set) var audioFormat: AVAudioFormat?
    
    var audioBufferPublisher: AnyPublisher<AVAudioPCMBuffer, Never> {
        audioBufferSubject.eraseToAnyPublisher()
    }
    
    private(set) var isAudioStreaming = false
    private var audioTimer: Timer?
    
    // MARK: - Device Info
    
    let batteryLevel: Int = 82
    let deviceName: String = "Ray-Ban Meta (Mock)"
    
    // MARK: - Initialization
    
    init() {
        // Create audio format for speech recognition (16kHz mono)
        audioFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Config.audioSampleRate,
            channels: 1,
            interleaved: false
        )
    }
    
    deinit {
        disconnect()
    }
    
    // MARK: - Connection
    
    func connect() async throws {
        guard connectionState != .connected else { return }
        
        connectionStateSubject.send(.connecting)
        
        // Simulate connection delay
        let delay = Double.random(in: Config.connectionDelayRange)
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        
        connectionStateSubject.send(.connected)
    }
    
    func disconnect() {
        stopVideoStream()
        stopAudioStream()
        connectionStateSubject.send(.disconnected)
    }
    
    // MARK: - Video Streaming
    
    func startVideoStream() async throws {
        guard connectionState == .connected else {
            throw GlassesError.notConnected
        }
        
        guard !isVideoStreaming else { return }
        
        isVideoStreaming = true
        frameCount = 0
        startTime = Date()
        videoStartHostTime = mach_absolute_time()
        
        // Start video frame generation on main thread for Timer
        await MainActor.run {
            videoTimer = Timer.scheduledTimer(
                withTimeInterval: 1.0 / Config.videoFPS,
                repeats: true
            ) { [weak self] _ in
                self?.generateVideoFrame()
            }
        }
    }
    
    func stopVideoStream() {
        isVideoStreaming = false
        videoTimer?.invalidate()
        videoTimer = nil
    }
    
    // MARK: - Audio Streaming
    
    func startAudioStream() async throws {
        guard connectionState == .connected else {
            throw GlassesError.notConnected
        }
        
        guard !isAudioStreaming else { return }
        
        isAudioStreaming = true
        
        // Start audio buffer generation on main thread for Timer
        // Generate buffers at ~60 buffers/second (1024 samples at 16kHz ≈ 64ms per buffer)
        await MainActor.run {
            audioTimer = Timer.scheduledTimer(
                withTimeInterval: Double(Config.audioBufferSize) / Config.audioSampleRate,
                repeats: true
            ) { [weak self] _ in
                self?.generateAudioBuffer()
            }
        }
    }
    
    func stopAudioStream() {
        isAudioStreaming = false
        audioTimer?.invalidate()
        audioTimer = nil
    }
    
    // MARK: - Frame Generation
    
    private func generateVideoFrame() {
        guard isVideoStreaming else { return }
        
        // Create pixel buffer
        var pixelBuffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
        
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Config.videoWidth,
            Config.videoHeight,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pixelBuffer
        )
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return }
        
        // Lock buffer for drawing
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: Config.videoWidth,
            height: Config.videoHeight,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return }
        
        // Draw frame content
        drawMockFrame(in: context)
        
        frameCount += 1
        
        // Send raw pixel buffer for backward compatibility
        videoFrameSubject.send(buffer)
        
        // Create and send timestamped frame for synchronization
        let hostTime = mach_absolute_time()
        let presentationTime = CMTime(
            value: CMTimeValue(frameCount),
            timescale: CMTimeScale(Config.videoFPS)
        )
        
        let timestampedFrame = TimestampedVideoFrame(
            pixelBuffer: buffer,
            hostTime: hostTime,
            presentationTime: presentationTime
        )
        timestampedVideoFrameSubject.send(timestampedFrame)
    }
    
    private func drawMockFrame(in context: CGContext) {
        let width = CGFloat(Config.videoWidth)
        let height = CGFloat(Config.videoHeight)
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        
        // Calculate hue shift based on time (cycles every 10 seconds)
        let elapsed = startTime.map { Date().timeIntervalSince($0) } ?? 0
        let hueShift = CGFloat(elapsed.truncatingRemainder(dividingBy: 10.0) / 10.0)
        
        // Draw gradient background with shifting hue
        let topColor = UIColor(hue: hueShift, saturation: 0.3, brightness: 0.2, alpha: 1.0).cgColor
        let bottomColor = UIColor(hue: (hueShift + 0.5).truncatingRemainder(dividingBy: 1.0), saturation: 0.4, brightness: 0.3, alpha: 1.0).cgColor
        
        let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [topColor, bottomColor] as CFArray,
            locations: [0, 1]
        )!
        
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: 0),
            end: CGPoint(x: 0, y: height),
            options: []
        )
        
        // Draw crosshairs (POV camera guide)
        context.setStrokeColor(UIColor.white.withAlphaComponent(0.3).cgColor)
        context.setLineWidth(1)
        
        // Vertical center line
        context.move(to: CGPoint(x: width / 2, y: 0))
        context.addLine(to: CGPoint(x: width / 2, y: height))
        context.strokePath()
        
        // Horizontal center line
        context.move(to: CGPoint(x: 0, y: height / 2))
        context.addLine(to: CGPoint(x: width, y: height / 2))
        context.strokePath()
        
        // Corner brackets
        let bracketSize: CGFloat = 40
        let bracketMargin: CGFloat = 60
        context.setLineWidth(2)
        context.setStrokeColor(UIColor.white.withAlphaComponent(0.5).cgColor)
        
        // Top-left bracket
        context.move(to: CGPoint(x: bracketMargin, y: bracketMargin + bracketSize))
        context.addLine(to: CGPoint(x: bracketMargin, y: bracketMargin))
        context.addLine(to: CGPoint(x: bracketMargin + bracketSize, y: bracketMargin))
        context.strokePath()
        
        // Top-right bracket
        context.move(to: CGPoint(x: width - bracketMargin - bracketSize, y: bracketMargin))
        context.addLine(to: CGPoint(x: width - bracketMargin, y: bracketMargin))
        context.addLine(to: CGPoint(x: width - bracketMargin, y: bracketMargin + bracketSize))
        context.strokePath()
        
        // Bottom-left bracket
        context.move(to: CGPoint(x: bracketMargin, y: height - bracketMargin - bracketSize))
        context.addLine(to: CGPoint(x: bracketMargin, y: height - bracketMargin))
        context.addLine(to: CGPoint(x: bracketMargin + bracketSize, y: height - bracketMargin))
        context.strokePath()
        
        // Bottom-right bracket
        context.move(to: CGPoint(x: width - bracketMargin - bracketSize, y: height - bracketMargin))
        context.addLine(to: CGPoint(x: width - bracketMargin, y: height - bracketMargin))
        context.addLine(to: CGPoint(x: width - bracketMargin, y: height - bracketMargin - bracketSize))
        context.strokePath()
        
        // Draw "MOCK GLASSES FEED" watermark centered
        drawText(
            "MOCK GLASSES FEED",
            in: context,
            at: CGPoint(x: width / 2, y: height / 2),
            fontSize: 48,
            color: UIColor.white.withAlphaComponent(0.6),
            centered: true
        )
        
        // Draw timestamp in bottom-left
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss.SSS"
        let timestamp = dateFormatter.string(from: Date())
        
        drawText(
            timestamp,
            in: context,
            at: CGPoint(x: 20, y: height - 30),
            fontSize: 24,
            color: UIColor.white.withAlphaComponent(0.8),
            centered: false
        )
        
        // Draw frame counter in bottom-right
        drawText(
            "Frame: \(frameCount)",
            in: context,
            at: CGPoint(x: width - 20, y: height - 30),
            fontSize: 20,
            color: UIColor.white.withAlphaComponent(0.6),
            centered: false,
            rightAligned: true
        )
        
        // Draw resolution in top-right
        drawText(
            "1280×720 @ 30fps",
            in: context,
            at: CGPoint(x: width - 20, y: 30),
            fontSize: 16,
            color: UIColor.white.withAlphaComponent(0.5),
            centered: false,
            rightAligned: true
        )
    }
    
    private func drawText(
        _ text: String,
        in context: CGContext,
        at point: CGPoint,
        fontSize: CGFloat,
        color: UIColor,
        centered: Bool,
        rightAligned: Bool = false
    ) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: color
        ]
        
        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributedString.size()
        
        var x = point.x
        if centered {
            x -= textSize.width / 2
        } else if rightAligned {
            x -= textSize.width
        }
        
        // CGContext has flipped coordinates, so we need to transform
        context.saveGState()
        context.translateBy(x: 0, y: CGFloat(Config.videoHeight))
        context.scaleBy(x: 1, y: -1)
        
        let drawPoint = CGPoint(x: x, y: CGFloat(Config.videoHeight) - point.y - textSize.height / 2)
        attributedString.draw(at: drawPoint)
        
        context.restoreGState()
    }
    
    // MARK: - Audio Generation
    
    private func generateAudioBuffer() {
        guard isAudioStreaming, let format = audioFormat else { return }
        
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: Config.audioBufferSize
        ) else { return }
        
        buffer.frameLength = Config.audioBufferSize
        
        // Generate near-silent audio (very low amplitude noise)
        // This allows speech recognition to stay active without actual audio
        if let channelData = buffer.floatChannelData?[0] {
            for i in 0..<Int(Config.audioBufferSize) {
                // Very quiet white noise (nearly silent)
                channelData[i] = Float.random(in: -0.001...0.001)
            }
        }
        
        audioBufferSubject.send(buffer)
    }
}
