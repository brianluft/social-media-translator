import Foundation
import CoreGraphics

/// Represents a detected subtitle entry in the video
public struct SubtitleEntry: Codable, Identifiable, Equatable {
    /// Unique identifier for the subtitle entry
    public let id: UUID
    /// The detected text content
    public let text: String
    /// Start time of the subtitle in seconds from video start
    public let startTime: TimeInterval
    /// End time of the subtitle in seconds from video start
    public let endTime: TimeInterval
    /// Position of the subtitle in the video frame (normalized coordinates 0-1)
    public let position: CGRect
    /// Confidence score of the OCR detection (0-1)
    public let confidence: Float
    
    public init(
        id: UUID = UUID(),
        text: String,
        startTime: TimeInterval,
        endTime: TimeInterval,
        position: CGRect,
        confidence: Float
    ) {
        self.id = id
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.position = position
        self.confidence = confidence
    }
}

/// Represents a translated subtitle with original and translated text
public struct TranslatedSubtitle: Codable, Identifiable, Equatable {
    /// Unique identifier for the translated subtitle
    public let id: UUID
    /// Reference to the original subtitle entry
    public let originalSubtitleId: UUID
    /// The original text content
    public let originalText: String
    /// The translated text content
    public let translatedText: String
    /// The language code of the translation (e.g., "en", "es", "fr")
    public let targetLanguage: String
    /// Start time inherited from original subtitle
    public let startTime: TimeInterval
    /// End time inherited from original subtitle
    public let endTime: TimeInterval
    /// Position inherited from original subtitle
    public let position: CGRect
    
    public init(
        id: UUID = UUID(),
        originalSubtitleId: UUID,
        originalText: String,
        translatedText: String,
        targetLanguage: String,
        startTime: TimeInterval,
        endTime: TimeInterval,
        position: CGRect
    ) {
        self.id = id
        self.originalSubtitleId = originalSubtitleId
        self.originalText = originalText
        self.translatedText = translatedText
        self.targetLanguage = targetLanguage
        self.startTime = startTime
        self.endTime = endTime
        self.position = position
    }
}

// MARK: - CustomStringConvertible
extension SubtitleEntry: CustomStringConvertible {
    public var description: String {
        return """
        SubtitleEntry(
            id: \(id),
            text: "\(text)",
            time: \(String(format: "%.2f", startTime))-\(String(format: "%.2f", endTime)),
            confidence: \(String(format: "%.2f", confidence))
        )
        """
    }
}

extension TranslatedSubtitle: CustomStringConvertible {
    public var description: String {
        return """
        TranslatedSubtitle(
            id: \(id),
            original: "\(originalText)",
            translated: "\(translatedText)" (\(targetLanguage)),
            time: \(String(format: "%.2f", startTime))-\(String(format: "%.2f", endTime))
        )
        """
    }
} 