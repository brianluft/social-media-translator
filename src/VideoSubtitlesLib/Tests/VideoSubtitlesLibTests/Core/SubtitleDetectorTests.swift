import AVFoundation
import XCTest
@testable import VideoSubtitlesLib

final class SubtitleDetectorTests: XCTestCase {
    // MARK: - Test Properties

    private var detector: SubtitleDetector!
    private var mockDelegate: MockTextDetectionDelegate!

    // MARK: - Setup/Teardown

    override func setUp() async throws {
        try await super.setUp()
        mockDelegate = MockTextDetectionDelegate()
    }

    override func tearDown() async throws {
        detector = nil
        mockDelegate = nil
        try await super.tearDown()
    }

    // MARK: - Helper Classes

    private class MockTextDetectionDelegate: TextDetectionDelegate {
        var progressUpdates: [Float] = []
        var completedFrames: [FrameSegments]?
        var detectionError: Error?

        func detectionDidProgress(_ progress: Float) {
            progressUpdates.append(progress)
        }

        func detectionDidComplete(frames: [FrameSegments]) {
            completedFrames = frames
        }

        func detectionDidFail(with error: Error) {
            detectionError = error
        }
    }

    // MARK: - Test Methods

    func testTextDetection() async throws {
        // Get the test video URL
        let testBundle = Bundle.module
        guard let videoURL = testBundle.url(forResource: "test1", withExtension: "mp4") else {
            XCTFail("Could not find test video")
            return
        }

        let videoAsset = AVAsset(url: videoURL)
        detector = SubtitleDetector(videoAsset: videoAsset, delegate: mockDelegate, recognitionLanguages: ["en-US"])

        // Perform detection
        try await detector.detectText()

        // Verify progress updates were received
        XCTAssertFalse(mockDelegate.progressUpdates.isEmpty, "Should receive progress updates")
        XCTAssertEqual(mockDelegate.progressUpdates.last, 1.0, "Final progress should be 1.0")

        // Verify detected frames
        guard let frames = mockDelegate.completedFrames else {
            XCTFail("No frames detected")
            return
        }

        // We expect frames with text
        XCTAssertFalse(frames.isEmpty, "Should detect text in frames")

        // Expected texts that should appear somewhere in the frames
        let expectedTexts = ["Hello World", "Test subtitle", "Another test"]

        // Collect all detected text
        let detectedTexts = frames.flatMap { frame in
            frame.segments.map { $0.text.lowercased() }
        }

        // Verify each expected text appears at least once
        for expectedText in expectedTexts {
            XCTAssertTrue(
                detectedTexts.contains { $0.contains(expectedText.lowercased()) },
                "Should find '\(expectedText)' in detected text"
            )
        }

        // Verify frame properties
        for frame in frames {
            // Verify timing is reasonable
            XCTAssertGreaterThanOrEqual(frame.timestamp, 0.0)
            XCTAssertLessThanOrEqual(frame.timestamp, 5.0) // Assuming test video is under 5s

            // Verify segments in frame
            for segment in frame.segments {
                // Verify confidence
                XCTAssertGreaterThan(
                    segment.confidence,
                    0.4,
                    "Text confidence should be above minimum threshold"
                )

                // Verify position is within valid bounds
                XCTAssertGreaterThanOrEqual(segment.position.origin.x, 0)
                XCTAssertGreaterThanOrEqual(segment.position.origin.y, 0)
                XCTAssertLessThanOrEqual(segment.position.maxX, 1.0)
                XCTAssertLessThanOrEqual(segment.position.maxY, 1.0)
            }
        }
    }

    func testErrorHandling() async throws {
        // Create an invalid asset to test error handling
        let invalidURL = URL(fileURLWithPath: "/nonexistent/path/video.mp4")
        let invalidAsset = AVAsset(url: invalidURL)

        detector = SubtitleDetector(videoAsset: invalidAsset, delegate: mockDelegate, recognitionLanguages: ["en-US"])

        do {
            try await detector.detectText()
            XCTFail("Expected error for invalid asset")
        } catch {
            XCTAssertNotNil(mockDelegate.detectionError, "Delegate should receive error")
        }
    }

    func testSingleFrameDetection() async throws {
        // Get the test video URL
        let testBundle = Bundle.module
        guard let videoURL = testBundle.url(forResource: "test1", withExtension: "mp4") else {
            XCTFail("Could not find test video")
            return
        }

        let videoAsset = AVAsset(url: videoURL)
        detector = SubtitleDetector(videoAsset: videoAsset, delegate: mockDelegate, recognitionLanguages: ["en-US"])

        // Extract and test a single frame at 0.5 seconds (middle of first text)
        let imageGenerator = AVAssetImageGenerator(asset: videoAsset)
        imageGenerator.appliesPreferredTrackTransform = true
        let time = CMTime(seconds: 0.5, preferredTimescale: 600)
        let image = try imageGenerator.copyCGImage(at: time, actualTime: nil)

        let frameSegments = try await detector.detectText(in: image, at: time)

        // Verify single frame detection
        XCTAssertFalse(frameSegments.segments.isEmpty, "Should detect text in frame")

        // Find segment with highest confidence
        let bestSegment = frameSegments.segments.max(by: { $0.confidence < $1.confidence })!

        XCTAssertEqual(bestSegment.text.lowercased(), "hello world", "Should detect correct text")
        XCTAssertGreaterThan(bestSegment.confidence, 0.4, "Should have sufficient confidence")
        XCTAssertEqual(frameSegments.timestamp, 0.5, "Should have correct timestamp")

        // Verify position is within valid bounds
        XCTAssertGreaterThanOrEqual(bestSegment.position.origin.x, 0)
        XCTAssertGreaterThanOrEqual(bestSegment.position.origin.y, 0)
        XCTAssertLessThanOrEqual(bestSegment.position.maxX, 1.0)
        XCTAssertLessThanOrEqual(bestSegment.position.maxY, 1.0)

        // Verify position is roughly in the expected region (2/3 down the frame)
        XCTAssertGreaterThan(
            bestSegment.position.origin.y,
            0.5,
            "Text should be in lower half of frame"
        )
    }

    func testHighFrameRateVideo() async throws {
        // Get the test video URL
        let testBundle = Bundle.module
        guard let videoURL = testBundle.url(forResource: "test2", withExtension: "mp4") else {
            XCTFail("Could not find high frame rate test video")
            return
        }

        let videoAsset = AVAsset(url: videoURL)
        detector = SubtitleDetector(videoAsset: videoAsset, delegate: mockDelegate, recognitionLanguages: ["en-US"])

        // Perform detection
        try await detector.detectText()

        // Verify progress updates
        XCTAssertFalse(mockDelegate.progressUpdates.isEmpty, "Should receive progress updates")
        XCTAssertEqual(mockDelegate.progressUpdates.last, 1.0, "Final progress should be 1.0")

        // Verify detected frames
        guard let frames = mockDelegate.completedFrames else {
            XCTFail("No frames detected")
            return
        }

        // Group frames by text content to verify timing
        let frameGroups = Dictionary(grouping: frames) { frame -> String in
            frame.segments.max(by: { $0.confidence < $1.confidence })?.text.lowercased() ?? ""
        }

        // Verify "test message" group
        if let testMessageFrames = frameGroups["test message"] {
            let timestamps = testMessageFrames.map(\.timestamp).sorted()
            XCTAssertGreaterThan(timestamps.count, 0, "Should have frames with 'test message'")
            XCTAssertEqual(timestamps.first!, 0.0, accuracy: 0.5, "Should start at beginning")
            XCTAssertEqual(timestamps.last!, 1.0, accuracy: 0.5, "Should end around 1s")
        } else {
            XCTFail("Missing 'test message' frames")
        }

        // Verify "second test" group
        if let secondTestFrames = frameGroups["second test"] {
            let timestamps = secondTestFrames.map(\.timestamp).sorted()
            XCTAssertGreaterThan(timestamps.count, 0, "Should have frames with 'second test'")
            XCTAssertEqual(timestamps.first!, 2.0, accuracy: 0.5, "Should start around 2s")
            XCTAssertEqual(timestamps.last!, 3.0, accuracy: 0.5, "Should end around 3s")
        } else {
            XCTFail("Missing 'second test' frames")
        }

        // Verify positions are within bounds and in expected region
        for frame in frames {
            for segment in frame.segments {
                XCTAssertGreaterThanOrEqual(segment.position.origin.x, 0)
                XCTAssertGreaterThanOrEqual(segment.position.origin.y, 0)
                XCTAssertLessThanOrEqual(segment.position.maxX, 1.0)
                XCTAssertLessThanOrEqual(segment.position.maxY, 1.0)

                // Verify position is roughly in the expected region (2/3 down the frame)
                XCTAssertGreaterThan(
                    segment.position.origin.y,
                    0.5,
                    "Text should be in lower half of frame"
                )
            }
        }
    }

    func testChineseSubtitlesDetection() async throws {
        // Get the test video URL
        let testBundle = Bundle.module
        guard let videoURL = testBundle.url(forResource: "test3", withExtension: "mp4") else {
            XCTFail("Could not find test video")
            return
        }

        let videoAsset = AVAsset(url: videoURL)
        detector = SubtitleDetector(videoAsset: videoAsset, delegate: mockDelegate, recognitionLanguages: ["zh-Hans"])

        // Perform detection
        try await detector.detectText()

        // Verify progress updates were received
        XCTAssertFalse(mockDelegate.progressUpdates.isEmpty, "Should receive progress updates")
        XCTAssertEqual(mockDelegate.progressUpdates.last, 1.0, "Final progress should be 1.0")

        // Verify detected frames
        guard let frames = mockDelegate.completedFrames else {
            XCTFail("No frames detected")
            return
        }

        // Expected Chinese texts and their frame ranges (30 fps)
        let expectedTexts = [
            ("这是一条测试消息", 13...61),
            ("再试一条消息", 79...125)
        ]

        // Group frames by timestamp
        let framesByTimestamp = Dictionary(grouping: frames) { frame -> Int in
            Int(round(frame.timestamp * 30.0)) // Convert timestamp to frame number at 30fps
        }

        // Verify each expected text appears in its frame range
        for (expectedText, frameRange) in expectedTexts {
            let framesInRange = frameRange.compactMap { framesByTimestamp[$0] }.flatMap { $0 }
            
            // Verify we found frames in the expected range
            XCTAssertFalse(framesInRange.isEmpty, "Should find frames for text: \(expectedText)")
            
            // Check if the text appears in the frames and is positioned correctly
            let hasCorrectlyPositionedText = framesInRange.contains { frame in
                frame.segments.contains { segment in
                    // Text should be in lower 1/3rd of the frame
                    let isInLowerThird = segment.position.origin.y >= 0.66
                    return segment.text.contains(expectedText) && isInLowerThird
                }
            }
            
            XCTAssertTrue(
                hasCorrectlyPositionedText,
                "Should find '\(expectedText)' in lower third of frame range \(frameRange)"
            )
        }

        // Verify "electroly" appears in correct position
        let allSegments = frames.flatMap { $0.segments }
        let electrolySegment = allSegments.first { segment in
            segment.text.lowercased().contains("electroly")
        }
        
        XCTAssertNotNil(electrolySegment, "Should find 'electroly' text")
        if let segment = electrolySegment {
            // Verify position in lower 1/10th
            XCTAssertGreaterThanOrEqual(segment.position.origin.y, 0.9, "Should be in lower 1/10th")
            // Verify position in left half
            XCTAssertLessThanOrEqual(segment.position.maxX, 0.5, "Should be in left half")
        }
    }
}
