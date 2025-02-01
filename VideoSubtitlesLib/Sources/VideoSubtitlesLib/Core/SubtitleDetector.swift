import AVFoundation
import CoreImage
import Foundation
import Vision

/// Theory of Operation:
/// The SubtitleDetector processes videos to extract text through the following steps:
///
/// 1. Frame Extraction:
///    - Samples video at a low rate using AVFoundation
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
    private var isCancelled = false
    private let translationService: TranslationService?

    /// Sampling rate in frames per second
    public let samplingRate: Float = 3 // Sample at video frame rate

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

    /// Creates a new subtitle detector for processing text from video frames
    /// - Parameters:
    ///   - videoAsset: The AVAsset to process for text detection
    ///   - delegate: Optional delegate to receive progress updates and results
    ///   - recognitionLanguages: Array of language codes for text recognition (e.g. ["en-US"])
    ///   - translationService: Optional translation service to translate detected text
    public init(
        videoAsset: AVAsset,
        delegate: TextDetectionDelegate? = nil,
        recognitionLanguages: [String] = ["en-US"],
        translationService: TranslationService? = nil
    ) {
        self.videoAsset = videoAsset
        self.delegate = delegate
        self.recognitionLanguages = recognitionLanguages
        self.translationService = translationService

        // Configure image generator
        imageGenerator = AVAssetImageGenerator(asset: videoAsset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceBefore = .zero
        imageGenerator.requestedTimeToleranceAfter = .zero
    }

    // MARK: - Public Methods

    /// Cancels any ongoing detection
    public func cancelDetection() {
        isCancelled = true
    }

    /// Processes the video asset to detect text in frames
    /// - Throws: Error if video processing fails or if cancelled
    /// - Returns: Void, but calls delegate methods with progress and results
    public func detectText() async throws {
        do {
            // Reset cancellation state
            isCancelled = false

            // Get video duration
            let duration = try await videoAsset.load(.duration)
            let durationSeconds = CMTimeGetSeconds(duration)
            let frameCount = Int(durationSeconds * Float64(samplingRate))
            var frames: [FrameSegments] = []

            // Process frames
            for frameIndex in 0 ..< frameCount {
                // Check for cancellation
                if isCancelled {
                    throw CancellationError()
                }

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

                // Check for cancellation again after image generation
                if isCancelled {
                    throw CancellationError()
                }

                let frameSegments = try await detectText(in: image, at: time)
                frames.append(frameSegments)

                // Report progress
                let progress = Float(frameIndex + 1) / Float(frameCount)
                delegate?.detectionDidProgress(progress)
            }

            // Final cancellation check before completing
            if isCancelled {
                throw CancellationError()
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

        // Capture translationService before task group to avoid data race
        let translationService = self.translationService

        let segments = try await withThrowingTaskGroup(of: TextSegment.self) { group in
            var segments: [TextSegment] = []

            for observation in observations where observation.confidence >= minimumConfidence {
                // Capture all necessary data from observation before the task
                let boundingBox = observation.boundingBox
                let text = observation.topCandidates(1)[0].string
                let confidence = observation.confidence

                group.addTask {
                    // Convert Vision coordinates (bottom-left origin) to normalized coordinates (top-left origin)
                    let normalizedBox = CGRect(
                        x: boundingBox.origin.x,
                        y: 1 - boundingBox.origin.y - boundingBox.height, // Flip Y coordinate
                        width: boundingBox.width,
                        height: boundingBox.height
                    )

                    var translatedText: String?

                    if let translationService {
                        translatedText = try await translationService.translateText(text)
                    }

                    return TextSegment(
                        text: text,
                        translatedText: translatedText,
                        position: normalizedBox,
                        confidence: confidence
                    )
                }
            }

            for try await segment in group {
                segments.append(segment)
            }

            return segments
        }

        return FrameSegments(
            timestamp: CMTimeGetSeconds(time),
            segments: segments
        )
    }
}
