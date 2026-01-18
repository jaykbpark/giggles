import Foundation
import CoreVideo
import AVFoundation
import UIKit

/// FFmpeg-based video exporter that writes raw frames to disk
/// then uses FFmpeg CLI to encode. This avoids AVAssetWriter's picky hardware encoder.
///
/// Flow:
/// 1. Write each frame as raw BGRA data to a temp file
/// 2. Run FFmpeg to encode raw video → H.264 MP4
/// 3. Return the MP4 URL
final class FFmpegExporter {
    
    enum ExportError: Error, LocalizedError {
        case noFrames
        case writeFailed(String)
        case encodeFailed(String)
        case conversionFailed
        
        var errorDescription: String? {
            switch self {
            case .noFrames: return "No frames to export"
            case .writeFailed(let msg): return "Write failed: \(msg)"
            case .encodeFailed(let msg): return "Encode failed: \(msg)"
            case .conversionFailed: return "Pixel buffer conversion failed"
            }
        }
    }
    
    private let tempDir: URL
    
    init() {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ffmpeg_export_\(UUID().uuidString)")
    }
    
    /// Export frames to MP4 using image sequence approach
    /// This is the most reliable method - writes JPEGs then combines with FFmpeg
    func exportAsImageSequence(
        frames: [(pixelBuffer: CVPixelBuffer, hostTime: UInt64)],
        audioBuffers: [TimestampedAudioBuffer] = [],
        frameRate: Int = 30
    ) async throws -> URL {
        guard !frames.isEmpty else {
            throw ExportError.noFrames
        }
        
        // Create temp directory
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        print("🎬 [FFmpeg] Writing \(frames.count) frames as JPEGs...")
        
        let width = CVPixelBufferGetWidth(frames[0].pixelBuffer)
        let height = CVPixelBufferGetHeight(frames[0].pixelBuffer)
        
        // Write each frame as JPEG
        for (index, frame) in frames.enumerated() {
            let jpegURL = tempDir.appendingPathComponent(String(format: "frame_%05d.jpg", index))
            
            if let jpegData = pixelBufferToJPEG(frame.pixelBuffer) {
                try jpegData.write(to: jpegURL)
            } else {
                print("⚠️ Failed to convert frame \(index) to JPEG")
            }
            
            if index % 100 == 0 {
                print("🎬 [FFmpeg] Wrote \(index)/\(frames.count) JPEGs")
            }
        }
        
        print("✅ [FFmpeg] All JPEGs written")
        
        let baseHostTime = min(
            frames.first?.hostTime ?? 0,
            audioBuffers.first?.hostTime ?? UInt64.max
        )
        
        // Since FFmpeg isn't available on device, combine JPEGs using AVAssetWriter
        print("🎬 [JPEG] Combining JPEGs with AVAssetWriter...")
        
        let videoURL = try await combineJPEGsToVideo(
            jpegDirectory: tempDir,
            frameCount: frames.count,
            width: width,
            height: height,
            frameRate: frameRate,
            framesHostTimes: frames.map { $0.hostTime },
            baseHostTime: baseHostTime
        )
        
        // If we have audio, write an audio track and mux with video
        if !audioBuffers.isEmpty {
            print("🎬 [Audio] Writing audio track...")
            let audioURL = try await writeAudioTrack(
                audioBuffers: audioBuffers,
                baseHostTime: baseHostTime
            )
            
            print("🎬 [Mux] Combining audio + video...")
            let muxedURL = try await muxVideo(videoURL: videoURL, audioURL: audioURL, outputFileType: .mp4, preset: AVAssetExportPresetHighestQuality)
            
            // Cleanup temp files
            try? FileManager.default.removeItem(at: audioURL)
            try? FileManager.default.removeItem(at: tempDir)
            
            print("✅ [Mux] Export complete: \(muxedURL.lastPathComponent)")
            return muxedURL
        }
        
        // Cleanup temp files
        try? FileManager.default.removeItem(at: tempDir)
        
        print("✅ [JPEG] Export complete: \(videoURL.lastPathComponent)")
        return videoURL
    }

    /// Mux an existing video with audio buffers (used after ProRes export)
    func muxVideoWithAudio(
        videoURL: URL,
        audioBuffers: [TimestampedAudioBuffer],
        baseHostTime: UInt64,
        outputFileType: AVFileType = .mp4,
        preset: String = AVAssetExportPresetHighestQuality
    ) async throws -> URL {
        guard !audioBuffers.isEmpty else { return videoURL }

        let audioURL = try await writeAudioTrack(
            audioBuffers: audioBuffers,
            baseHostTime: baseHostTime
        )

        let muxedURL = try await muxVideo(
            videoURL: videoURL,
            audioURL: audioURL,
            outputFileType: outputFileType,
            preset: preset
        )
        try? FileManager.default.removeItem(at: audioURL)
        return muxedURL
    }
    
    /// Combine JPEG files into H.264 video using AVAssetWriter
    /// This works because JPEGs → UIImage → BGRA pixel buffer is a standard path
    private func combineJPEGsToVideo(
        jpegDirectory: URL,
        frameCount: Int,
        width: Int,
        height: Int,
        frameRate: Int,
        framesHostTimes: [UInt64],
        baseHostTime: UInt64
    ) async throws -> URL {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("clip_\(UUID().uuidString).mp4")
        
        try? FileManager.default.removeItem(at: outputURL)
        
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 15_000_000, // 15 Mbps for 1080p quality
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoMaxKeyFrameIntervalKey: 30 // Keyframe every second at 30fps
            ]
        ]
        
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = false
        
        // Use BGRA for adaptor - this is what UIImage gives us
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ]
        )
        
        writer.add(input)
        
        guard writer.startWriting() else {
            throw ExportError.writeFailed(writer.error?.localizedDescription ?? "Unknown")
        }
        
        writer.startSession(atSourceTime: .zero)
        
        var writtenCount = 0
        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate))
        var lastPresentationTime = CMTime(value: -1, timescale: 600)
        
        for index in 0..<frameCount {
            let jpegURL = jpegDirectory.appendingPathComponent(String(format: "frame_%05d.jpg", index))
            
            guard let jpegData = try? Data(contentsOf: jpegURL),
                  let uiImage = UIImage(data: jpegData),
                  let pixelBuffer = pixelBufferFromUIImage(uiImage) else {
                print("⚠️ [JPEG] Failed to read frame \(index)")
                continue
            }
            
            // Wait for input to be ready
            while !input.isReadyForMoreMediaData {
                if writer.status == .failed {
                    throw ExportError.writeFailed(writer.error?.localizedDescription ?? "Unknown")
                }
                try await Task.sleep(nanoseconds: 1_000_000)
            }
            
            let rawTime = hostTimeToCMTime(framesHostTimes[index], relativeTo: baseHostTime)
            let presentationTime: CMTime
            if lastPresentationTime.isValid && rawTime <= lastPresentationTime {
                presentationTime = CMTimeAdd(lastPresentationTime, frameDuration)
            } else {
                presentationTime = rawTime
            }
            lastPresentationTime = presentationTime
            
            if adaptor.append(pixelBuffer, withPresentationTime: presentationTime) {
                writtenCount += 1
            } else {
                print("⚠️ [JPEG] Frame \(index) append failed")
                if writer.status == .failed {
                    throw ExportError.writeFailed(writer.error?.localizedDescription ?? "Unknown")
                }
            }
            
            if writtenCount % 100 == 0 && writtenCount > 0 {
                print("🎬 [JPEG] Encoded: \(writtenCount)/\(frameCount)")
            }
        }
        
        input.markAsFinished()
        await writer.finishWriting()
        
        if writer.status == .completed {
            print("✅ [JPEG] Video created: \(writtenCount) frames")
            return outputURL
        } else {
            throw ExportError.writeFailed(writer.error?.localizedDescription ?? "Finish failed")
        }
    }

    // MARK: - Audio Track

    private func writeAudioTrack(
        audioBuffers: [TimestampedAudioBuffer],
        baseHostTime: UInt64
    ) async throws -> URL {
        guard let firstBuffer = audioBuffers.first else {
            throw ExportError.writeFailed("No audio buffers")
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("audio_\(UUID().uuidString).caf")

        try? FileManager.default.removeItem(at: outputURL)

        // Use LinearPCM to avoid AAC encoder failures at 16kHz
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .caf)

        let format = firstBuffer.buffer.format
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        input.expectsMediaDataInRealTime = false

        writer.add(input)

        guard writer.startWriting() else {
            throw ExportError.writeFailed(writer.error?.localizedDescription ?? "Unknown")
        }

        writer.startSession(atSourceTime: .zero)

        var writtenCount = 0
        for (index, audioBuffer) in audioBuffers.enumerated() {
            while !input.isReadyForMoreMediaData {
                if writer.status == .failed {
                    throw ExportError.writeFailed(writer.error?.localizedDescription ?? "Unknown")
                }
                try await Task.sleep(nanoseconds: 1_000_000)
            }

            if let sampleBuffer = createAudioSampleBuffer(from: audioBuffer, baseHostTime: baseHostTime) {
                if input.append(sampleBuffer) {
                    writtenCount += 1
                } else if writer.status == .failed {
                    throw ExportError.writeFailed(writer.error?.localizedDescription ?? "Unknown")
                }
            } else {
                print("⚠️ [Audio] Failed to create sample buffer at index \(index)")
            }
        }

        input.markAsFinished()
        await writer.finishWriting()

        if writer.status == .completed {
            print("✅ [Audio] Wrote \(writtenCount)/\(audioBuffers.count) buffers")
            return outputURL
        }

        throw ExportError.writeFailed(writer.error?.localizedDescription ?? "Audio finish failed")
    }

    private func muxVideo(
        videoURL: URL,
        audioURL: URL,
        outputFileType: AVFileType,
        preset: String
    ) async throws -> URL {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("clip_muxed_\(UUID().uuidString).\(outputFileType == .mov ? "mov" : "mp4")")

        try? FileManager.default.removeItem(at: outputURL)

        let videoAsset = AVAsset(url: videoURL)
        let audioAsset = AVAsset(url: audioURL)

        let composition = AVMutableComposition()
        let videoDuration = try await videoAsset.load(.duration)

        if let videoTrack = try await videoAsset.loadTracks(withMediaType: .video).first,
           let compVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try compVideoTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: videoDuration),
                of: videoTrack,
                at: .zero
            )
        }

        if let audioTrack = try await audioAsset.loadTracks(withMediaType: .audio).first,
           let compAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            let audioDuration = try await audioAsset.load(.duration)
            let duration = CMTimeMinimum(videoDuration, audioDuration)
            try compAudioTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: duration),
                of: audioTrack,
                at: .zero
            )
        }

        // Use passthrough for master .mov, otherwise re-encode for mp4
        guard let exporter = AVAssetExportSession(asset: composition, presetName: preset) else {
            throw ExportError.writeFailed("Failed to create export session")
        }

        exporter.outputURL = outputURL
        exporter.outputFileType = outputFileType
        if outputFileType == .mp4 {
            exporter.shouldOptimizeForNetworkUse = true
        }

        await exporter.export()

        switch exporter.status {
        case .completed:
            return outputURL
        case .failed:
            throw ExportError.writeFailed(exporter.error?.localizedDescription ?? "Mux failed")
        case .cancelled:
            throw ExportError.writeFailed("Mux cancelled")
        default:
            throw ExportError.writeFailed("Mux unexpected status: \(exporter.status.rawValue)")
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

    private func createAudioSampleBuffer(
        from timestampedBuffer: TimestampedAudioBuffer,
        baseHostTime: UInt64
    ) -> CMSampleBuffer? {
        let buffer = timestampedBuffer.buffer
        let formatPtr = buffer.format.streamDescription

        let presentationTime = hostTimeToCMTime(timestampedBuffer.hostTime, relativeTo: baseHostTime)

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

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: CMTimeValue(buffer.frameLength), timescale: CMTimeScale(buffer.format.sampleRate)),
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: .invalid
        )

        var sampleBuffer: CMSampleBuffer?
        guard let channelData = buffer.floatChannelData else { return nil }

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

        CMBlockBufferReplaceDataBytes(
            with: channelData[0],
            blockBuffer: block,
            offsetIntoDestination: 0,
            dataLength: dataSize
        )

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
    
    /// Convert UIImage to CVPixelBuffer (BGRA format)
    private func pixelBufferFromUIImage(_ image: UIImage) -> CVPixelBuffer? {
        guard let cgImage = image.cgImage else { return nil }
        
        let width = cgImage.width
        let height = cgImage.height
        
        var pixelBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any]
        ]
        
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pixelBuffer
        )
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            return nil
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        return buffer
    }
    
    /// Convert CVPixelBuffer to JPEG data
    private func pixelBufferToJPEG(_ pixelBuffer: CVPixelBuffer, quality: CGFloat = 0.95) -> Data? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        if width <= 0 || height <= 0 {
            print("⚠️ [JPEG] Invalid pixel buffer size: \(width)x\(height)")
            return nil
        }
        if CVPixelBufferIsPlanar(pixelBuffer) {
            let planeCount = CVPixelBufferGetPlaneCount(pixelBuffer)
            for plane in 0..<planeCount {
                let planeHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, plane)
                let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, plane)
                if planeHeight <= 0 || bytesPerRow <= 0 {
                    print("⚠️ [JPEG] Invalid plane \(plane): height=\(planeHeight), bytesPerRow=\(bytesPerRow)")
                    return nil
                }
            }
        } else if CVPixelBufferGetBytesPerRow(pixelBuffer) <= 0 {
            print("⚠️ [JPEG] Invalid bytesPerRow")
            return nil
        }
        
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        
        let uiImage = UIImage(cgImage: cgImage)
        return uiImage.jpegData(compressionQuality: quality)
    }
    
    /// Since FFmpegKit isn't integrated yet, we'll use AVAssetWriter with ProRes/uncompressed
    /// which is much more lenient about input formats
    private func runFFmpeg(command: String) async -> Bool {
        // FFmpegKit not integrated - use fallback
        return false
    }
}

// MARK: - ProRes Fallback (more lenient than H.264)

extension FFmpegExporter {
    
    /// Export using ProRes codec which is much more forgiving about input formats
    /// Then we can transcode to H.264 later if needed
    func exportWithProRes(
        frames: [(pixelBuffer: CVPixelBuffer, hostTime: UInt64)],
        frameRate: Int = 30
    ) async throws -> URL {
        guard !frames.isEmpty else {
            throw ExportError.noFrames
        }
        
        let width = CVPixelBufferGetWidth(frames[0].pixelBuffer)
        let height = CVPixelBufferGetHeight(frames[0].pixelBuffer)
        
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("clip_\(UUID().uuidString).mov")
        
        // Remove existing
        try? FileManager.default.removeItem(at: outputURL)
        
        // Create writer with Apple ProRes (much more lenient)
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        
        // Use ProRes 422 - very forgiving about input formats
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.proRes422,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]
        
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = false
        
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: nil
        )
        
        writer.add(input)
        
        guard writer.startWriting() else {
            throw ExportError.writeFailed(writer.error?.localizedDescription ?? "Unknown")
        }
        
        writer.startSession(atSourceTime: .zero)
        
        print("🎬 [ProRes] Writing \(frames.count) frames...")
        
        var writtenCount = 0
        let baseTime = frames[0].hostTime
        
        for (index, frame) in frames.enumerated() {
            while !input.isReadyForMoreMediaData {
                if writer.status == .failed {
                    throw ExportError.writeFailed(writer.error?.localizedDescription ?? "Unknown")
                }
                try await Task.sleep(nanoseconds: 1_000_000)
            }
            
            // Calculate presentation time
            let relativeNanos = frame.hostTime - baseTime
            var timebaseInfo = mach_timebase_info_data_t()
            mach_timebase_info(&timebaseInfo)
            let nanos = relativeNanos * UInt64(timebaseInfo.numer) / UInt64(timebaseInfo.denom)
            let seconds = Double(nanos) / 1_000_000_000.0
            let time = CMTime(seconds: seconds, preferredTimescale: 600)
            
            if adaptor.append(frame.pixelBuffer, withPresentationTime: time) {
                writtenCount += 1
            } else {
                print("⚠️ [ProRes] Frame \(index) failed: \(writer.error?.localizedDescription ?? "unknown")")
                if writer.status == .failed {
                    throw ExportError.writeFailed(writer.error?.localizedDescription ?? "Unknown")
                }
            }
            
            if writtenCount % 100 == 0 && writtenCount > 0 {
                print("🎬 [ProRes] Progress: \(writtenCount)/\(frames.count)")
            }
        }
        
        input.markAsFinished()
        await writer.finishWriting()
        
        if writer.status == .completed {
            print("✅ [ProRes] Export complete: \(outputURL.lastPathComponent) (\(writtenCount) frames)")
            return outputURL
        } else {
            throw ExportError.writeFailed(writer.error?.localizedDescription ?? "Unknown")
        }
    }
}

// MARK: - Alternative: Raw Video Export (for when FFmpegKit is added)

extension FFmpegExporter {
    
    /// Export as raw video file (faster than JPEG, but requires FFmpegKit on device)
    func exportAsRawVideo(
        frames: [(pixelBuffer: CVPixelBuffer, hostTime: UInt64)],
        frameRate: Int = 30
    ) async throws -> URL {
        guard !frames.isEmpty else {
            throw ExportError.noFrames
        }
        
        let width = CVPixelBufferGetWidth(frames[0].pixelBuffer)
        let height = CVPixelBufferGetHeight(frames[0].pixelBuffer)
        
        // Create raw video file
        let rawURL = tempDir.appendingPathComponent("raw_video.yuv")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        FileManager.default.createFile(atPath: rawURL.path, contents: nil)
        guard let fileHandle = try? FileHandle(forWritingTo: rawURL) else {
            throw ExportError.writeFailed("Cannot create raw file")
        }
        
        print("🎬 [FFmpeg] Writing \(frames.count) raw YUV frames...")
        
        for (index, frame) in frames.enumerated() {
            if let data = extractYUVData(from: frame.pixelBuffer) {
                fileHandle.write(data)
            }
            
            if index % 100 == 0 {
                print("🎬 [FFmpeg] Wrote \(index)/\(frames.count) raw frames")
            }
        }
        
        try fileHandle.close()
        print("✅ [FFmpeg] Raw video written")
        
        // Output path
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("clip_\(UUID().uuidString).mp4")
        
        // FFmpeg command for raw YUV → H.264
        let command = """
        -y \
        -f rawvideo \
        -pix_fmt nv12 \
        -s \(width)x\(height) \
        -r \(frameRate) \
        -i "\(rawURL.path)" \
        -c:v libx264 \
        -preset ultrafast \
        -pix_fmt yuv420p \
        "\(outputURL.path)"
        """
        
        let success = await runFFmpeg(command: command)
        
        // Cleanup
        try? FileManager.default.removeItem(at: tempDir)
        
        if success {
            return outputURL
        } else {
            throw ExportError.encodeFailed("FFmpeg raw encode failed")
        }
    }
    
    /// Extract raw YUV data from pixel buffer
    private func extractYUVData(from pixelBuffer: CVPixelBuffer) -> Data? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        
        let planeCount = CVPixelBufferGetPlaneCount(pixelBuffer)
        var data = Data()
        
        if planeCount > 0 {
            // Planar format (YUV)
            for plane in 0..<planeCount {
                guard let baseAddr = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, plane) else {
                    continue
                }
                let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, plane)
                let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, plane)
                let planeData = Data(bytes: baseAddr, count: bytesPerRow * height)
                data.append(planeData)
            }
        } else {
            // Non-planar format
            guard let baseAddr = CVPixelBufferGetBaseAddress(pixelBuffer) else {
                return nil
            }
            let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            data = Data(bytes: baseAddr, count: bytesPerRow * height)
        }
        
        return data
    }
}
