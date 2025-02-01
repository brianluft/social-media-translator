import XCTest
@testable import VideoSubtitlesLib

final class ProcessedVideoTests: XCTestCase {
    let testURL = URL(fileURLWithPath: "/test/video.mp4")

    // MARK: - Test Data

    func makeTestSegment(
        id: UUID,
        text: String,
        translatedText: String? = nil,
        x: CGFloat = 0,
        y: CGFloat = 0
    ) -> TextSegment {
        TextSegment(
            id: id,
            text: text,
            translatedText: translatedText,
            position: CGRect(x: x, y: y, width: 0.2, height: 0.1),
            confidence: 0.9
        )
    }

    func makeFrameSegments(id: UUID, timestamp: TimeInterval, segments: [TextSegment]) -> FrameSegments {
        FrameSegments(id: id, timestamp: timestamp, segments: segments)
    }

    // MARK: - Tests

    func testInitSortsFrameSegments() {
        // Given
        let seg1Id = UUID()
        let seg1 = makeTestSegment(id: seg1Id, text: "Hello", translatedText: "Hola")

        let frame1 = makeFrameSegments(id: UUID(), timestamp: 2.0, segments: [seg1])
        let frame2 = makeFrameSegments(id: UUID(), timestamp: 1.0, segments: [seg1])
        let frame3 = makeFrameSegments(id: UUID(), timestamp: 3.0, segments: [seg1])

        // When
        let video = ProcessedVideo(
            url: testURL,
            frameSegments: [frame1, frame2, frame3],
            targetLanguage: "es"
        )

        // Then
        XCTAssertEqual(video.frameSegments.map(\.timestamp), [1.0, 2.0, 3.0])
    }

    func testSegmentsAtTimeWithExactMatch() {
        // Given
        let seg1Id = UUID()
        let seg1 = makeTestSegment(id: seg1Id, text: "Hello", translatedText: "Hola")

        let frame = makeFrameSegments(id: UUID(), timestamp: 1.0, segments: [seg1])
        let video = ProcessedVideo(
            url: testURL,
            frameSegments: [frame],
            targetLanguage: "es"
        )

        // When
        let segments = video.segments(at: 1.0)

        // Then
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments.first?.translation, "Hola")
        XCTAssertEqual(segments.first?.segment.text, "Hello")
    }

    func testSegmentsAtTimeWithClosestMatch() {
        // Given
        let seg1Id = UUID()
        let seg1 = makeTestSegment(id: seg1Id, text: "Hello", translatedText: "Hola")

        let frame1 = makeFrameSegments(id: UUID(), timestamp: 1.0, segments: [seg1])
        let frame2 = makeFrameSegments(id: UUID(), timestamp: 2.0, segments: [seg1])
        let video = ProcessedVideo(
            url: testURL,
            frameSegments: [frame1, frame2],
            targetLanguage: "es"
        )

        // When/Then
        let segments1 = video.segments(at: 1.2)
        XCTAssertEqual(segments1.count, 1)
        XCTAssertEqual(segments1.first?.translation, "Hola")
        XCTAssertEqual(segments1.first?.segment.text, "Hello")

        let segments2 = video.segments(at: 1.8)
        XCTAssertEqual(segments2.count, 1)
        XCTAssertEqual(segments2.first?.translation, "Hola")
        XCTAssertEqual(segments2.first?.segment.text, "Hello")
    }

    func testSegmentsAtTimeWithMissingTranslation() {
        // Given
        let seg1Id = UUID()
        let seg1 = makeTestSegment(id: seg1Id, text: "Hello", translatedText: nil)

        let frame = makeFrameSegments(id: UUID(), timestamp: 1.0, segments: [seg1])
        let video = ProcessedVideo(
            url: testURL,
            frameSegments: [frame],
            targetLanguage: "es"
        )

        // When
        let segments = video.segments(at: 1.0)

        // Then
        XCTAssertEqual(segments.count, 1)
        XCTAssertNil(segments.first?.translation)
        XCTAssertEqual(segments.first?.segment.text, "Hello")
    }

    func testSegmentsAtTimeWithEmptyResults() {
        // Given
        let video = ProcessedVideo(
            url: testURL,
            frameSegments: [],
            targetLanguage: "es"
        )

        // When
        let segments = video.segments(at: 1.0)

        // Then
        XCTAssertTrue(segments.isEmpty)
    }

    func testSegmentsAtTimeWithEdgeCases() {
        // Given
        let seg1Id = UUID()
        let seg1 = makeTestSegment(id: seg1Id, text: "Hello", translatedText: "Hola")

        let frame1 = makeFrameSegments(id: UUID(), timestamp: 1.0, segments: [seg1])
        let frame2 = makeFrameSegments(id: UUID(), timestamp: 2.0, segments: [seg1])
        let video = ProcessedVideo(
            url: testURL,
            frameSegments: [frame1, frame2],
            targetLanguage: "es"
        )

        // When/Then
        // Before first frame
        let segments1 = video.segments(at: 0.5)
        XCTAssertEqual(segments1.count, 1)
        XCTAssertEqual(segments1.first?.translation, "Hola")
        XCTAssertEqual(segments1.first?.segment.text, "Hello")

        // After last frame
        let segments2 = video.segments(at: 2.5)
        XCTAssertEqual(segments2.count, 1)
        XCTAssertEqual(segments2.first?.translation, "Hola")
        XCTAssertEqual(segments2.first?.segment.text, "Hello")
    }
}
