import AVFoundation
import CoreMedia
import CoreVideo
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
    
    // MARK: - Properties
    
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    
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
        guard !videoFrames.isEmpty else {
            throw ExportError.noVideoFrames
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
        } catch {
            throw ExportError.failedToCreateWriter(error.localizedDescription)
        }
        
        self.assetWriter = writer
        
        // Setup video input
        setupVideoInput(writer: writer, config: config)
        
        // Setup audio input if we have audio
        if !audioBuffers.isEmpty {
            setupAudioInput(writer: writer, config: config)
        }
        
        // Start writing
        guard writer.startWriting() else {
            throw ExportError.failedToStartWriting
        }
        
        // Find the earliest timestamp to use as our base time
        let baseTime = videoFrames.first?.presentationTime ?? .zero
        writer.startSession(atSourceTime: baseTime)
        
        // Write video frames
        try await writeVideoFrames(videoFrames, baseTime: baseTime)
        
        // Write audio buffers
        if !audioBuffers.isEmpty {
            try await writeAudioBuffers(audioBuffers, baseTime: baseTime)
        }
        
        // Finish writing
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        
        await writer.finishWriting()
        
        if let error = writer.error {
            throw ExportError.failedToFinishWriting(error.localizedDescription)
        }
        
        print("📼 Exported clip to: \(outputURL.lastPathComponent)")
        
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
        guard !videoFrames.isEmpty else {
            throw ExportError.noVideoFrames
        }
        
        // Convert host times to CMTime
        // Find the earliest host time as our reference point
        let videoStartTime = videoFrames.first?.hostTime ?? 0
        let audioStartTime = audioBuffers.first?.hostTime ?? UInt64.max
        let baseHostTime = min(videoStartTime, audioStartTime)
        
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
        
        // Create pixel buffer adaptor for efficient writing
        let sourcePixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: config.videoSize.width,
            kCVPixelBufferHeightKey as String: config.videoSize.height
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
        guard let input = videoInput, let adaptor = pixelBufferAdaptor else { return }
        
        for frame in frames {
            // Wait for input to be ready
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 10_000_000) // 10ms
            }
            
            // Calculate presentation time relative to base
            let presentationTime = CMTimeSubtract(frame.presentationTime, baseTime)
            let adjustedTime = CMTimeMaximum(presentationTime, .zero)
            
            // Append pixel buffer
            if !adaptor.append(frame.pixelBuffer, withPresentationTime: adjustedTime) {
                print("⚠️ Failed to append video frame at \(adjustedTime.seconds)s")
            }
        }
    }
    
    private func writeAudioBuffers(_ buffers: [TimestampedAudioSample], baseTime: CMTime) async throws {
        guard let input = audioInput else { return }
        
        for buffer in buffers {
            // Wait for input to be ready
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 10_000_000) // 10ms
            }
            
            // Append sample buffer
            if !input.append(buffer.sampleBuffer) {
                print("⚠️ Failed to append audio buffer")
            }
        }
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
}
