import Foundation
import os

/// Represents a video that has been processed for subtitle translation
public struct ProcessedVideo: Hashable {
    /// The URL of the video file
    public let url: URL

    /// All frame segments with their timestamps, sorted by timestamp
    public let frameSegments: [FrameSegments]

    /// Dictionary mapping original text to translated text
    public let translations: [String: String]

    /// Target language of the translations
    public let targetLanguage: String

    public func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }

    public static func == (lhs: ProcessedVideo, rhs: ProcessedVideo) -> Bool {
        lhs.url == rhs.url
    }

    /// Creates a new ProcessedVideo instance with detected subtitles and their translations
    /// - Parameters:
    ///   - url: The URL of the source video file
    ///   - frameSegments: Array of detected text segments with their timestamps
    ///   - translations: Dictionary mapping original text to translated text
    ///   - targetLanguage: The language code of the translated text
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
    }

    /// Returns the text segments that should be visible at the given timestamp, with translations if available
    /// - Parameter time: The timestamp in seconds from the start of the video
    /// - Returns: Array of text segments with translations
    public func segments(at time: TimeInterval) -> [(segment: TextSegment, translation: String?)] {
        // Binary search for the closest frame
        let frame = binarySearchClosestFrame(at: time)
        guard let frame else {
            return []
        }

        let segmentsWithTranslations = frame.segments.map { segment -> (segment: TextSegment, translation: String?) in
            let translation = translations[segment.text]
            return (segment: segment, translation: translation)
        }

        return segmentsWithTranslations
    }

    /// Binary search to find the frame segments closest to the given timestamp
    private func binarySearchClosestFrame(at time: TimeInterval) -> FrameSegments? {
        guard !frameSegments.isEmpty else { return nil }

        var left = 0
        var right = frameSegments.count - 1

        while left < right {
            let mid = (left + right) / 2
            let midTime = frameSegments[mid].timestamp

            if abs(midTime - time) < 0.001 { // Found exact match within tolerance
                return frameSegments[mid]
            }

            if midTime < time {
                left = mid + 1
            } else {
                right = mid
            }
        }

        // Handle edge cases and return closest frame
        if left == 0 {
            return frameSegments[0]
        }
        if left == frameSegments.count {
            return frameSegments[frameSegments.count - 1]
        }

        let leftDiff = abs(frameSegments[left - 1].timestamp - time)
        let rightDiff = abs(frameSegments[left].timestamp - time)

        let result = leftDiff < rightDiff ? frameSegments[left - 1] : frameSegments[left]

        return result
    }
}
