import XCTest
import AVFoundation
@testable import VideoSubtitlesLib

final class SubtitleDetectorTests: XCTestCase {
    
    // MARK: - Test Properties
    private var detector: SubtitleDetector!
    private var mockDelegate: MockSubtitleDetectionDelegate!
    
    // MARK: - Setup/Teardown
    override func setUp() async throws {
        try await super.setUp()
        mockDelegate = MockSubtitleDetectionDelegate()
    }
    
    override func tearDown() async throws {
        detector = nil
        mockDelegate = nil
        try await super.tearDown()
    }
    
    // MARK: - Helper Classes
    private class MockSubtitleDetectionDelegate: SubtitleDetectionDelegate {
        var progressUpdates: [Float] = []
        var completedSubtitles: [SubtitleEntry]?
        var detectionError: Error?
        
        func detectionDidProgress(_ progress: Float) {
            progressUpdates.append(progress)
        }
        
        func detectionDidComplete(subtitles: [SubtitleEntry]) {
            completedSubtitles = subtitles
        }
        
        func detectionDidFail(with error: Error) {
            detectionError = error
        }
    }
    
    // MARK: - Test Methods
    func testSubtitleDetection() async throws {
        // Get the test video URL
        let testBundle = Bundle.module
        guard let videoURL = testBundle.url(forResource: "test1", withExtension: "mp4") else {
            XCTFail("Could not find test video")
            return
        }
        
        let videoAsset = AVAsset(url: videoURL)
        detector = SubtitleDetector(videoAsset: videoAsset, delegate: mockDelegate)
        
        // Perform detection
        try await detector.detectSubtitles()
        
        // Verify progress updates were received
        XCTAssertFalse(mockDelegate.progressUpdates.isEmpty, "Should receive progress updates")
        XCTAssertEqual(mockDelegate.progressUpdates.last, 1.0, "Final progress should be 1.0")
        
        // Verify detected subtitles
        guard let subtitles = mockDelegate.completedSubtitles else {
            XCTFail("No subtitles detected")
            return
        }
        
        // We expect 3 subtitles, one per second
        XCTAssertEqual(subtitles.count, 3, "Should detect 3 subtitles")
        
        // Expected subtitle texts
        let expectedTexts = ["Hello World", "Test subtitle", "Another test"]
        
        // Verify subtitle content and timing
        for (index, subtitle) in subtitles.enumerated() {
            // Verify text content (case-insensitive comparison since OCR might vary in casing)
            XCTAssertEqual(subtitle.text.lowercased(), expectedTexts[index].lowercased(),
                          "Subtitle at index \(index) should match expected text")
            
            // Verify timing (approximately)
            let expectedStart = Double(index)
            XCTAssertEqual(subtitle.startTime, expectedStart, accuracy: 0.5,
                          "Subtitle should start at approximately \(expectedStart) seconds")
            XCTAssertEqual(subtitle.endTime, expectedStart + 1.0, accuracy: 0.5,
                          "Subtitle should end approximately 1 second after start")
            
            // Verify confidence
            XCTAssertGreaterThan(subtitle.confidence, 0.4,
                               "Subtitle confidence should be above minimum threshold")
            
            // Verify position is within valid bounds
            XCTAssertGreaterThanOrEqual(subtitle.position.origin.x, 0)
            XCTAssertGreaterThanOrEqual(subtitle.position.origin.y, 0)
            XCTAssertLessThanOrEqual(subtitle.position.maxX, 1.0)
            XCTAssertLessThanOrEqual(subtitle.position.maxY, 1.0)
        }
    }
    
    func testErrorHandling() async throws {
        // Create an invalid asset to test error handling
        let invalidURL = URL(fileURLWithPath: "/nonexistent/path/video.mp4")
        let invalidAsset = AVAsset(url: invalidURL)
        
        detector = SubtitleDetector(videoAsset: invalidAsset, delegate: mockDelegate)
        
        do {
            try await detector.detectSubtitles()
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
        detector = SubtitleDetector(videoAsset: videoAsset, delegate: mockDelegate)
        
        // Extract and test a single frame at 0.5 seconds (middle of first subtitle)
        let imageGenerator = AVAssetImageGenerator(asset: videoAsset)
        imageGenerator.appliesPreferredTrackTransform = true
        let time = CMTime(seconds: 0.5, preferredTimescale: 600)
        let image = try imageGenerator.copyCGImage(at: time, actualTime: nil)
        
        let subtitles = try await detector.detectText(in: image, at: time)
        
        // Verify single frame detection
        XCTAssertFalse(subtitles.isEmpty, "Should detect text in frame")
        XCTAssertEqual(subtitles.count, 1, "Should find one subtitle")
        
        let subtitle = subtitles[0]
        XCTAssertEqual(subtitle.text.lowercased(), "hello world", "Should detect correct text")
        XCTAssertGreaterThan(subtitle.confidence, 0.4, "Should have sufficient confidence")
        XCTAssertEqual(subtitle.startTime, 0.5, "Should have correct timestamp")
    }
} 