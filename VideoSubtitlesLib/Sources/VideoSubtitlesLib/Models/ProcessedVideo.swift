import Foundation
import os

/// Represents a video that has been processed for subtitle translation
public struct ProcessedVideo: Hashable {
    /// The URL of the video file
    public private(set) var url: URL

    /// All frame segments with their timestamps, sorted by timestamp
    private var _frameSegments: [FrameSegments]
    private let lock = NSLock()

    /// Target language of the translations
    public let targetLanguage: String

    public func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }

    public static func == (lhs: ProcessedVideo, rhs: ProcessedVideo) -> Bool {
        lhs.url == rhs.url
    }

    /// Creates a new ProcessedVideo instance
    /// - Parameter targetLanguage: The language code of the translated text
    public init(targetLanguage: String) {
        self.url = URL(fileURLWithPath: "")
        self._frameSegments = []
        self.targetLanguage = targetLanguage
    }

    /// Updates the video URL
    /// - Parameter newURL: The new URL for the video file
    public mutating func updateURL(_ newURL: URL) {
        lock.lock()
        defer { lock.unlock() }
        url = newURL
    }

    /// Appends new frame segments to the video
    /// - Parameter newSegments: Array of new frame segments to append
    /// - Precondition: All timestamps in newSegments must be greater than any existing timestamps,
    ///                 as this method assumes frames are processed sequentially from start to end
    public mutating func appendFrameSegments(_ newSegments: [FrameSegments]) {
        lock.lock()
        defer { lock.unlock() }

        _frameSegments.append(contentsOf: newSegments)
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
            return (segment: segment, translation: segment.translatedText)
        }

        return segmentsWithTranslations
    }

    /// Binary search to find the frame segments closest to the given timestamp
    private func binarySearchClosestFrame(at time: TimeInterval) -> FrameSegments? {
        lock.lock()
        defer { lock.unlock() }

        guard !_frameSegments.isEmpty else { return nil }

        var left = 0
        var right = _frameSegments.count - 1

        while left < right {
            let mid = (left + right) / 2
            let midTime = _frameSegments[mid].timestamp

            if abs(midTime - time) < 0.001 { // Found exact match within tolerance
                return _frameSegments[mid]
            }

            if midTime < time {
                left = mid + 1
            } else {
                right = mid
            }
        }

        // Handle edge cases and return closest frame
        if left == 0 {
            return _frameSegments[0]
        }
        if left == _frameSegments.count {
            return _frameSegments[_frameSegments.count - 1]
        }

        let leftDiff = abs(_frameSegments[left - 1].timestamp - time)
        let rightDiff = abs(_frameSegments[left].timestamp - time)

        let result = leftDiff < rightDiff ? _frameSegments[left - 1] : _frameSegments[left]

        return result
    }
}
