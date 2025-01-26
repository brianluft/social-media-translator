import Foundation
import SwiftUI
#if os(macOS)
import Translation
#endif

@available(macOS 15.0, *)
public protocol TranslationServiceDelegate: AnyObject {
    func translationService(_ service: TranslationService, didUpdateProgress progress: Double)
    func translationService(_ service: TranslationService, didTranslateSegment segment: TranslatedSegment)
    func translationService(_ service: TranslationService, didFinishWithError error: Error?)
}

public enum TranslationServiceError: Error {
    case unsupportedPlatform
    case translationFailed(String)
    case batchTranslationFailed(String)
    case cancelled
}

@available(macOS 15.0, *)
public class TranslationService {
    public weak var delegate: TranslationServiceDelegate?
    let targetLanguage: String // Internal access for TranslationView
    private var isCancelled = false

    public init(targetLanguage: String) {
        self.targetLanguage = targetLanguage
    }

    public func makeTranslationView(for frames: [FrameSegments]) -> some View {
        TranslationView(service: self, frames: frames)
    }
    
    // Internal access for TranslationView
    func processTranslation(frames: [FrameSegments], translateText: (String) async throws -> String) async throws {
        var totalSegments = 0
        var processedSegments = 0
        
        // Count total segments for progress tracking
        for frame in frames {
            totalSegments += frame.segments.count
        }
        
        // Process frames in batches
        for frame in frames {
            if isCancelled {
                throw TranslationServiceError.cancelled
            }
            
            // Process each segment in the frame
            for segment in frame.segments {
                if isCancelled {
                    throw TranslationServiceError.cancelled
                }
                
                // Translate text
                let translatedText = try await translateText(segment.text)
                
                let translatedSegment = TranslatedSegment(
                    originalSegmentId: segment.id,
                    originalText: segment.text,
                    translatedText: translatedText,
                    targetLanguage: targetLanguage,
                    position: segment.position
                )
                
                processedSegments += 1
                let progress = Double(processedSegments) / Double(totalSegments)
                
                await MainActor.run {
                    delegate?.translationService(self, didUpdateProgress: progress)
                    delegate?.translationService(self, didTranslateSegment: translatedSegment)
                }
            }
        }
        
        await MainActor.run {
            delegate?.translationService(self, didFinishWithError: nil)
        }
    }

    public func cancelTranslation() {
        isCancelled = true
    }
}

@available(macOS 15.0, *)
private struct TranslationView: View {
    let service: TranslationService
    let frames: [FrameSegments]
    
    var body: some View {
        Color.clear // Invisible view that just handles translation
            .translationTask(target: Locale.Language(identifier: service.targetLanguage)) { session in
                do {
                    try await service.processTranslation(frames: frames) { text in
                        let response = try await session.translate(text)
                        return response.targetText
                    }
                } catch {
                    await MainActor.run {
                        service.delegate?.translationService(service, didFinishWithError: error)
                    }
                }
            }
    }
}
