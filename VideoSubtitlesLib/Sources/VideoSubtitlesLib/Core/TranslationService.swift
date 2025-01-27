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
    private var translationSession: TranslationSession?
    private let targetLanguage: Locale.Language
    private var initializationContinuation: CheckedContinuation<Void, Error>?

    // MARK: - Initialization

    /// Initialize the translation service with a SwiftUI view that will host the translation session
    /// - Parameters:
    ///   - hostView: A SwiftUI view that will host the translation session
    ///   - delegate: Optional delegate to receive progress updates
    ///   - source: Source language (optional, will be auto-detected if nil)
    ///   - target: Target language to translate into
    public init(
        hostView: some View,
        delegate: TranslationProgressDelegate? = nil,
        source: Locale.Language? = nil,
        target: Locale.Language
    ) {
        logger
            .info(
                "Initializing TranslationService with target language: \(target.languageCode?.identifier ?? "unknown")"
            )
        self.delegate = delegate
        targetLanguage = target

        let configuration = TranslationSession.Configuration(source: source, target: target)
        logger
            .debug(
                "Created translation configuration - source: \(source?.languageCode?.identifier ?? "auto"), target: \(target.languageCode?.identifier ?? "unknown")"
            )

        logger.info("Setting up translation task with host view")
        _ = hostView.translationTask(configuration) { [weak self] session in
            guard let self else { return }

            self.translationSession = session
            logger.info("Translation session successfully initialized")
            self.initializationContinuation?.resume()
            self.initializationContinuation = nil
        }
        logger.debug("Translation task created successfully")
    }

    /// Wait for the translation session to be initialized
    private func waitForInitialization() async throws {
        if translationSession != nil {
            logger.debug("Translation session already initialized")
            return
        }

        logger.info("Waiting for translation session initialization")
        try await withCheckedThrowingContinuation { continuation in
            self.initializationContinuation = continuation
        }
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

        // Wait for session initialization if needed
        try await waitForInitialization()

        guard let session = translationSession else {
            logger.error("Translation failed - session not initialized")
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
