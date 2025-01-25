import Foundation
import Vision
import AVFoundation
import CoreImage

/// Theory of Operation:
/// The SubtitleDetector processes videos to extract burned-in subtitles through the following steps:
///
/// 1. Frame Extraction:
///    - Samples video at 2 frames per second using AVFoundation
///    - Uses AVAssetImageGenerator for high-quality frame extraction
///    - Maintains precise timing information for each frame
///
/// 2. Text Detection:
///    - Uses Vision framework's VNRecognizeTextRequest for OCR
///    - Processes each frame to detect text regions
///    - Filters results by confidence score (threshold: 0.4)
///    - Captures text content, position, and timing
///
/// 3. Subtitle Merging:
///    - Groups similar subtitles that appear in consecutive frames
///    - Merges subtitles when:
///      * Text content matches (case-insensitive)
///      * Time gap is less than 0.5 seconds
///    - Uses highest confidence detection when merging
///    - Preserves original timing and positioning
///
/// 4. Progress Reporting:
///    - Reports progress through delegate pattern
///    - Provides completion callback with merged subtitles
///    - Reports errors if they occur during processing
///
/// The detector is designed to be memory-efficient (processing one frame at a time)
/// and accurate (using Vision's accurate recognition level with language correction).
/// It handles video orientation correctly and provides normalized coordinates for
/// subtitle positioning.

/// Protocol for reporting subtitle detection progress
public protocol SubtitleDetectionDelegate: AnyObject {
    func detectionDidProgress(_ progress: Float)
    func detectionDidComplete(subtitles: [SubtitleEntry])
    func detectionDidFail(with error: Error)
}

/// Handles detection of burned-in subtitles from video frames using Vision OCR
public class SubtitleDetector {
    
    // MARK: - Properties
    private let videoAsset: AVAsset
    private let imageGenerator: AVAssetImageGenerator
    private weak var delegate: SubtitleDetectionDelegate?
    
    /// Sampling rate in frames per second
    private let samplingRate: Float = 2.0 // Sample 2 frames per second
    
    /// Minimum confidence score for text detection
    private let minimumConfidence: Float = 0.4
    
    // Vision request for text detection
    private lazy var textRecognitionRequest: VNRecognizeTextRequest = {
        let request = VNRecognizeTextRequest { [weak self] request, error in
            if let error = error {
                print("Text recognition error: \(error)")
            }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        return request
    }()
    
    // MARK: - Initialization
    public init(videoAsset: AVAsset, delegate: SubtitleDetectionDelegate? = nil) {
        self.videoAsset = videoAsset
        self.delegate = delegate
        
        // Configure image generator
        self.imageGenerator = AVAssetImageGenerator(asset: videoAsset)
        self.imageGenerator.appliesPreferredTrackTransform = true
        self.imageGenerator.requestedTimeToleranceBefore = .zero
        self.imageGenerator.requestedTimeToleranceAfter = .zero
    }
    
    // MARK: - Public Methods
    public func detectSubtitles() async throws {
        do {
            // Get video duration
            let duration = try await videoAsset.load(.duration)
            let durationSeconds = CMTimeGetSeconds(duration)
            let frameCount = Int(durationSeconds * Float64(samplingRate))
            var subtitles: [SubtitleEntry] = []
            
            // Process frames
            for frameIndex in 0..<frameCount {
                let time = CMTime(seconds: Double(frameIndex) / Double(samplingRate), preferredTimescale: 600)
                
                let image = try imageGenerator.copyCGImage(at: time, actualTime: nil)
                let detectedTexts = try await detectText(in: image, at: time)
                subtitles.append(contentsOf: detectedTexts)
                
                // Report progress
                let progress = Float(frameIndex + 1) / Float(frameCount)
                delegate?.detectionDidProgress(progress)
            }
            
            // Merge similar subtitles that appear in consecutive frames
            let mergedSubtitles = mergeConsecutiveSubtitles(subtitles)
            delegate?.detectionDidComplete(subtitles: mergedSubtitles)
            
        } catch {
            delegate?.detectionDidFail(with: error)
            throw error
        }
    }
    
    /// Detects text in a single frame
    /// - Parameters:
    ///   - image: The frame to process
    ///   - time: The timestamp of the frame
    /// - Returns: Array of detected subtitles
    public func detectText(in image: CGImage, at time: CMTime) async throws -> [SubtitleEntry] {
        let requestHandler = VNImageRequestHandler(cgImage: image)
        try requestHandler.perform([textRecognitionRequest])
        
        guard let observations = textRecognitionRequest.results else { return [] }
        
        return observations
            .filter { $0.confidence >= minimumConfidence }
            .map { observation in
                SubtitleEntry(
                    text: observation.topCandidates(1)[0].string,
                    startTime: CMTimeGetSeconds(time),
                    endTime: CMTimeGetSeconds(time) + (1.0 / Double(samplingRate)),
                    position: observation.boundingBox,
                    confidence: observation.confidence
                )
            }
    }
    
    private func mergeConsecutiveSubtitles(_ subtitles: [SubtitleEntry]) -> [SubtitleEntry] {
        var mergedSubtitles: [SubtitleEntry] = []
        var currentGroup: [SubtitleEntry] = []
        
        func mergeSimilarSubtitles(_ group: [SubtitleEntry]) -> SubtitleEntry? {
            guard !group.isEmpty else { return nil }
            
            // Use the subtitle with highest confidence as the base
            let base = group.max(by: { $0.confidence < $1.confidence })!
            
            return SubtitleEntry(
                text: base.text,
                startTime: group.map(\.startTime).min()!,
                endTime: group.map(\.endTime).max()!,
                position: base.position,
                confidence: base.confidence
            )
        }
        
        for subtitle in subtitles.sorted(by: { $0.startTime < $1.startTime }) {
            if let last = currentGroup.last,
               subtitle.startTime - last.endTime < 0.5, // Gap threshold of 0.5 seconds
               subtitle.text.lowercased() == last.text.lowercased() {
                currentGroup.append(subtitle)
            } else {
                if let merged = mergeSimilarSubtitles(currentGroup) {
                    mergedSubtitles.append(merged)
                }
                currentGroup = [subtitle]
            }
        }
        
        if let merged = mergeSimilarSubtitles(currentGroup) {
            mergedSubtitles.append(merged)
        }
        
        return mergedSubtitles
    }
} 