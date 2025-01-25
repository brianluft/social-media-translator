import Foundation
import Vision
import AVFoundation

public protocol SubtitleDetectorDelegate: AnyObject {
    func subtitleDetector(_ detector: SubtitleDetector, didUpdateProgress progress: Double)
    func subtitleDetector(_ detector: SubtitleDetector, didDetectSubtitle subtitle: SubtitleEntry)
    func subtitleDetector(_ detector: SubtitleDetector, didFinishWithError error: Error?)
}

public class SubtitleDetector {
    public weak var delegate: SubtitleDetectorDelegate?
    private let videoAsset: AVAsset
    private var subtitles: [SubtitleEntry] = []
    
    public init(videoAsset: AVAsset) {
        self.videoAsset = videoAsset
    }
    
    public func startDetection() {
        // TODO: Implement OCR detection using Vision framework
        // This will be implemented in the next phase
    }
    
    public func cancelDetection() {
        // TODO: Implement cancellation logic
    }
} 