import Foundation
import SwiftUI
import Translation

/// Protocol for reporting translation progress
public protocol TranslationProgressDelegate: AnyObject {
    func translationDidProgress(_ progress: Float)
    func translationDidComplete()
    func translationDidFail(with error: Error)
}

/// Service that handles translation of subtitle segments using Apple's Translation framework
public class TranslationService {
    // MARK: - Properties

    private weak var delegate: TranslationProgressDelegate?
    private var translationSession: TranslationSession?
    private var configuration: TranslationSession.Configuration?

    // MARK: - Initialization

    /// Initialize the translation service with a SwiftUI view that will host the translation session
    /// - Parameters:
    ///   - hostView: A SwiftUI view that will host the translation session
    ///   - delegate: Optional delegate to receive progress updates
    public init(hostView: some View, delegate: TranslationProgressDelegate? = nil) {
        self.delegate = delegate

        // Set up translation task on host view
        _ = hostView.translationTask(configuration) { [weak self] session in
            self?.translationSession = session
        }
    }

    /// Start a translation session with specified languages
    /// - Parameters:
    ///   - source: Source language (optional, will be auto-detected if nil)
    ///   - target: Target language
    public func startSession(source: Locale.Language? = nil, target: Locale.Language) {
        configuration = TranslationSession.Configuration(source: source, target: target)
    }

    /// Translate a collection of frame segments
    /// - Parameters:
    ///   - frameSegments: Array of frame segments to translate
    /// - Returns: Dictionary mapping frame IDs to arrays of translated segments
    public func translate(_ frameSegments: [FrameSegments]) async throws -> [UUID: [TranslatedSegment]] {
        guard let session = translationSession else {
            throw NSError(
                domain: "TranslationService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Translation session not initialized"]
            )
        }

        // Step 1: Collect unique text segments
        var uniqueSegments: [String: (TextSegment, Set<UUID>)] = [:]
        for frame in frameSegments {
            for segment in frame.segments {
                if uniqueSegments[segment.text] == nil {
                    uniqueSegments[segment.text] = (segment, [frame.id])
                } else {
                    uniqueSegments[segment.text]?.1.insert(frame.id)
                }
            }
        }

        // Step 2: Create translation requests
        let requests = uniqueSegments.map { text, _ in
            TranslationSession.Request(sourceText: text, clientIdentifier: text)
        }

        // Step 3: Translate all segments at once
        let responses: [TranslationSession.Response]
        do {
            responses = try await session.translations(from: requests)
            delegate?.translationDidComplete()
        } catch {
            delegate?.translationDidFail(with: error)
            throw error
        }

        // Step 4: Create translated segments and organize by frame ID
        var translatedByFrame: [UUID: [TranslatedSegment]] = [:]

        for response in responses {
            guard let clientId = response.clientIdentifier,
                  let (originalSegment, frameIds) = uniqueSegments[clientId] else { continue }

            let translatedSegment = TranslatedSegment(
                originalSegmentId: originalSegment.id,
                originalText: originalSegment.text,
                translatedText: response.targetText,
                targetLanguage: "es", // TODO: Get actual language code from configuration
                position: originalSegment.position
            )

            // Add translated segment to each frame it appears in
            for frameId in frameIds {
                if translatedByFrame[frameId] == nil {
                    translatedByFrame[frameId] = []
                }
                translatedByFrame[frameId]?.append(translatedSegment)
            }
        }

        return translatedByFrame
    }
}
