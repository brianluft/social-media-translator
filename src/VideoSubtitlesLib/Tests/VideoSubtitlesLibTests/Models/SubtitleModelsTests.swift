import XCTest
import CoreGraphics
@testable import VideoSubtitlesLib

final class SubtitleModelsTests: XCTestCase {
    
    // MARK: - SubtitleEntry Tests
    
    func testSubtitleEntryJSONCoding() throws {
        let id = UUID()
        let original = SubtitleEntry(
            id: id,
            text: "Hello World",
            startTime: 1.5,
            endTime: 3.0,
            position: CGRect(x: 0.1, y: 0.8, width: 0.8, height: 0.1),
            confidence: 0.95
        )
        
        // Test encoding
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        // Test decoding
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(SubtitleEntry.self, from: data)
        
        // Verify equality
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.text, original.text)
        XCTAssertEqual(decoded.startTime, original.startTime)
        XCTAssertEqual(decoded.endTime, original.endTime)
        XCTAssertEqual(decoded.position, original.position)
        XCTAssertEqual(decoded.confidence, original.confidence)
    }
    
    func testSubtitleEntryEquatable() {
        let id = UUID()
        let entry1 = SubtitleEntry(
            id: id,
            text: "Test",
            startTime: 1.0,
            endTime: 2.0,
            position: CGRect(x: 0.1, y: 0.8, width: 0.8, height: 0.1),
            confidence: 0.9
        )
        
        let entry2 = SubtitleEntry(
            id: id,
            text: "Test",
            startTime: 1.0,
            endTime: 2.0,
            position: CGRect(x: 0.1, y: 0.8, width: 0.8, height: 0.1),
            confidence: 0.9
        )
        
        XCTAssertEqual(entry1, entry2)
    }
    
    // MARK: - TranslatedSubtitle Tests
    
    func testTranslatedSubtitleJSONCoding() throws {
        let id = UUID()
        let originalId = UUID()
        let original = TranslatedSubtitle(
            id: id,
            originalSubtitleId: originalId,
            originalText: "Hello",
            translatedText: "Hola",
            targetLanguage: "es",
            startTime: 1.5,
            endTime: 3.0,
            position: CGRect(x: 0.1, y: 0.8, width: 0.8, height: 0.1)
        )
        
        // Test encoding
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        // Test decoding
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(TranslatedSubtitle.self, from: data)
        
        // Verify equality
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.originalSubtitleId, original.originalSubtitleId)
        XCTAssertEqual(decoded.originalText, original.originalText)
        XCTAssertEqual(decoded.translatedText, original.translatedText)
        XCTAssertEqual(decoded.targetLanguage, original.targetLanguage)
        XCTAssertEqual(decoded.startTime, original.startTime)
        XCTAssertEqual(decoded.endTime, original.endTime)
        XCTAssertEqual(decoded.position, original.position)
    }
    
    func testTranslatedSubtitleEquatable() {
        let id = UUID()
        let originalId = UUID()
        let subtitle1 = TranslatedSubtitle(
            id: id,
            originalSubtitleId: originalId,
            originalText: "Hello",
            translatedText: "Hola",
            targetLanguage: "es",
            startTime: 1.0,
            endTime: 2.0,
            position: CGRect(x: 0.1, y: 0.8, width: 0.8, height: 0.1)
        )
        
        let subtitle2 = TranslatedSubtitle(
            id: id,
            originalSubtitleId: originalId,
            originalText: "Hello",
            translatedText: "Hola",
            targetLanguage: "es",
            startTime: 1.0,
            endTime: 2.0,
            position: CGRect(x: 0.1, y: 0.8, width: 0.8, height: 0.1)
        )
        
        XCTAssertEqual(subtitle1, subtitle2)
    }
    
    func testSubtitleEntryDescription() {
        let id = UUID()
        let entry = SubtitleEntry(
            id: id,
            text: "Test",
            startTime: 1.5,
            endTime: 3.0,
            position: CGRect(x: 0.1, y: 0.8, width: 0.8, height: 0.1),
            confidence: 0.95
        )
        
        let description = entry.description
        XCTAssertTrue(description.contains("Test"))
        XCTAssertTrue(description.contains("1.50"))
        XCTAssertTrue(description.contains("3.00"))
        XCTAssertTrue(description.contains("0.95"))
    }
    
    func testTranslatedSubtitleDescription() {
        let id = UUID()
        let originalId = UUID()
        let subtitle = TranslatedSubtitle(
            id: id,
            originalSubtitleId: originalId,
            originalText: "Hello",
            translatedText: "Hola",
            targetLanguage: "es",
            startTime: 1.5,
            endTime: 3.0,
            position: CGRect(x: 0.1, y: 0.8, width: 0.8, height: 0.1)
        )
        
        let description = subtitle.description
        XCTAssertTrue(description.contains("Hello"))
        XCTAssertTrue(description.contains("Hola"))
        XCTAssertTrue(description.contains("es"))
        XCTAssertTrue(description.contains("1.50"))
        XCTAssertTrue(description.contains("3.00"))
    }
} 