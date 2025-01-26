import Foundation

public protocol TranslationServiceDelegate: AnyObject {
    func translationService(_ service: TranslationService, didUpdateProgress progress: Double)
    func translationService(_ service: TranslationService, didTranslateSegment segment: TranslatedSegment)
    func translationService(_ service: TranslationService, didFinishWithError error: Error?)
}

public class TranslationService {
    public weak var delegate: TranslationServiceDelegate?
    private let targetLanguage: String
    
    public init(targetLanguage: String) {
        self.targetLanguage = targetLanguage
    }
    
    public func translateFrames(_ frames: [FrameSegments]) {
        // TODO: Implement translation using Apple's Translation framework
        // This will be implemented in the next phase
    }
    
    public func cancelTranslation() {
        // TODO: Implement cancellation logic
    }
} 