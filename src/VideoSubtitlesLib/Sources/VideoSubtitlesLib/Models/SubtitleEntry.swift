import Foundation
import CoreGraphics

public struct SubtitleEntry: Identifiable, Codable {
    public let id: UUID
    public let text: String
    public let startTime: TimeInterval
    public let endTime: TimeInterval
    public let position: CGRect
    public var translatedText: String?
    
    public init(
        id: UUID = UUID(),
        text: String,
        startTime: TimeInterval,
        endTime: TimeInterval,
        position: CGRect,
        translatedText: String? = nil
    ) {
        self.id = id
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.position = position
        self.translatedText = translatedText
    }
} 