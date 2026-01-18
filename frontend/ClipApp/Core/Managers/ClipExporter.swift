import AVFoundation
import CoreMedia
import CoreVideo
import CoreImage
import Combine

/// Exports synchronized video and audio buffers to a movie file.
/// Uses AVAssetWriter to mux video frames and audio buffers into a .mov file.
///
/// ## Usage
/// ```swift
/// let exporter = ClipExporter()
/// let url = try await exporter.export(
///     videoFrames: videoBuffers,
///     audioBuffers: audioBuffers,
///     videoSize: CGSize(width: 1280, height: 720)
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
        
        static let `default` = ExportConfig(
            videoSize: CGSize(width: 1280, height: 720),
            frameRate: 30,
            videoBitRate: 5_000_000, // 5 Mbps
            audioSampleRate: 16000,
            audioChannels: 1
        )
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
    
    /// Progress callback: (framesWritten, totalFrames)
    typealias ProgressCallback = (Int, Int) -> Void
    
    /// Called periodically during export with progress updates
    var onProgress: ProgressCallback?
    
    // MARK: - Properties
    
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    
    /// CIContext for converting pixel buffers to BGRA format (GPU-accelerated)
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    
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
        
        // Round dimensions to be divisible by 16 for H.264 compatibility
        let adjustedWidth = (frameWidth + 15) / 16 * 16
        let adjustedHeight = (frameHeight + 15) / 16 * 16
        let adjustedConfig = ExportConfig(
            videoSize: CGSize(width: adjustedWidth, height: adjustedHeight),
            frameRate: config.frameRate,
            videoBitRate: config.videoBitRate,
            audioSampleRate: config.audioSampleRate,
            audioChannels: config.audioChannels
        )
        
        if adjustedWidth != frameWidth || adjustedHeight != frameHeight {
            print("🎬 Adjusted dimensions for H.264: \(adjustedWidth)x\(adjustedHeight)")
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
        
        // Setup video input with adjusted dimensions
        setupVideoInput(writer: writer, config: adjustedConfig)
        print("✅ Video input configured")
        
        // Setup audio input if we have audio (use original config for audio settings)
        if !audioBuffers.isEmpty {
            setupAudioInput(writer: writer, config: config)
            print("✅ Audio input configured")
        }
        
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
        
        // Write video frames (convert to BGRA using adaptor's pool for H.264 compatibility)
        try await writeVideoFrames(videoFrames, baseTime: baseTime)
        
        // Write audio buffers
        if !audioBuffers.isEmpty {
            try await writeAudioBuffers(audioBuffers, baseTime: baseTime)
        }
        
        // Finish writing
        print("🎬 Finishing write...")
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        
        await writer.finishWriting()
        
        if let error = writer.error {
            print("❌ Writer error after finish: \(error.localizedDescription)")
            throw ExportError.failedToFinishWriting(error.localizedDescription)
        }
        
        print("✅ Export complete: \(outputURL.lastPathComponent)")
        
        return outputURL
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
    
    private func setupVideoInput(writer: AVAssetWriter, config: ExportConfig) {
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: config.videoSize.width,
            AVVideoHeightKey: config.videoSize.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: config.videoBitRate,
                AVVideoExpectedSourceFrameRateKey: config.frameRate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]
        
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = false
        
        // Create pixel buffer adaptor with BGRA format
        // We convert all incoming frames to BGRA before appending, so specify that format here
        let sourcePixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(config.videoSize.width),
            kCVPixelBufferHeightKey as String: Int(config.videoSize.height),
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]
        ]
        
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: sourcePixelBufferAttributes
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
        
        print("📹 Writing \(frames.count) video frames (using adaptor's pixel buffer pool)...")
        print("📹 Initial isReadyForMoreMediaData: \(input.isReadyForMoreMediaData)")
        print("📹 Pixel buffer pool available: \(adaptor.pixelBufferPool != nil)")
        
        if let writer = assetWriter {
            print("📹 Writer status: \(writerStatusString(writer.status))")
        }
        
        var convertedCount = 0
        var skippedCount = 0
        
        for (index, frame) in frames.enumerated() {
            // Convert frame to BGRA format using adaptor's pool (optimized for hardware encoder)
            guard let convertedBuffer = convertToBGRA(frame.pixelBuffer, using: adaptor) else {
                skippedCount += 1
                if skippedCount == 1 {
                    print("⚠️ Failed to convert frame \(index) to BGRA, skipping")
                }
                continue
            }
            
            // Wait for input to be ready with timeout
            var waitCount = 0
            let maxWait = 3000 // 30 second max (3000 * 10ms) - encoding large buffers takes time
            
            while !input.isReadyForMoreMediaData {
                waitCount += 1
                if waitCount > maxWait {
                    let writerStatus = assetWriter?.status ?? .unknown
                    let writerError = assetWriter?.error?.localizedDescription ?? "none"
                    print("❌ Timeout waiting for video input - frame \(index)/\(frames.count)")
                    print("❌ Writer status: \(writerStatusString(writerStatus)), error: \(writerError)")
                    throw ExportError.failedToFinishWriting("Video input not ready after timeout (writer: \(writerStatusString(writerStatus)))")
                }
                
                // Check if writer has failed
                if let writer = assetWriter, writer.status == .failed {
                    let errorMsg = writer.error?.localizedDescription ?? "Unknown writer error"
                    print("❌ Writer failed: \(errorMsg)")
                    throw ExportError.failedToFinishWriting(errorMsg)
                }
                
                // Log every 100 waits (1s)
                if waitCount % 100 == 0 {
                    print("⏳ Waiting for video input... (\(waitCount * 10)ms)")
                }
                
                try await Task.sleep(nanoseconds: 10_000_000) // 10ms
            }
            
            // Calculate presentation time relative to base
            let presentationTime = CMTimeSubtract(frame.presentationTime, baseTime)
            let adjustedTime = CMTimeMaximum(presentationTime, .zero)
            
            // Append the converted BGRA pixel buffer
            if adaptor.append(convertedBuffer, withPresentationTime: adjustedTime) {
                convertedCount += 1
            } else {
                print("⚠️ Failed to append video frame \(index) at \(adjustedTime.seconds)s")
                // Check if writer failed
                if let writer = assetWriter, writer.status == .failed {
                    let errorMsg = writer.error?.localizedDescription ?? "Unknown writer error"
                    throw ExportError.failedToFinishWriting(errorMsg)
                }
            }
            
            // Report progress every 10 frames for smooth UI updates
            if convertedCount % 10 == 0 {
                onProgress?(convertedCount, frames.count)
            }
            
            // Log progress every 100 frames
            if convertedCount > 0 && convertedCount % 100 == 0 {
                print("📹 Written \(convertedCount)/\(frames.count) video frames")
            }
        }
        
        // Report final progress
        onProgress?(convertedCount, frames.count)
        
        if skippedCount > 0 {
            print("⚠️ Skipped \(skippedCount) frames due to conversion failure")
        }
        print("✅ Finished writing \(convertedCount) video frames")
    }
    
    private func writeAudioBuffers(_ buffers: [TimestampedAudioSample], baseTime: CMTime) async throws {
        guard let input = audioInput else {
            print("⚠️ Audio input not available")
            return
        }
        
        print("🎤 Writing \(buffers.count) audio buffers...")
        
        for (index, buffer) in buffers.enumerated() {
            // Wait for input to be ready with timeout
            var waitCount = 0
            let maxWait = 3000 // 30 second max (3000 * 10ms) - encoding large buffers takes time
            
            while !input.isReadyForMoreMediaData {
                waitCount += 1
                if waitCount > maxWait {
                    print("❌ Timeout waiting for audio input - buffer \(index)/\(buffers.count)")
                    throw ExportError.failedToFinishWriting("Audio input not ready after timeout")
                }
                
                // Check if writer has failed
                if let writer = assetWriter, writer.status == .failed {
                    let errorMsg = writer.error?.localizedDescription ?? "Unknown writer error"
                    print("❌ Writer failed: \(errorMsg)")
                    throw ExportError.failedToFinishWriting(errorMsg)
                }
                
                // Log every 100 waits (1s)
                if waitCount % 100 == 0 {
                    print("⏳ Waiting for audio input... (\(waitCount * 10)ms)")
                }
                
                try await Task.sleep(nanoseconds: 10_000_000) // 10ms
            }
            
            // Append sample buffer
            if !input.append(buffer.sampleBuffer) {
                print("⚠️ Failed to append audio buffer \(index)")
                // Check if writer failed
                if let writer = assetWriter, writer.status == .failed {
                    let errorMsg = writer.error?.localizedDescription ?? "Unknown writer error"
                    throw ExportError.failedToFinishWriting(errorMsg)
                }
            }
        }
        
        print("✅ Finished writing \(buffers.count) audio buffers")
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
    
    /// Convert a pixel buffer from any format to BGRA format using the adaptor's pixel buffer pool
    /// - Parameters:
    ///   - pixelBuffer: Source pixel buffer (can be YUV, BGRA, etc.)
    ///   - adaptor: The pixel buffer adaptor whose pool will be used for output buffers
    /// - Returns: A new pixel buffer in BGRA format from the adaptor's pool, or nil if conversion fails
    private func convertToBGRA(
        _ pixelBuffer: CVPixelBuffer,
        using adaptor: AVAssetWriterInputPixelBufferAdaptor
    ) -> CVPixelBuffer? {
        // Get buffer from adaptor's pool (optimized for hardware encoder)
        guard let pool = adaptor.pixelBufferPool else {
            print("⚠️ Pixel buffer pool not available")
            return nil
        }
        
        var outputBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &outputBuffer)
        
        guard status == kCVReturnSuccess, let output = outputBuffer else {
            print("⚠️ Failed to create pixel buffer from pool: \(status)")
            return nil
        }
        
        // Create CIImage from the source pixel buffer
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        
        // Get output dimensions from the pooled buffer
        let outputWidth = CVPixelBufferGetWidth(output)
        let outputHeight = CVPixelBufferGetHeight(output)
        
        // Scale if needed to match output dimensions
        let scaleX = CGFloat(outputWidth) / ciImage.extent.width
        let scaleY = CGFloat(outputHeight) / ciImage.extent.height
        let scaledImage = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        
        // Render the CIImage into the pooled buffer
        ciContext.render(scaledImage, to: output)
        
        return output
    }
}
