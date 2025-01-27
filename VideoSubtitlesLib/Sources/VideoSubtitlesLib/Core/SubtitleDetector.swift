import AVFoundation
import CoreImage
import Foundation
import Vision

/// Theory of Operation:
/// The SubtitleDetector processes videos to extract text through the following steps:
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
///    - Captures text content and position
///
/// 3. Frame Processing:
///    - Groups all text segments found in each frame
///    - Maintains original positioning and confidence scores
///    - Tracks timing information per frame
///
/// 4. Progress Reporting:
///    - Reports progress through delegate pattern
///    - Provides completion callback with frame segments
///    - Reports errors if they occur during processing
///
/// The detector is designed to be memory-efficient (processing one frame at a time)
/// and accurate (using Vision's accurate recognition level with language correction).
/// It handles video orientation correctly and provides normalized coordinates for
/// text positioning.

/// Protocol for reporting text detection progress
public protocol TextDetectionDelegate: AnyObject {
    func detectionDidProgress(_ progress: Float)
    func detectionDidComplete(frames: [FrameSegments])
    func detectionDidFail(with error: Error)
}

/// Handles detection of text from video frames using Vision OCR
public class SubtitleDetector {
    // MARK: - Properties

    private let videoAsset: AVAsset
    private let imageGenerator: AVAssetImageGenerator
    private weak var delegate: TextDetectionDelegate?
    private let recognitionLanguages: [String]

    /// Sampling rate in frames per second
    public let samplingRate: Float = 7.5 // Sample at video frame rate

    /// Minimum confidence score for text detection
    private let minimumConfidence: Float = 0.4

    // Vision request for text detection
    private lazy var textRecognitionRequest: VNRecognizeTextRequest = {
        let request = VNRecognizeTextRequest { [weak self] _, error in
            if let error {
                print("Text recognition error: \(error)")
            }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = recognitionLanguages
        return request
    }()

    // MARK: - Initialization

    public init(
        videoAsset: AVAsset,
        delegate: TextDetectionDelegate? = nil,
        recognitionLanguages: [String] = ["en-US"]
    ) {
        self.videoAsset = videoAsset
        self.delegate = delegate
        self.recognitionLanguages = recognitionLanguages

        // Configure image generator
        imageGenerator = AVAssetImageGenerator(asset: videoAsset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceBefore = .zero
        imageGenerator.requestedTimeToleranceAfter = .zero
    }

    // MARK: - Public Methods

    public func detectText() async throws {
        do {
            // Get video duration
            let duration = try await videoAsset.load(.duration)
            let durationSeconds = CMTimeGetSeconds(duration)
            let frameCount = Int(durationSeconds * Float64(samplingRate))
            var frames: [FrameSegments] = []

            // Process frames
            for frameIndex in 0 ..< frameCount {
                let time = CMTime(seconds: Double(frameIndex) / Double(samplingRate), preferredTimescale: 600)

                let image = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<
                    CGImage,
                    Error
                >) in
                    imageGenerator.generateCGImageAsynchronously(for: time) { cgImage, _, error in
                        if let error {
                            continuation.resume(throwing: error)
                        } else if let cgImage {
                            continuation.resume(returning: cgImage)
                        } else {
                            continuation.resume(throwing: NSError(
                                domain: "SubtitleDetector",
                                code: -1,
                                userInfo: [NSLocalizedDescriptionKey: "Failed to generate image"]
                            ))
                        }
                    }
                }
                let frameSegments = try await detectText(in: image, at: time)
                frames.append(frameSegments)

                // Report progress
                let progress = Float(frameIndex + 1) / Float(frameCount)
                delegate?.detectionDidProgress(progress)
            }

            delegate?.detectionDidComplete(frames: frames)

        } catch {
            delegate?.detectionDidFail(with: error)
            throw error
        }
    }

    /// Detects text in a single frame
    /// - Parameters:
    ///   - image: The frame to process
    ///   - time: The timestamp of the frame
    /// - Returns: FrameSegments containing all detected text
    public func detectText(in image: CGImage, at time: CMTime) async throws -> FrameSegments {
        let requestHandler = VNImageRequestHandler(cgImage: image)
        try requestHandler.perform([textRecognitionRequest])

        guard let observations = textRecognitionRequest.results else {
            return FrameSegments(timestamp: CMTimeGetSeconds(time), segments: [])
        }

        let segments = observations
            .filter { $0.confidence >= minimumConfidence }
            .map { observation in
                // Convert Vision coordinates (bottom-left origin) to normalized coordinates (top-left origin)
                let visionBox = observation.boundingBox
                let normalizedBox = CGRect(
                    x: visionBox.origin.x,
                    y: 1 - visionBox.origin.y - visionBox.height, // Flip Y coordinate
                    width: visionBox.width,
                    height: visionBox.height
                )

                return TextSegment(
                    text: observation.topCandidates(1)[0].string,
                    position: normalizedBox,
                    confidence: observation.confidence
                )
            }

        return FrameSegments(
            timestamp: CMTimeGetSeconds(time),
            segments: segments
        )
    }
}
