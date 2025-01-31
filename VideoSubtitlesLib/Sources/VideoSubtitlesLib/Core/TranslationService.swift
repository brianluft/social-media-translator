import Foundation
import os
import SwiftUI
import Translation

private let logger = Logger(subsystem: "VideoSubtitlesLib", category: "TranslationService")

#if targetEnvironment(simulator)
private let isSimulator = true
#else
private let isSimulator = false
#endif

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
    private let session: TranslationSession
    private let targetLanguage: Locale.Language

    // MARK: - Initialization

    /// Initialize the translation service with an existing translation session
    /// - Parameters:
    ///   - session: The translation session to use for translations
    ///   - delegate: Optional delegate to receive progress updates
    ///   - target: Target language being translated into
    public init(
        session: TranslationSession,
        delegate: TranslationProgressDelegate? = nil,
        target: Locale.Language
    ) {
        logger
            .info(
                "Initializing TranslationService with target language: \(target.languageCode?.identifier ?? "unknown")"
            )
        self.session = session
        self.delegate = delegate
        targetLanguage = target
    }

    /// Translate a collection of frame segments
    /// - Parameters:
    ///   - frameSegments: Array of frame segments to translate
    /// - Returns: Dictionary mapping frame IDs to arrays of translated segments
    public func translate(_ frameSegments: [FrameSegments]) async throws -> [UUID: [TranslatedSegment]] {
        logger.info("Starting translation of \(frameSegments.count) frame segments")

        if isSimulator {
            logger.info("Running in simulator - returning mock translations")
            var translatedByFrame: [UUID: [TranslatedSegment]] = [:]

            for frame in frameSegments {
                translatedByFrame[frame.id] = frame.segments.map { segment in
                    TranslatedSegment(
                        originalSegmentId: segment.id,
                        originalText: segment.text,
                        translatedText: "[TR] \(segment.text)",
                        targetLanguage: targetLanguage.languageCode?.identifier ?? "unknown",
                        position: segment.position
                    )
                }
            }

            delegate?.translationDidComplete()
            return translatedByFrame
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
        logger.debug("Found \(uniqueSegments.count) unique text segments to translate")

        // Step 2: Create translation requests
        let requests = uniqueSegments.map { text, _ in
            TranslationSession.Request(sourceText: text, clientIdentifier: text)
        }
        logger.debug("Created \(requests.count) translation requests")

        // Step 3: Translate all segments at once
        let responses: [TranslationSession.Response]
        do {
            logger.info("Sending translation requests to service")
            responses = try await session.translations(from: requests)
            logger.info("Successfully received \(responses.count) translation responses")
            delegate?.translationDidComplete()
        } catch {
            logger.error("Translation failed with error: \(error.localizedDescription)")
            delegate?.translationDidFail(with: error)
            throw error
        }

        // Step 4: Create translated segments and organize by frame ID
        var translatedByFrame: [UUID: [TranslatedSegment]] = [:]

        for response in responses {
            guard let clientId = response.clientIdentifier,
                  let (originalSegment, frameIds) = uniqueSegments[clientId] else {
                logger.warning("Missing client ID or original segment for response")
                continue
            }

            let translatedSegment = TranslatedSegment(
                originalSegmentId: originalSegment.id,
                originalText: originalSegment.text,
                translatedText: response.targetText,
                targetLanguage: targetLanguage.languageCode?.identifier ?? "unknown",
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

        logger.info("Translation complete - processed \(translatedByFrame.count) frames")
        return translatedByFrame
    }
}
