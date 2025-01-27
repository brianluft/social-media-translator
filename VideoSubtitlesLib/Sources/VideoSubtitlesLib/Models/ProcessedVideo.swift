import Foundation

/// Represents a video that has been processed for subtitle translation
public struct ProcessedVideo {
    /// The URL of the video file
    public let url: URL

    /// All frame segments with their timestamps, sorted by timestamp
    public let frameSegments: [FrameSegments]

    /// All translated segments
    public let translatedSegments: [TranslatedSegment]

    /// Lookup table from original segment ID to translated segments
    private let translatedSegmentsByOriginalId: [UUID: [TranslatedSegment]]

    public init(
        url: URL,
        frameSegments: [FrameSegments],
        translatedSegments: [TranslatedSegment]
    ) {
        self.url = url
        // Sort frame segments by timestamp for binary search
        self.frameSegments = frameSegments.sorted(by: { $0.timestamp < $1.timestamp })
        self.translatedSegments = translatedSegments

        // Build lookup table
        var lookup: [UUID: [TranslatedSegment]] = [:]
        for segment in translatedSegments {
            lookup[segment.originalSegmentId, default: []].append(segment)
        }
        translatedSegmentsByOriginalId = lookup
    }

    /// Returns the translated segments that should be visible at the given timestamp
    /// - Parameter time: The timestamp in seconds from the start of the video
    /// - Returns: Array of translated segments that should be displayed
    public func segments(at time: TimeInterval) -> [TranslatedSegment] {
        // Binary search for the closest frame
        let frame = binarySearchClosestFrame(at: time)
        guard let frame else { return [] }

        // Get translated segments using lookup table
        return frame.segments.flatMap { segment in
            translatedSegmentsByOriginalId[segment.id] ?? []
        }
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
        if left == 0 { return frameSegments[0] }
        if left == frameSegments.count { return frameSegments[frameSegments.count - 1] }

        let leftDiff = abs(frameSegments[left - 1].timestamp - time)
        let rightDiff = abs(frameSegments[left].timestamp - time)
        return leftDiff < rightDiff ? frameSegments[left - 1] : frameSegments[left]
    }
}
