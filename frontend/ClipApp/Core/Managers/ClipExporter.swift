import AVFoundation
import CoreMedia
import CoreVideo
import CoreImage
import Combine
import UIKit

/// Exports synchronized video and audio buffers to a movie file.
/// Uses AVAssetWriter to mux video frames and audio buffers into a .mov file.
///
/// ## Design
/// This exporter passes raw YUV pixel buffers directly to the H.264 hardware encoder
/// without any manual conversion. This is fast and reliable because iOS's VideoToolbox
/// natively supports the YUV 420v format from Meta glasses.
///
/// ## Usage
/// ```swift
/// let exporter = ClipExporter()
/// let url = try await exporter.exportWithHostTimeSync(
///     videoFrames: frames,
///     audioBuffers: audio,
///     config: .default
/// )
/// ```
final class ClipExporter {
    
    // MARK: - Types
    
    /// A timestamped video frame for export
    struct TimestampedVideoFrame {
        let pixelBuffer: CVPixelBuffer
        let presentationTime: CMTime
    }
    
    /// A timestamped audio buffer for export
    struct TimestampedAudioSample {
        let sampleBuffer: CMSampleBuffer
        let presentationTime: CMTime
    }
    
    /// Export configuration
    struct ExportConfig {
        let videoSize: CGSize
        let frameRate: Int32
        let videoBitRate: Int
        let audioSampleRate: Double
        let audioChannels: Int
        let isPortrait: Bool
        let generateThumbnail: Bool
        
        static let `default` = ExportConfig(
            videoSize: CGSize(width: 1280, height: 720),
            frameRate: 30,
            videoBitRate: 5_000_000,
            audioSampleRate: 16000,
            audioChannels: 1,
            isPortrait: false,
            generateThumbnail: false
        )
    }
    
    /// Export result containing URL and optional thumbnail
    struct ExportResult {
        let videoURL: URL
        let thumbnail: UIImage?
        let isPortrait: Bool
    }
    
    // MARK: - Errors
    
    enum ExportError: Error, LocalizedError {
        case failedToCreateWriter(String)
        case failedToStartWriting
        case failedToFinishWriting(String)
        case noVideoFrames
        case invalidPixelBuffer
        case cancelled
        case trimFailed(String)
        case exportSessionFailed(String)
        
        var errorDescription: String? {
            switch self {
            case .failedToCreateWriter(let reason):
                return "Failed to create writer: \(reason)"
            case .failedToStartWriting:
                return "Failed to start writing"
            case .failedToFinishWriting(let reason):
                return "Failed to finish writing: \(reason)"
            case .noVideoFrames:
                return "No video frames to export"
            case .invalidPixelBuffer:
                return "Invalid pixel buffer"
            case .cancelled:
                return "Export was cancelled"
            case .trimFailed(let reason):
                return "Trim failed: \(reason)"
            case .exportSessionFailed(let reason):
                return "Export session failed: \(reason)"
            }
        }
    }
    
    // MARK: - Progress Reporting
    
    typealias ProgressCallback = (Int, Int) -> Void
    var onProgress: ProgressCallback?
    
    // MARK: - Properties
    
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    
    // Lazy CIContext only for thumbnail generation (not used during export)
    private lazy var ciContext = CIContext(options: [.useSoftwareRenderer: false])
    
    // MARK: - Initialization
    
    init() {}
    
    // MARK: - Export
    
    /// Export video frames and audio buffers to a movie file
    /// - Parameters:
    ///   - videoFrames: Array of timestamped video frames
    ///   - audioBuffers: Array of timestamped audio sample buffers
    ///   - config: Export configuration
    /// - Returns: URL of the exported movie file
    func export(
        videoFrames: [TimestampedVideoFrame],
        audioBuffers: [TimestampedAudioSample],
        config: ExportConfig = .default
    ) async throws -> URL {
        print("🎬 Starting export: \(videoFrames.count) video frames, \(audioBuffers.count) audio buffers")
        print("🎬 Config video size: \(config.videoSize.width)x\(config.videoSize.height)")
        
        guard !videoFrames.isEmpty else {
            print("❌ No video frames to export")
            throw ExportError.noVideoFrames
        }
        
        // Log first frame details for debugging
        let firstFrame = videoFrames[0].pixelBuffer
        let frameWidth = CVPixelBufferGetWidth(firstFrame)
        let frameHeight = CVPixelBufferGetHeight(firstFrame)
        let pixelFormat = CVPixelBufferGetPixelFormatType(firstFrame)
        let formatString = pixelFormatToString(pixelFormat)
        print("🎬 First frame: \(frameWidth)x\(frameHeight), format: \(formatString) (0x\(String(pixelFormat, radix: 16)))")
        
        // Ensure export config matches the actual frame size (no resizing during export)
        var finalConfig = config
        let actualSize = CGSize(width: frameWidth, height: frameHeight)
        if config.videoSize != actualSize {
            finalConfig = ExportConfig(
                videoSize: actualSize,
                frameRate: config.frameRate,
                videoBitRate: config.videoBitRate,
                audioSampleRate: config.audioSampleRate,
                audioChannels: config.audioChannels,
                isPortrait: config.isPortrait,
                generateThumbnail: config.generateThumbnail
            )
            print("🎬 Using actual frame size: \(frameWidth)x\(frameHeight)")
        }
        
        // Create output URL in temp directory
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")
        
        // Remove existing file if any
        try? FileManager.default.removeItem(at: outputURL)
        
        // Create asset writer
        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
            print("✅ Created AVAssetWriter")
        } catch {
            print("❌ Failed to create writer: \(error.localizedDescription)")
            throw ExportError.failedToCreateWriter(error.localizedDescription)
        }
        
        self.assetWriter = writer
        
        // Setup video input - pass through YUV directly to H.264 encoder (no conversion)
        setupVideoInput(writer: writer, config: finalConfig, sourcePixelFormat: pixelFormat)
        print("✅ Video input configured (format: \(formatString))")
        
        // Skip audio input for now (debugging video first)
        // if !audioBuffers.isEmpty {
        //     setupAudioInput(writer: writer, config: finalConfig)
        //     print("✅ Audio input configured")
        // }
        print("⚠️ Audio input skipped (debugging video first)")
        
        // Start writing
        guard writer.startWriting() else {
            let errorMsg = writer.error?.localizedDescription ?? "Unknown error"
            print("❌ Failed to start writing: \(errorMsg)")
            throw ExportError.failedToStartWriting
        }
        print("✅ Writer started")
        
        // Find the earliest timestamp to use as our base time for relative calculations
        let baseTime = videoFrames.first?.presentationTime ?? .zero
        
        // Start session at .zero since we'll provide frames with relative presentation times (0, 0.033, etc.)
        writer.startSession(atSourceTime: .zero)
        
        // Check writer status after starting session
        if writer.status == .failed {
            let errorMsg = writer.error?.localizedDescription ?? "Unknown error"
            print("❌ Writer failed after startSession: \(errorMsg)")
            throw ExportError.failedToStartWriting
        }
        print("✅ Session started at time zero (base time for offset: \(baseTime.seconds)s)")
        
        // Write video frames
        try await writeVideoFrames(videoFrames, baseTime: baseTime)
        
        // Skip audio for now to isolate the problem
        // TODO: Re-enable audio once video export works
        if !audioBuffers.isEmpty {
            print("⚠️ Skipping \(audioBuffers.count) audio buffers (debugging video first)")
            // try await writeAudioBuffers(audioBuffers, baseTime: baseTime)
        }
        
        // Check writer status before finishing
        print("🎬 Finishing write... (writer status: \(writerStatusString(writer.status)))")
        if let error = writer.error {
            print("🎬 Writer has error before finish: \(error.localizedDescription)")
        }
        
        await writer.finishWriting()
        
        print("🎬 Finish complete (writer status: \(writerStatusString(writer.status)))")
        
        if let error = writer.error {
            print("❌ Writer error after finish: \(error.localizedDescription)")
            throw ExportError.failedToFinishWriting(error.localizedDescription)
        }
        
        print("✅ Export complete: \(outputURL.lastPathComponent)")
        
        return outputURL
    }
    
    /// Export video frames with optional portrait cropping and thumbnail generation
    /// - Parameters:
    ///   - videoFrames: Array of timestamped video frames
    ///   - audioBuffers: Array of timestamped audio sample buffers
    ///   - config: Export configuration (use .portrait for vertical video)
    /// - Returns: ExportResult containing video URL and optional thumbnail
    func exportWithResult(
        videoFrames: [TimestampedVideoFrame],
        audioBuffers: [TimestampedAudioSample],
        config: ExportConfig = .default
    ) async throws -> ExportResult {
        print("🎬 Starting export with result: portrait=\(config.isPortrait), thumbnail=\(config.generateThumbnail)")
        
        // Generate thumbnail from first frame before any processing
        var thumbnail: UIImage? = nil
        if config.generateThumbnail, let firstFrame = videoFrames.first {
            thumbnail = generateThumbnail(from: firstFrame.pixelBuffer, isPortrait: config.isPortrait)
            print("🖼️ Thumbnail generated: \(thumbnail != nil)")
        }
        
        // If portrait mode, transform frames to portrait orientation (center crop)
        let processedFrames: [TimestampedVideoFrame]
        if config.isPortrait {
            print("📱 Processing frames for portrait mode (center crop)...")
            processedFrames = videoFrames.compactMap { frame -> TimestampedVideoFrame? in
                guard let croppedBuffer = cropToPortrait(frame.pixelBuffer) else {
                    return nil
                }
                return TimestampedVideoFrame(
                    pixelBuffer: croppedBuffer,
                    presentationTime: frame.presentationTime
                )
            }
            print("📱 Processed \(processedFrames.count) portrait frames")
        } else {
            processedFrames = videoFrames
        }
        
        // Export the video
        let videoURL = try await export(
            videoFrames: processedFrames,
            audioBuffers: audioBuffers,
            config: config
        )
        
        return ExportResult(
            videoURL: videoURL,
            thumbnail: thumbnail,
            isPortrait: config.isPortrait
        )
    }
    
    /// Generate a thumbnail image from a pixel buffer
    /// - Parameters:
    ///   - pixelBuffer: Source pixel buffer
    ///   - isPortrait: If true, crop to portrait aspect ratio
    /// - Returns: Thumbnail UIImage
    func generateThumbnail(from pixelBuffer: CVPixelBuffer, isPortrait: Bool = false, maxSize: CGFloat = 400) -> UIImage? {
        var ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        
        // If portrait, crop to center 9:16 region
        if isPortrait {
            let width = ciImage.extent.width
            let height = ciImage.extent.height
            
            // Calculate portrait crop (9:16 from center of landscape 16:9)
            let targetAspect: CGFloat = 9.0 / 16.0
            let cropWidth = height * targetAspect // Use height to determine width for 9:16
            let cropX = (width - cropWidth) / 2
            
            let cropRect = CGRect(x: cropX, y: 0, width: cropWidth, height: height)
            ciImage = ciImage.cropped(to: cropRect)
        }
        
        // Scale down for thumbnail size
        let scale = min(maxSize / ciImage.extent.width, maxSize / ciImage.extent.height, 1.0)
        if scale < 1.0 {
            ciImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        
        // Render to CGImage then UIImage
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        
        return UIImage(cgImage: cgImage)
    }
    
    /// Generate thumbnail from a video file URL
    /// - Parameters:
    ///   - url: Video file URL
    ///   - time: Time to capture thumbnail (default: 0.5 seconds in)
    /// - Returns: Thumbnail UIImage
    func generateThumbnail(from url: URL, at time: TimeInterval = 0.5) async -> UIImage? {
        let asset = AVAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: 400, height: 400)
        
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        
        do {
            let cgImage = try imageGenerator.copyCGImage(at: cmTime, actualTime: nil)
            return UIImage(cgImage: cgImage)
        } catch {
            print("⚠️ Failed to generate thumbnail: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Crop a landscape pixel buffer to portrait (9:16) aspect ratio
    /// - Parameter pixelBuffer: Source landscape pixel buffer
    /// - Returns: New pixel buffer cropped to portrait aspect ratio
    private func cropToPortrait(_ pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let width = ciImage.extent.width
        let height = ciImage.extent.height
        
        // Calculate 9:16 portrait crop from center
        let targetAspect: CGFloat = 9.0 / 16.0
        let cropWidth = height * targetAspect
        let cropX = (width - cropWidth) / 2
        
        let cropRect = CGRect(x: cropX, y: 0, width: cropWidth, height: height)
        let croppedImage = ciImage.cropped(to: cropRect)
        
        // Translate to origin (CIImage.cropped keeps original coordinates)
        let translatedImage = croppedImage.transformed(by: CGAffineTransform(translationX: -cropRect.origin.x, y: 0))
        
        // Calculate output dimensions (divisible by 16 for H.264)
        let outputWidth = (Int(cropWidth) + 15) / 16 * 16
        let outputHeight = (Int(height) + 15) / 16 * 16
        
        // Create output pixel buffer with IOSurface for hardware encoder compatibility
        var outputBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferWidthKey: outputWidth,
            kCVPixelBufferHeightKey: outputHeight,
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any]  // Enable IOSurface backing
        ]
        
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            outputWidth,
            outputHeight,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &outputBuffer
        )
        
        guard status == kCVReturnSuccess, let output = outputBuffer else {
            print("⚠️ Failed to create portrait pixel buffer: \(status)")
            return nil
        }
        
        // Scale to fill the output buffer dimensions
        let scaleX = CGFloat(outputWidth) / translatedImage.extent.width
        let scaleY = CGFloat(outputHeight) / translatedImage.extent.height
        let scaledImage = translatedImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        
        // Render to output buffer
        ciContext.render(scaledImage, to: output)
        
        return output
    }
    
    /// Export from raw buffers with host time synchronization
    /// - Parameters:
    ///   - videoFrames: Video pixel buffers with host times
    ///   - audioBuffers: Audio buffers with host times
    ///   - config: Export configuration
    /// - Returns: URL of the exported movie file
    func exportWithHostTimeSync(
        videoFrames: [(pixelBuffer: CVPixelBuffer, hostTime: UInt64)],
        audioBuffers: [TimestampedAudioBuffer],
        config: ExportConfig = .default
    ) async throws -> URL {
        print("🎬 exportWithHostTimeSync called with \(videoFrames.count) video frames, \(audioBuffers.count) audio buffers")
        
        guard !videoFrames.isEmpty else {
            print("❌ No video frames provided")
            throw ExportError.noVideoFrames
        }
        
        // Convert host times to CMTime
        // Find the earliest host time as our reference point
        let videoStartTime = videoFrames.first?.hostTime ?? 0
        let audioStartTime = audioBuffers.first?.hostTime ?? UInt64.max
        let baseHostTime = min(videoStartTime, audioStartTime)
        
        print("🎬 Converting frames... base host time: \(baseHostTime)")
        
        // Convert video frames
        let convertedVideoFrames = videoFrames.map { frame -> TimestampedVideoFrame in
            let relativeTime = hostTimeToCMTime(frame.hostTime, relativeTo: baseHostTime)
            return TimestampedVideoFrame(pixelBuffer: frame.pixelBuffer, presentationTime: relativeTime)
        }
        
        // Convert audio buffers to CMSampleBuffers
        var convertedAudioBuffers: [TimestampedAudioSample] = []
        for audioBuffer in audioBuffers {
            if let sampleBuffer = createAudioSampleBuffer(from: audioBuffer, baseHostTime: baseHostTime) {
                let relativeTime = hostTimeToCMTime(audioBuffer.hostTime, relativeTo: baseHostTime)
                convertedAudioBuffers.append(TimestampedAudioSample(
                    sampleBuffer: sampleBuffer,
                    presentationTime: relativeTime
                ))
            }
        }
        
        print("🎬 Converted \(convertedVideoFrames.count) video frames, \(convertedAudioBuffers.count) audio buffers")
        
        return try await export(
            videoFrames: convertedVideoFrames,
            audioBuffers: convertedAudioBuffers,
            config: config
        )
    }
    
    /// Export from raw buffers with host time synchronization and return ExportResult with thumbnail
    /// - Parameters:
    ///   - videoFrames: Video pixel buffers with host times
    ///   - audioBuffers: Audio buffers with host times
    ///   - config: Export configuration (use .portrait for vertical video)
    /// - Returns: ExportResult containing video URL and optional thumbnail
    func exportWithHostTimeSyncResult(
        videoFrames: [(pixelBuffer: CVPixelBuffer, hostTime: UInt64)],
        audioBuffers: [TimestampedAudioBuffer],
        config: ExportConfig = .default
    ) async throws -> ExportResult {
        print("🎬 exportWithHostTimeSyncResult: portrait=\(config.isPortrait), thumbnail=\(config.generateThumbnail)")
        
        guard !videoFrames.isEmpty else {
            throw ExportError.noVideoFrames
        }
        
        // Generate thumbnail from first frame
        var thumbnail: UIImage? = nil
        if config.generateThumbnail, let firstFrame = videoFrames.first?.pixelBuffer {
            thumbnail = generateThumbnail(from: firstFrame, isPortrait: config.isPortrait)
            print("🖼️ Thumbnail generated: \(thumbnail != nil)")
        }
        
        // Convert host times to CMTime
        let videoStartTime = videoFrames.first?.hostTime ?? 0
        let audioStartTime = audioBuffers.first?.hostTime ?? UInt64.max
        let baseHostTime = min(videoStartTime, audioStartTime)
        
        // Convert and optionally crop video frames
        let convertedVideoFrames: [TimestampedVideoFrame]
        if config.isPortrait {
            print("📱 Processing frames for portrait mode...")
            convertedVideoFrames = videoFrames.compactMap { frame -> TimestampedVideoFrame? in
                guard let croppedBuffer = cropToPortrait(frame.pixelBuffer) else {
                    return nil
                }
                let relativeTime = hostTimeToCMTime(frame.hostTime, relativeTo: baseHostTime)
                return TimestampedVideoFrame(pixelBuffer: croppedBuffer, presentationTime: relativeTime)
            }
        } else {
            convertedVideoFrames = videoFrames.map { frame in
                let relativeTime = hostTimeToCMTime(frame.hostTime, relativeTo: baseHostTime)
                return TimestampedVideoFrame(pixelBuffer: frame.pixelBuffer, presentationTime: relativeTime)
            }
        }
        
        // Convert audio buffers
        var convertedAudioBuffers: [TimestampedAudioSample] = []
        for audioBuffer in audioBuffers {
            if let sampleBuffer = createAudioSampleBuffer(from: audioBuffer, baseHostTime: baseHostTime) {
                let relativeTime = hostTimeToCMTime(audioBuffer.hostTime, relativeTo: baseHostTime)
                convertedAudioBuffers.append(TimestampedAudioSample(
                    sampleBuffer: sampleBuffer,
                    presentationTime: relativeTime
                ))
            }
        }
        
        print("🎬 Converted \(convertedVideoFrames.count) frames, \(convertedAudioBuffers.count) audio buffers")
        
        // Update config with actual frame dimensions after portrait processing
        var finalConfig = config
        if config.isPortrait, let firstFrame = convertedVideoFrames.first?.pixelBuffer {
            let actualWidth = CVPixelBufferGetWidth(firstFrame)
            let actualHeight = CVPixelBufferGetHeight(firstFrame)
            finalConfig = ExportConfig(
                videoSize: CGSize(width: actualWidth, height: actualHeight),
                frameRate: config.frameRate,
                videoBitRate: config.videoBitRate,
                audioSampleRate: config.audioSampleRate,
                audioChannels: config.audioChannels,
                isPortrait: config.isPortrait,
                generateThumbnail: config.generateThumbnail
            )
            print("🎬 Updated config for portrait: \(actualWidth)x\(actualHeight)")
        }
        
        let videoURL = try await export(
            videoFrames: convertedVideoFrames,
            audioBuffers: convertedAudioBuffers,
            config: finalConfig
        )
        
        return ExportResult(
            videoURL: videoURL,
            thumbnail: thumbnail,
            isPortrait: config.isPortrait
        )
    }
    
    // MARK: - Trim
    
    /// Trim a video file to a specific time range using passthrough (no re-encoding)
    /// - Parameters:
    ///   - sourceURL: URL of the source video file
    ///   - startTime: Start time of the trim
    ///   - endTime: End time of the trim
    /// - Returns: URL of the trimmed video file
    func trimClip(sourceURL: URL, startTime: CMTime, endTime: CMTime) async throws -> URL {
        let asset = AVAsset(url: sourceURL)
        
        // Validate time range
        let duration = try await asset.load(.duration)
        let clampedStart = CMTimeClampToRange(startTime, range: CMTimeRange(start: .zero, end: duration))
        let clampedEnd = CMTimeClampToRange(endTime, range: CMTimeRange(start: clampedStart, end: duration))
        
        // Create export session with passthrough preset for fast, lossless trim
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw ExportError.trimFailed("Could not create export session")
        }
        
        // Create output URL
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("trimmed_\(UUID().uuidString)")
            .appendingPathExtension("mov")
        
        // Remove existing file if any
        try? FileManager.default.removeItem(at: outputURL)
        
        // Configure export session
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mov
        exportSession.timeRange = CMTimeRange(start: clampedStart, end: clampedEnd)
        
        // Export
        await exportSession.export()
        
        // Check for errors
        switch exportSession.status {
        case .completed:
            print("✂️ Trimmed clip to: \(outputURL.lastPathComponent)")
            return outputURL
        case .failed:
            throw ExportError.exportSessionFailed(exportSession.error?.localizedDescription ?? "Unknown error")
        case .cancelled:
            throw ExportError.cancelled
        default:
            throw ExportError.exportSessionFailed("Unexpected export status: \(exportSession.status.rawValue)")
        }
    }
    
    /// Trim a video file and optionally re-encode with specific quality settings
    /// - Parameters:
    ///   - sourceURL: URL of the source video file
    ///   - startTime: Start time of the trim
    ///   - endTime: End time of the trim
    ///   - preset: Export preset (default: high quality)
    /// - Returns: URL of the trimmed video file
    func trimClipWithReencode(
        sourceURL: URL,
        startTime: CMTime,
        endTime: CMTime,
        preset: String = AVAssetExportPresetHighestQuality
    ) async throws -> URL {
        let asset = AVAsset(url: sourceURL)
        
        // Validate time range
        let duration = try await asset.load(.duration)
        let clampedStart = CMTimeClampToRange(startTime, range: CMTimeRange(start: .zero, end: duration))
        let clampedEnd = CMTimeClampToRange(endTime, range: CMTimeRange(start: clampedStart, end: duration))
        
        // Create export session
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw ExportError.trimFailed("Could not create export session with preset: \(preset)")
        }
        
        // Create output URL
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("trimmed_\(UUID().uuidString)")
            .appendingPathExtension("mp4")
        
        // Remove existing file if any
        try? FileManager.default.removeItem(at: outputURL)
        
        // Configure export session
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.timeRange = CMTimeRange(start: clampedStart, end: clampedEnd)
        exportSession.shouldOptimizeForNetworkUse = true
        
        // Export
        await exportSession.export()
        
        // Check for errors
        switch exportSession.status {
        case .completed:
            print("✂️ Trimmed and re-encoded clip to: \(outputURL.lastPathComponent)")
            return outputURL
        case .failed:
            throw ExportError.exportSessionFailed(exportSession.error?.localizedDescription ?? "Unknown error")
        case .cancelled:
            throw ExportError.cancelled
        default:
            throw ExportError.exportSessionFailed("Unexpected export status: \(exportSession.status.rawValue)")
        }
    }
    
    // MARK: - Private Methods
    
    private func setupVideoInput(
        writer: AVAssetWriter,
        config: ExportConfig,
        sourcePixelFormat: OSType
    ) {
        // Use EXACT source dimensions - don't pad
        let width = Int(config.videoSize.width)
        let height = Int(config.videoSize.height)
        
        print("📹 Video dimensions: \(width)x\(height) (exact, no padding)")
        
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: config.videoBitRate,
                AVVideoExpectedSourceFrameRateKey: config.frameRate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264BaselineAutoLevel
            ]
        ]
        
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = false
        
        // Use pixel buffer adaptor - let it handle format conversion
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: nil // Let system figure out the format
        )
        
        writer.add(input)
        self.videoInput = input
        self.pixelBufferAdaptor = adaptor
    }
    
    private func setupAudioInput(writer: AVAssetWriter, config: ExportConfig) {
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: config.audioSampleRate,
            AVNumberOfChannelsKey: config.audioChannels,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        input.expectsMediaDataInRealTime = false
        
        writer.add(input)
        
        self.audioInput = input
    }
    
    private func writeVideoFrames(_ frames: [TimestampedVideoFrame], baseTime: CMTime) async throws {
        guard let input = videoInput, let adaptor = pixelBufferAdaptor else {
            print("⚠️ Video input or adaptor not available")
            return
        }
        
        print("📹 Writing \(frames.count) video frames (adaptor method)...")
        
        var writtenCount = 0
        
        for (index, frame) in frames.enumerated() {
            // Wait for input to be ready
            while !input.isReadyForMoreMediaData {
                if let writer = assetWriter, writer.status == .failed {
                    let errorMsg = writer.error?.localizedDescription ?? "Unknown"
                    print("❌ Writer failed at frame \(index): \(errorMsg)")
                    throw ExportError.failedToFinishWriting(errorMsg)
                }
                try await Task.sleep(nanoseconds: 1_000_000) // 1ms
            }
            
            // Calculate presentation time relative to base
            let presentationTime = CMTimeSubtract(frame.presentationTime, baseTime)
            let adjustedTime = CMTimeMaximum(presentationTime, .zero)
            
            // Append via adaptor
            if adaptor.append(frame.pixelBuffer, withPresentationTime: adjustedTime) {
                writtenCount += 1
            } else {
                let writerStatus = assetWriter?.status ?? .unknown
                let writerError = assetWriter?.error?.localizedDescription ?? "none"
                print("❌ Frame \(index) append FAILED at time \(adjustedTime.seconds)s")
                print("❌ Writer status: \(writerStatusString(writerStatus)), Error: \(writerError)")
                
                input.markAsFinished()
                throw ExportError.failedToFinishWriting("Frame \(index) failed: \(writerError)")
            }
            
            // Progress every 100 frames
            if writtenCount % 100 == 0 && writtenCount > 0 {
                print("📹 Progress: \(writtenCount)/\(frames.count)")
                onProgress?(writtenCount, frames.count)
            }
        }
        
        input.markAsFinished()
        print("✅ Wrote \(writtenCount)/\(frames.count) video frames")
        onProgress?(writtenCount, frames.count)
    }
    
    private func writeAudioBuffers(_ buffers: [TimestampedAudioSample], baseTime: CMTime) async throws {
        guard let input = audioInput else {
            print("⚠️ Audio input not available")
            return
        }
        
        print("🎤 Writing \(buffers.count) audio buffers (sequential)...")
        
        var writtenCount = 0
        
        for (index, buffer) in buffers.enumerated() {
            // Wait for input to be ready
            while !input.isReadyForMoreMediaData {
                if let writer = assetWriter, writer.status == .failed {
                    let errorMsg = writer.error?.localizedDescription ?? "Unknown"
                    print("❌ Writer failed at audio buffer \(index): \(errorMsg)")
                    throw ExportError.failedToFinishWriting(errorMsg)
                }
                try await Task.sleep(nanoseconds: 1_000_000) // 1ms
            }
            
            if input.append(buffer.sampleBuffer) {
                writtenCount += 1
            } else {
                let writerStatus = assetWriter?.status ?? .unknown
                let writerError = assetWriter?.error?.localizedDescription ?? "none"
                print("⚠️ Audio buffer \(index) append failed. Status: \(writerStatusString(writerStatus)), Error: \(writerError)")
                
                if writerStatus == .failed {
                    throw ExportError.failedToFinishWriting(writerError)
                }
            }
        }
        
        input.markAsFinished()
        print("✅ Wrote \(writtenCount)/\(buffers.count) audio buffers")
    }
    
    private func hostTimeToCMTime(_ hostTime: UInt64, relativeTo baseHostTime: UInt64) -> CMTime {
        var timebaseInfo = mach_timebase_info_data_t()
        mach_timebase_info(&timebaseInfo)
        
        let elapsedHostTime = hostTime - baseHostTime
        let nanoseconds = elapsedHostTime * UInt64(timebaseInfo.numer) / UInt64(timebaseInfo.denom)
        let seconds = Double(nanoseconds) / 1_000_000_000.0
        
        return CMTime(seconds: seconds, preferredTimescale: 600)
    }
    
    private func createAudioSampleBuffer(from timestampedBuffer: TimestampedAudioBuffer, baseHostTime: UInt64) -> CMSampleBuffer? {
        let buffer = timestampedBuffer.buffer
        let formatPtr = buffer.format.streamDescription
        
        // Calculate presentation time
        let presentationTime = hostTimeToCMTime(timestampedBuffer.hostTime, relativeTo: baseHostTime)
        
        // Create audio format description
        var formatDescription: CMAudioFormatDescription?
        let status = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: formatPtr,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        )
        
        guard status == noErr, let audioFormatDescription = formatDescription else {
            return nil
        }
        
        // Create timing info
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: CMTimeValue(buffer.frameLength), timescale: CMTimeScale(buffer.format.sampleRate)),
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: .invalid
        )
        
        // Create sample buffer
        var sampleBuffer: CMSampleBuffer?
        guard let channelData = buffer.floatChannelData else { return nil }
        
        // Create a block buffer from the audio data
        let dataSize = Int(buffer.frameLength) * MemoryLayout<Float>.size
        var blockBuffer: CMBlockBuffer?
        
        CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: dataSize,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: dataSize,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        
        guard let block = blockBuffer else { return nil }
        
        // Copy audio data to block buffer
        CMBlockBufferReplaceDataBytes(
            with: channelData[0],
            blockBuffer: block,
            offsetIntoDestination: 0,
            dataLength: dataSize
        )
        
        // Create sample buffer
        CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: block,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: audioFormatDescription,
            sampleCount: CMItemCount(buffer.frameLength),
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )
        
        return sampleBuffer
    }
    
    /// Convert writer status to human-readable string
    private func writerStatusString(_ status: AVAssetWriter.Status) -> String {
        switch status {
        case .unknown: return "unknown"
        case .writing: return "writing"
        case .completed: return "completed"
        case .failed: return "failed"
        case .cancelled: return "cancelled"
        @unknown default: return "unknown(\(status.rawValue))"
        }
    }
    
    /// Convert pixel format type to human-readable string
    private func pixelFormatToString(_ format: OSType) -> String {
        switch format {
        case kCVPixelFormatType_32BGRA:
            return "BGRA"
        case kCVPixelFormatType_32ARGB:
            return "ARGB"
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
            return "420v (YUV BiPlanar)"
        case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
            return "420f (YUV BiPlanar Full)"
        case kCVPixelFormatType_420YpCbCr8Planar:
            return "y420 (YUV Planar)"
        default:
            // Convert OSType to 4-char string
            let chars = [
                Character(UnicodeScalar((format >> 24) & 0xFF)!),
                Character(UnicodeScalar((format >> 16) & 0xFF)!),
                Character(UnicodeScalar((format >> 8) & 0xFF)!),
                Character(UnicodeScalar(format & 0xFF)!)
            ]
            return String(chars)
        }
    }
    
}
