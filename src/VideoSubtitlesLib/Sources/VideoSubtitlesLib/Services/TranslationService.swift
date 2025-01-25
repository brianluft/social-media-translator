import Foundation

public protocol TranslationServiceDelegate: AnyObject {
    func translationService(_ service: TranslationService, didUpdateProgress progress: Double)
    func translationService(_ service: TranslationService, didTranslateSubtitle subtitle: SubtitleEntry)
    func translationService(_ service: TranslationService, didFinishWithError error: Error?)
}

public class TranslationService {
    public weak var delegate: TranslationServiceDelegate?
    private let targetLanguage: String
    
    public init(targetLanguage: String) {
        self.targetLanguage = targetLanguage
    }
    
    public func translateSubtitles(_ subtitles: [SubtitleEntry]) {
        // TODO: Implement translation using Apple's Translation framework
        // This will be implemented in the next phase
    }
    
    public func cancelTranslation() {
        // TODO: Implement cancellation logic
    }
} 