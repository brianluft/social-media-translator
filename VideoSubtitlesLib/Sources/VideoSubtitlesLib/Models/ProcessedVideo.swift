import Foundation
import os

private let logger = Logger(subsystem: "VideoSubtitlesLib", category: "ProcessedVideo")

/// Represents a video that has been processed for subtitle translation
public struct ProcessedVideo {
    /// The URL of the video file
    public let url: URL

    /// All frame segments with their timestamps, sorted by timestamp
    public let frameSegments: [FrameSegments]

    /// Dictionary mapping original text to translated text
    public let translations: [String: String]

    /// Target language of the translations
    public let targetLanguage: String

    public init(
        url: URL,
        frameSegments: [FrameSegments],
        translations: [String: String],
        targetLanguage: String
    ) {
        self.url = url
        // Sort frame segments by timestamp for binary search
        self.frameSegments = frameSegments.sorted(by: { $0.timestamp < $1.timestamp })
        self.translations = translations
        self.targetLanguage = targetLanguage

        logger.debug("Initialized with \(translations.count) translations in \(targetLanguage)")
        for (original, translated) in translations {
            logger.debug("  '\(original)' -> '\(translated)'")
        }
    }

    /// Returns the text segments that should be visible at the given timestamp, with translations if available
    /// - Parameter time: The timestamp in seconds from the start of the video
    /// - Returns: Array of text segments with translations
    public func segments(at time: TimeInterval) -> [(segment: TextSegment, translation: String?)] {
        // Binary search for the closest frame
        let frame = binarySearchClosestFrame(at: time)
        guard let frame else {
            logger.debug("No frame found at time \(time, format: .fixed(precision: 3))")
            return []
        }

        logger
            .debug(
                "Found frame at \(frame.timestamp, format: .fixed(precision: 3)) for time \(time, format: .fixed(precision: 3))"
            )
        logger.debug("Frame contains \(frame.segments.count) segments:")

        let segmentsWithTranslations = frame.segments.map { segment -> (segment: TextSegment, translation: String?) in
            let translation = translations[segment.text]
            logger.debug("  '\(segment.text)' -> \(translation ?? "nil")")
            return (segment: segment, translation: translation)
        }

        return segmentsWithTranslations
    }

    /// Binary search to find the frame segments closest to the given timestamp
    private func binarySearchClosestFrame(at time: TimeInterval) -> FrameSegments? {
        guard !frameSegments.isEmpty else { return nil }

        logger
            .debug(
                "Binary searching for frame at time \(time, format: .fixed(precision: 3)) among \(frameSegments.count) frames"
            )
        logger
            .debug(
                "Frame range: \(frameSegments[0].timestamp, format: .fixed(precision: 3)) to \(frameSegments[frameSegments.count - 1].timestamp, format: .fixed(precision: 3))"
            )

        var left = 0
        var right = frameSegments.count - 1

        while left < right {
            let mid = (left + right) / 2
            let midTime = frameSegments[mid].timestamp

            logger.debug("  Comparing with frame at \(midTime, format: .fixed(precision: 3)) (index \(mid))")

            if abs(midTime - time) < 0.001 { // Found exact match within tolerance
                logger.debug("  Found exact match at index \(mid)")
                return frameSegments[mid]
            }

            if midTime < time {
                logger
                    .debug(
                        "  Moving right: \(midTime, format: .fixed(precision: 3)) < \(time, format: .fixed(precision: 3))"
                    )
                left = mid + 1
            } else {
                logger
                    .debug(
                        "  Moving left: \(midTime, format: .fixed(precision: 3)) >= \(time, format: .fixed(precision: 3))"
                    )
                right = mid
            }
        }

        // Handle edge cases and return closest frame
        if left == 0 {
            logger.debug("  At start of range, returning first frame")
            return frameSegments[0]
        }
        if left == frameSegments.count {
            logger.debug("  At end of range, returning last frame")
            return frameSegments[frameSegments.count - 1]
        }

        let leftDiff = abs(frameSegments[left - 1].timestamp - time)
        let rightDiff = abs(frameSegments[left].timestamp - time)

        logger.debug("  Comparing adjacent frames:")
        logger
            .debug(
                "    Left frame: \(frameSegments[left - 1].timestamp, format: .fixed(precision: 3)) (diff: \(leftDiff, format: .fixed(precision: 3)))"
            )
        logger
            .debug(
                "    Right frame: \(frameSegments[left].timestamp, format: .fixed(precision: 3)) (diff: \(rightDiff, format: .fixed(precision: 3)))"
            )

        let result = leftDiff < rightDiff ? frameSegments[left - 1] : frameSegments[left]
        logger.debug("  Selected frame at \(result.timestamp, format: .fixed(precision: 3))")

        return result
    }
}
