import XCTest
import CoreGraphics
@testable import VideoSubtitlesLib

final class SubtitleModelsTests: XCTestCase {
    
    // MARK: - TextSegment Tests
    
    func testTextSegmentJSONCoding() throws {
        let id = UUID()
        let original = TextSegment(
            id: id,
            text: "Hello World",
            position: CGRect(x: 0.1, y: 0.8, width: 0.8, height: 0.1),
            confidence: 0.95
        )
        
        // Test encoding
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        // Test decoding
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(TextSegment.self, from: data)
        
        // Verify equality
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.text, original.text)
        XCTAssertEqual(decoded.position, original.position)
        XCTAssertEqual(decoded.confidence, original.confidence)
    }
    
    func testTextSegmentEquatable() {
        let id = UUID()
        let segment1 = TextSegment(
            id: id,
            text: "Test",
            position: CGRect(x: 0.1, y: 0.8, width: 0.8, height: 0.1),
            confidence: 0.9
        )
        
        let segment2 = TextSegment(
            id: id,
            text: "Test",
            position: CGRect(x: 0.1, y: 0.8, width: 0.8, height: 0.1),
            confidence: 0.9
        )
        
        XCTAssertEqual(segment1, segment2)
    }
    
    // MARK: - FrameSegments Tests
    
    func testFrameSegmentsJSONCoding() throws {
        let id = UUID()
        let textSegment = TextSegment(
            text: "Hello",
            position: CGRect(x: 0.1, y: 0.8, width: 0.8, height: 0.1),
            confidence: 0.95
        )
        
        let original = FrameSegments(
            id: id,
            timestamp: 1.5,
            segments: [textSegment]
        )
        
        // Test encoding
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        // Test decoding
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(FrameSegments.self, from: data)
        
        // Verify equality
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.timestamp, original.timestamp)
        XCTAssertEqual(decoded.segments.count, original.segments.count)
        XCTAssertEqual(decoded.segments.first?.text, original.segments.first?.text)
    }
    
    // MARK: - TranslatedSegment Tests
    
    func testTranslatedSegmentJSONCoding() throws {
        let id = UUID()
        let originalId = UUID()
        let original = TranslatedSegment(
            id: id,
            originalSegmentId: originalId,
            originalText: "Hello",
            translatedText: "Hola",
            targetLanguage: "es",
            position: CGRect(x: 0.1, y: 0.8, width: 0.8, height: 0.1)
        )
        
        // Test encoding
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        // Test decoding
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(TranslatedSegment.self, from: data)
        
        // Verify equality
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.originalSegmentId, original.originalSegmentId)
        XCTAssertEqual(decoded.originalText, original.originalText)
        XCTAssertEqual(decoded.translatedText, original.translatedText)
        XCTAssertEqual(decoded.targetLanguage, original.targetLanguage)
        XCTAssertEqual(decoded.position, original.position)
    }
    
    func testTranslatedSegmentEquatable() {
        let id = UUID()
        let originalId = UUID()
        let segment1 = TranslatedSegment(
            id: id,
            originalSegmentId: originalId,
            originalText: "Hello",
            translatedText: "Hola",
            targetLanguage: "es",
            position: CGRect(x: 0.1, y: 0.8, width: 0.8, height: 0.1)
        )
        
        let segment2 = TranslatedSegment(
            id: id,
            originalSegmentId: originalId,
            originalText: "Hello",
            translatedText: "Hola",
            targetLanguage: "es",
            position: CGRect(x: 0.1, y: 0.8, width: 0.8, height: 0.1)
        )
        
        XCTAssertEqual(segment1, segment2)
    }
    
    // MARK: - Description Tests
    
    func testTextSegmentDescription() {
        let id = UUID()
        let segment = TextSegment(
            id: id,
            text: "Test",
            position: CGRect(x: 0.1, y: 0.8, width: 0.8, height: 0.1),
            confidence: 0.95
        )
        
        let description = segment.description
        XCTAssertTrue(description.contains("Test"))
        XCTAssertTrue(description.contains("0.95"))
    }
    
    func testFrameSegmentsDescription() {
        let id = UUID()
        let textSegment = TextSegment(
            text: "Hello",
            position: CGRect(x: 0.1, y: 0.8, width: 0.8, height: 0.1),
            confidence: 0.95
        )
        
        let frameSegments = FrameSegments(
            id: id,
            timestamp: 1.5,
            segments: [textSegment]
        )
        
        let description = frameSegments.description
        XCTAssertTrue(description.contains("Hello"))
        XCTAssertTrue(description.contains("1.50"))
    }
    
    func testTranslatedSegmentDescription() {
        let id = UUID()
        let originalId = UUID()
        let segment = TranslatedSegment(
            id: id,
            originalSegmentId: originalId,
            originalText: "Hello",
            translatedText: "Hola",
            targetLanguage: "es",
            position: CGRect(x: 0.1, y: 0.8, width: 0.8, height: 0.1)
        )
        
        let description = segment.description
        XCTAssertTrue(description.contains("Hello"))
        XCTAssertTrue(description.contains("Hola"))
        XCTAssertTrue(description.contains("es"))
    }
} 