import CoreGraphics
import Foundation

/// Represents a single text segment detected in a video frame
public struct TextSegment: Codable, Identifiable, Equatable, Sendable {
    /// Unique identifier for the text segment
    public let id: UUID
    /// The detected text content
    public let text: String
    /// The translated text content (if available)
    public let translatedText: String?
    /// Position of the text in the video frame (normalized coordinates 0-1)
    public let position: CGRect
    /// Confidence score of the OCR detection (0-1)
    public let confidence: Float

    public init(
        id: UUID? = nil,
        text: String,
        translatedText: String? = nil,
        position: CGRect,
        confidence: Float
    ) {
        if let id {
            self.id = id
        } else {
            // Generate stable ID based on content and position for static text
            let idString =
                "\(text)_\(position.origin.x)_\(position.origin.y)_\(position.size.width)_\(position.size.height)"
            let stableId = UUID(uuidString: UUID5.generate(namespace: UUID5.Namespace.url, name: idString)) ?? UUID()
            self.id = stableId
        }
        self.text = text
        self.translatedText = translatedText
        self.position = position
        self.confidence = confidence
    }
}

/// Collection of text segments for a specific frame/timestamp
public struct FrameSegments: Codable, Identifiable, Equatable, Sendable {
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

/// UUID5 namespace generator for stable IDs
private enum UUID5 {
    private static let dns = UUID(uuidString: "6ba7b810-9dad-11d1-80b4-00c04fd430c8")!
    private static let url = UUID(uuidString: "6ba7b811-9dad-11d1-80b4-00c04fd430c8")!

    static func generate(namespace: UUID, name: String) -> String {
        let nameBytes = [UInt8](name.utf8)
        let namespaceBytes = namespace.uuid
        var hash = [UInt8](repeating: 0, count: 16)

        // Simple hash combining namespace and name
        for i in 0 ..< min(16, nameBytes.count) {
            hash[i] = namespaceBytes.3 ^ nameBytes[i]
        }

        // Format as UUID string
        return hash.reduce("") { $0 + String(format: "%02x", $1) }
    }

    enum Namespace {
        static let url = UUID5.url
    }
}

// MARK: - CustomStringConvertible

extension TextSegment: CustomStringConvertible {
    public var description: String {
        """
        TextSegment(
            id: \(id),
            text: "\(text)",
            translatedText: \(String(describing: translatedText)),
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
