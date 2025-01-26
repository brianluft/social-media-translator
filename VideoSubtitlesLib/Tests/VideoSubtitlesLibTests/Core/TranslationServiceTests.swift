import SwiftUI
import XCTest
@testable import VideoSubtitlesLib

final class TranslationServiceTests: XCTestCase {
    // MARK: - Properties

    private var mockDelegate: MockTranslationDelegate!
    private var hostView: some View {
        Text("Translation Host View")
    }

    // MARK: - Setup

    override func setUp() {
        super.setUp()
        mockDelegate = MockTranslationDelegate()
    }

    // MARK: - Tests

    func testTranslationDeduplication() async throws {
        let service = TranslationService(hostView: hostView, delegate: mockDelegate)
        service.startSession(target: .init(identifier: "es"))

        // Create test data with duplicate text across frames
        let frames = [
            FrameSegments(
                timestamp: 0.0,
                segments: [
                    TextSegment(text: "Hello", position: .zero, confidence: 0.9),
                    TextSegment(text: "World", position: .zero, confidence: 0.9),
                ]
            ),
            FrameSegments(
                timestamp: 0.5,
                segments: [
                    TextSegment(text: "Hello", position: .zero, confidence: 0.9),
                    TextSegment(text: "World", position: .zero, confidence: 0.9),
                ]
            ),
            FrameSegments(
                timestamp: 1.0,
                segments: [
                    TextSegment(text: "Hello", position: .zero, confidence: 0.9),
                    TextSegment(text: "New", position: .zero, confidence: 0.9),
                ]
            ),
        ]

        do {
            let result = try await service.translate(frames)

            // Verify each frame has translations
            XCTAssertEqual(result.count, 3)

            // Verify first frame has both translations
            let frame0Translations = result[frames[0].id]
            XCTAssertEqual(frame0Translations?.count, 2)

            // Verify second frame has both translations
            let frame1Translations = result[frames[1].id]
            XCTAssertEqual(frame1Translations?.count, 2)

            // Verify third frame has both translations
            let frame2Translations = result[frames[2].id]
            XCTAssertEqual(frame2Translations?.count, 2)

            // Verify delegate was called
            XCTAssertTrue(mockDelegate.didComplete)
            XCTAssertNil(mockDelegate.error)

        } catch {
            XCTFail("Translation failed: \(error)")
        }
    }
}

// MARK: - Mock Delegate

private class MockTranslationDelegate: TranslationProgressDelegate {
    var progress: Float = 0
    var didComplete = false
    var error: Error?

    func translationDidProgress(_ progress: Float) {
        self.progress = progress
    }

    func translationDidComplete() {
        didComplete = true
    }

    func translationDidFail(with error: Error) {
        self.error = error
    }
}
