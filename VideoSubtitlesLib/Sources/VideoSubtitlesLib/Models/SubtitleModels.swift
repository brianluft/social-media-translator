import CoreGraphics
import Foundation

/// Represents a single text segment detected in a video frame
public struct TextSegment: Codable, Identifiable, Equatable {
    /// Unique identifier for the text segment
    public let id: UUID
    /// The detected text content
    public let text: String
    /// Position of the text in the video frame (normalized coordinates 0-1)
    public let position: CGRect
    /// Confidence score of the OCR detection (0-1)
    public let confidence: Float

    public init(
        id: UUID = UUID(),
        text: String,
        position: CGRect,
        confidence: Float
    ) {
        self.id = id
        self.text = text
        self.position = position
        self.confidence = confidence
    }
}

/// Collection of text segments for a specific frame/timestamp
public struct FrameSegments: Codable, Identifiable, Equatable {
    /// Unique identifier for the frame segments collection
    public let id: UUID
    /// Timestamp of the frame in seconds from video start
    public let timestamp: TimeInterval
    /// All text segments detected in this frame
    public let segments: [TextSegment]

    public init(
        id: UUID = UUID(),
        timestamp: TimeInterval,
        segments: [TextSegment]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.segments = segments
    }
}

/// Represents a translated text segment with preserved positioning
public struct TranslatedSegment: Codable, Identifiable, Equatable {
    /// Unique identifier for the translated segment
    public let id: UUID
    /// Reference to the original text segment
    public let originalSegmentId: UUID
    /// The original text content
    public let originalText: String
    /// The translated text content
    public let translatedText: String
    /// The language code of the translation (e.g., "en", "es", "fr")
    public let targetLanguage: String
    /// Position inherited from original segment
    public let position: CGRect

    public init(
        id: UUID = UUID(),
        originalSegmentId: UUID,
        originalText: String,
        translatedText: String,
        targetLanguage: String,
        position: CGRect
    ) {
        self.id = id
        self.originalSegmentId = originalSegmentId
        self.originalText = originalText
        self.translatedText = translatedText
        self.targetLanguage = targetLanguage
        self.position = position
    }
}

// MARK: - CustomStringConvertible

extension TextSegment: CustomStringConvertible {
    public var description: String {
        """
        TextSegment(
            id: \(id),
            text: "\(text)",
            confidence: \(String(format: "%.2f", confidence))
        )
        """
    }
}

extension FrameSegments: CustomStringConvertible {
    public var description: String {
        """
        FrameSegments(
            id: \(id),
            timestamp: \(String(format: "%.2f", timestamp)),
            segments: [\(segments.map(\.description).joined(separator: ", "))]
        )
        """
    }
}

extension TranslatedSegment: CustomStringConvertible {
    public var description: String {
        """
        TranslatedSegment(
            id: \(id),
            original: "\(originalText)",
            translated: "\(translatedText)" (\(targetLanguage))
        )
        """
    }
}
