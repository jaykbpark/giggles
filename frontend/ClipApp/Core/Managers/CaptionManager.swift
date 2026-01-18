import AVFoundation
import UIKit
import CoreMedia
import Combine
import SwiftUI

/// Manages caption generation, timing, and video burn-in
@MainActor
final class CaptionManager: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = CaptionManager()
    
    // MARK: - Published State
    
    @Published private(set) var isProcessing = false
    @Published private(set) var progress: Double = 0
    
    // MARK: - Configuration
    
    /// Default words per caption segment
    private let wordsPerSegment = 8
    
    /// Default duration per word (seconds)
    private let secondsPerWord: TimeInterval = 0.4
    
    /// Minimum segment duration
    private let minSegmentDuration: TimeInterval = 1.0
    
    /// Maximum segment duration
    private let maxSegmentDuration: TimeInterval = 4.0
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Caption Generation
    
    /// Generate caption segments from a transcript
    /// - Parameters:
    ///   - transcript: The full transcript text
    ///   - duration: Total video duration
    /// - Returns: Array of timed caption segments
    func generateSegments(from transcript: String, duration: TimeInterval) -> [CaptionSegment] {
        guard !transcript.isEmpty else { return [] }
        
        // Split transcript into words
        let words = transcript.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }
        
        var segments: [CaptionSegment] = []
        var currentIndex = 0
        var currentTime: TimeInterval = 0
        
        // Calculate time per word based on total duration
        let totalWords = words.count
        let timePerWord = duration / Double(totalWords)
        
        while currentIndex < words.count {
            // Take up to wordsPerSegment words
            let endIndex = min(currentIndex + wordsPerSegment, words.count)
            let segmentWords = words[currentIndex..<endIndex]
            let segmentText = segmentWords.joined(separator: " ")
            
            // Calculate segment duration
            let wordCount = segmentWords.count
            var segmentDuration = Double(wordCount) * timePerWord
            
            // Clamp duration
            segmentDuration = max(minSegmentDuration, min(maxSegmentDuration, segmentDuration))
            
            // Don't exceed total duration
            let endTime = min(currentTime + segmentDuration, duration)
            
            let segment = CaptionSegment(
                text: segmentText,
                startTime: currentTime,
                endTime: endTime
            )
            segments.append(segment)
            
            currentTime = endTime
            currentIndex = endIndex
            
            // Stop if we've reached the end
            if currentTime >= duration {
                break
            }
        }
        
        return segments
    }
    
    /// Generate caption segments with natural sentence breaks
    /// - Parameters:
    ///   - transcript: The full transcript text
    ///   - duration: Total video duration
    /// - Returns: Array of timed caption segments
    func generateNaturalSegments(from transcript: String, duration: TimeInterval) -> [CaptionSegment] {
        guard !transcript.isEmpty else { return [] }
        
        // Split by sentence-ending punctuation
        let pattern = "[.!?]+"
        let sentences = transcript.components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        guard !sentences.isEmpty else {
            return generateSegments(from: transcript, duration: duration)
        }
        
        // Calculate total character count for timing
        let totalChars = sentences.reduce(0) { $0 + $1.count }
        let timePerChar = duration / Double(max(totalChars, 1))
        
        var segments: [CaptionSegment] = []
        var currentTime: TimeInterval = 0
        
        for sentence in sentences {
            // Calculate duration based on character count
            var segmentDuration = Double(sentence.count) * timePerChar
            segmentDuration = max(minSegmentDuration, min(maxSegmentDuration, segmentDuration))
            
            let endTime = min(currentTime + segmentDuration, duration)
            
            // If sentence is too long, split it
            if sentence.count > 60 {
                let subSegments = splitLongSentence(sentence, startTime: currentTime, endTime: endTime)
                segments.append(contentsOf: subSegments)
            } else {
                let segment = CaptionSegment(
                    text: sentence,
                    startTime: currentTime,
                    endTime: endTime
                )
                segments.append(segment)
            }
            
            currentTime = endTime
            
            if currentTime >= duration {
                break
            }
        }
        
        return segments
    }
    
    private func splitLongSentence(_ sentence: String, startTime: TimeInterval, endTime: TimeInterval) -> [CaptionSegment] {
        let words = sentence.split(separator: " ").map(String.init)
        let midPoint = words.count / 2
        
        let firstHalf = words[0..<midPoint].joined(separator: " ")
        let secondHalf = words[midPoint...].joined(separator: " ")
        
        let midTime = (startTime + endTime) / 2
        
        return [
            CaptionSegment(text: firstHalf, startTime: startTime, endTime: midTime),
            CaptionSegment(text: secondHalf, startTime: midTime, endTime: endTime)
        ]
    }
    
    // MARK: - Video Burn-in
    
    /// Burn captions into a video file
    /// - Parameters:
    ///   - sourceURL: Source video URL
    ///   - segments: Caption segments to burn in
    ///   - style: Caption style configuration
    /// - Returns: URL of the video with burned-in captions
    func burnCaptionsIntoVideo(
        sourceURL: URL,
        segments: [CaptionSegment],
        style: CaptionStyle = CaptionStyle()
    ) async throws -> URL {
        isProcessing = true
        progress = 0
        
        defer {
            isProcessing = false
            progress = 0
        }
        
        let asset = AVAsset(url: sourceURL)
        let composition = AVMutableComposition()
        
        // Load tracks
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw CaptionError.noVideoTrack
        }
        
        let duration = try await asset.load(.duration)
        let videoSize = try await videoTrack.load(.naturalSize)
        let transform = try await videoTrack.load(.preferredTransform)
        
        // Determine actual video size after transform
        let isPortrait = transform.a == 0 && transform.d == 0
        let actualSize = isPortrait ? CGSize(width: videoSize.height, height: videoSize.width) : videoSize
        
        // Add video track to composition
        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw CaptionError.failedToCreateTrack
        }
        
        try compositionVideoTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: duration),
            of: videoTrack,
            at: .zero
        )
        compositionVideoTrack.preferredTransform = transform
        
        // Add audio track if present
        if let audioTrack = try await asset.loadTracks(withMediaType: .audio).first {
            if let compositionAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) {
                try compositionAudioTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: duration),
                    of: audioTrack,
                    at: .zero
                )
            }
        }
        
        // Create video composition for overlays
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = actualSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        
        // Create caption layer
        let captionLayer = createCaptionLayer(
            segments: segments,
            style: style,
            videoSize: actualSize,
            duration: duration.seconds
        )
        
        // Create parent layer
        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: actualSize)
        
        let videoLayer = CALayer()
        videoLayer.frame = CGRect(origin: .zero, size: actualSize)
        
        parentLayer.addSublayer(videoLayer)
        parentLayer.addSublayer(captionLayer)
        
        // Apply animation tool
        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )
        
        // Create instruction
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)
        layerInstruction.setTransform(transform, at: .zero)
        instruction.layerInstructions = [layerInstruction]
        
        videoComposition.instructions = [instruction]
        
        // Export
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("captioned_\(UUID().uuidString)")
            .appendingPathExtension("mp4")
        
        try? FileManager.default.removeItem(at: outputURL)
        
        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw CaptionError.failedToCreateExportSession
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.videoComposition = videoComposition
        exportSession.shouldOptimizeForNetworkUse = true
        
        // Monitor progress
        let progressTask = Task {
            while !Task.isCancelled && exportSession.status == .exporting {
                await MainActor.run {
                    self.progress = Double(exportSession.progress)
                }
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }
        }
        
        await exportSession.export()
        progressTask.cancel()
        
        switch exportSession.status {
        case .completed:
            print("📝 Burned captions into video: \(outputURL.lastPathComponent)")
            return outputURL
        case .failed:
            throw CaptionError.exportFailed(exportSession.error?.localizedDescription ?? "Unknown error")
        case .cancelled:
            throw CaptionError.cancelled
        default:
            throw CaptionError.exportFailed("Unexpected status: \(exportSession.status.rawValue)")
        }
    }
    
    // MARK: - Private Helpers
    
    private func createCaptionLayer(
        segments: [CaptionSegment],
        style: CaptionStyle,
        videoSize: CGSize,
        duration: TimeInterval
    ) -> CALayer {
        let containerLayer = CALayer()
        containerLayer.frame = CGRect(origin: .zero, size: videoSize)
        containerLayer.masksToBounds = true
        
        for segment in segments {
            let textLayer = createTextLayer(
                text: segment.text,
                style: style,
                videoSize: videoSize
            )
            
            // Position based on style
            let yPosition: CGFloat
            switch style.position {
            case .top:
                yPosition = videoSize.height - textLayer.frame.height - 60
            case .center:
                yPosition = (videoSize.height - textLayer.frame.height) / 2
            case .bottom:
                yPosition = 60
            }
            
            textLayer.frame.origin.y = yPosition
            textLayer.frame.origin.x = (videoSize.width - textLayer.frame.width) / 2
            
            // Add fade in/out animation
            let fadeAnimation = CAKeyframeAnimation(keyPath: "opacity")
            fadeAnimation.values = [0, 1, 1, 0]
            fadeAnimation.keyTimes = [0, 0.05, 0.95, 1]
            fadeAnimation.duration = segment.duration
            fadeAnimation.beginTime = AVCoreAnimationBeginTimeAtZero + segment.startTime
            fadeAnimation.fillMode = .forwards
            fadeAnimation.isRemovedOnCompletion = false
            
            // Initially hidden
            textLayer.opacity = 0
            textLayer.add(fadeAnimation, forKey: "fadeAnimation")
            
            containerLayer.addSublayer(textLayer)
        }
        
        return containerLayer
    }
    
    private func createTextLayer(
        text: String,
        style: CaptionStyle,
        videoSize: CGSize
    ) -> CALayer {
        // Background layer
        let backgroundLayer = CALayer()
        
        // Text layer
        let textLayer = CATextLayer()
        textLayer.string = text
        textLayer.font = UIFont.systemFont(
            ofSize: style.fontSize * 2, // Scale for video resolution
            weight: uiFontWeight(from: style.fontWeight)
        )
        textLayer.fontSize = style.fontSize * 2
        textLayer.foregroundColor = UIColor(Color(hex: style.textColor) ?? .white).cgColor
        textLayer.alignmentMode = .center
        textLayer.contentsScale = UIScreen.main.scale
        textLayer.isWrapped = true
        
        // Calculate text size
        let maxWidth = videoSize.width * 0.85
        let textSize = (text as NSString).boundingRect(
            with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: UIFont.systemFont(ofSize: style.fontSize * 2, weight: uiFontWeight(from: style.fontWeight))],
            context: nil
        ).size
        
        let padding: CGFloat = 24
        textLayer.frame = CGRect(
            x: padding,
            y: padding / 2,
            width: textSize.width + padding,
            height: textSize.height + padding
        )
        
        // Background
        backgroundLayer.frame = CGRect(
            x: 0,
            y: 0,
            width: textSize.width + padding * 2,
            height: textSize.height + padding
        )
        backgroundLayer.backgroundColor = UIColor(Color(hex: style.backgroundColor) ?? .black)
            .withAlphaComponent(style.backgroundOpacity).cgColor
        backgroundLayer.cornerRadius = 12
        
        backgroundLayer.addSublayer(textLayer)
        
        return backgroundLayer
    }
    
    private func uiFontWeight(from string: String) -> UIFont.Weight {
        switch string {
        case "regular": return .regular
        case "medium": return .medium
        case "semibold": return .semibold
        case "bold": return .bold
        default: return .semibold
        }
    }
}

// MARK: - Errors

enum CaptionError: Error, LocalizedError {
    case noVideoTrack
    case failedToCreateTrack
    case failedToCreateExportSession
    case exportFailed(String)
    case cancelled
    
    var errorDescription: String? {
        switch self {
        case .noVideoTrack:
            return "No video track found"
        case .failedToCreateTrack:
            return "Failed to create composition track"
        case .failedToCreateExportSession:
            return "Failed to create export session"
        case .exportFailed(let reason):
            return "Export failed: \(reason)"
        case .cancelled:
            return "Caption burn-in was cancelled"
        }
    }
}
