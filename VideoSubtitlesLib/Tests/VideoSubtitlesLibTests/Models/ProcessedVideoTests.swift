import XCTest
@testable import VideoSubtitlesLib

final class ProcessedVideoTests: XCTestCase {
    let testURL = URL(fileURLWithPath: "/test/video.mp4")

    // MARK: - Test Data

    func makeTestSegment(id: UUID, text: String, x: CGFloat = 0, y: CGFloat = 0) -> TextSegment {
        TextSegment(
            id: id,
            text: text,
            position: CGRect(x: x, y: y, width: 0.2, height: 0.1),
            confidence: 0.9
        )
    }

    func makeFrameSegments(id: UUID, timestamp: TimeInterval, segments: [TextSegment]) -> FrameSegments {
        FrameSegments(id: id, timestamp: timestamp, segments: segments)
    }

    func makeTranslatedSegment(
        id: UUID,
        originalId: UUID,
        originalText: String,
        translatedText: String
    ) -> TranslatedSegment {
        TranslatedSegment(
            id: id,
            originalSegmentId: originalId,
            originalText: originalText,
            translatedText: translatedText,
            targetLanguage: "es",
            position: .zero
        )
    }

    // MARK: - Tests

    func testInitSortsFrameSegments() {
        // Given
        let seg1Id = UUID()
        let seg1 = makeTestSegment(id: seg1Id, text: "Hello")

        let frame1 = makeFrameSegments(id: UUID(), timestamp: 2.0, segments: [seg1])
        let frame2 = makeFrameSegments(id: UUID(), timestamp: 1.0, segments: [seg1])
        let frame3 = makeFrameSegments(id: UUID(), timestamp: 3.0, segments: [seg1])

        // When
        let video = ProcessedVideo(
            url: testURL,
            frameSegments: [frame1, frame2, frame3],
            translatedSegments: []
        )

        // Then
        XCTAssertEqual(video.frameSegments.map(\.timestamp), [1.0, 2.0, 3.0])
    }

    func testSegmentsAtTimeWithExactMatch() {
        // Given
        let seg1Id = UUID()
        let seg1 = makeTestSegment(id: seg1Id, text: "Hello")
        let translated1 = makeTranslatedSegment(
            id: UUID(),
            originalId: seg1Id,
            originalText: "Hello",
            translatedText: "Hola"
        )

        let frame = makeFrameSegments(id: UUID(), timestamp: 1.0, segments: [seg1])
        let video = ProcessedVideo(
            url: testURL,
            frameSegments: [frame],
            translatedSegments: [translated1]
        )

        // When
        let segments = video.segments(at: 1.0)

        // Then
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments.first?.translatedText, "Hola")
    }

    func testSegmentsAtTimeWithClosestMatch() {
        // Given
        let seg1Id = UUID()
        let seg1 = makeTestSegment(id: seg1Id, text: "Hello")
        let translated1 = makeTranslatedSegment(
            id: UUID(),
            originalId: seg1Id,
            originalText: "Hello",
            translatedText: "Hola"
        )

        let frame1 = makeFrameSegments(id: UUID(), timestamp: 1.0, segments: [seg1])
        let frame2 = makeFrameSegments(id: UUID(), timestamp: 2.0, segments: [seg1])
        let video = ProcessedVideo(
            url: testURL,
            frameSegments: [frame1, frame2],
            translatedSegments: [translated1]
        )

        // When/Then
        let segments1 = video.segments(at: 1.2)
        XCTAssertEqual(segments1.count, 1)
        XCTAssertEqual(segments1.first?.translatedText, "Hola")

        let segments2 = video.segments(at: 1.8)
        XCTAssertEqual(segments2.count, 1)
        XCTAssertEqual(segments2.first?.translatedText, "Hola")
    }

    func testSegmentsAtTimeWithMultipleTranslations() {
        // Given
        let seg1Id = UUID()
        let seg1 = makeTestSegment(id: seg1Id, text: "Hello")
        let translated1 = makeTranslatedSegment(
            id: UUID(),
            originalId: seg1Id,
            originalText: "Hello",
            translatedText: "Hola"
        )
        let translated2 = makeTranslatedSegment(
            id: UUID(),
            originalId: seg1Id,
            originalText: "Hello",
            translatedText: "Bonjour"
        )

        let frame = makeFrameSegments(id: UUID(), timestamp: 1.0, segments: [seg1])
        let video = ProcessedVideo(
            url: testURL,
            frameSegments: [frame],
            translatedSegments: [translated1, translated2]
        )

        // When
        let segments = video.segments(at: 1.0)

        // Then
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(Set(segments.map(\.translatedText)), Set(["Hola", "Bonjour"]))
    }

    func testSegmentsAtTimeWithEmptyResults() {
        // Given
        let video = ProcessedVideo(
            url: testURL,
            frameSegments: [],
            translatedSegments: []
        )

        // When
        let segments = video.segments(at: 1.0)

        // Then
        XCTAssertTrue(segments.isEmpty)
    }

    func testSegmentsAtTimeWithEdgeCases() {
        // Given
        let seg1Id = UUID()
        let seg1 = makeTestSegment(id: seg1Id, text: "Hello")
        let translated1 = makeTranslatedSegment(
            id: UUID(),
            originalId: seg1Id,
            originalText: "Hello",
            translatedText: "Hola"
        )

        let frame1 = makeFrameSegments(id: UUID(), timestamp: 1.0, segments: [seg1])
        let frame2 = makeFrameSegments(id: UUID(), timestamp: 2.0, segments: [seg1])
        let video = ProcessedVideo(
            url: testURL,
            frameSegments: [frame1, frame2],
            translatedSegments: [translated1]
        )

        // When/Then
        // Before first frame
        let segments1 = video.segments(at: 0.5)
        XCTAssertEqual(segments1.count, 1)
        XCTAssertEqual(segments1.first?.translatedText, "Hola")

        // After last frame
        let segments2 = video.segments(at: 2.5)
        XCTAssertEqual(segments2.count, 1)
        XCTAssertEqual(segments2.first?.translatedText, "Hola")
    }
}
