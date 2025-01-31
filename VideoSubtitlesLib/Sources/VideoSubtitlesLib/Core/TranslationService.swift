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
public protocol TranslationProgressDelegate: AnyObject, Sendable {
    func translationDidProgress(_ progress: Float) async
    func translationDidComplete() async
    func translationDidFail(with error: Error) async
}

/// A Sendable wrapper around TranslationSession
private struct SendableTranslationSession: @unchecked Sendable {
    let session: TranslationSession

    func translate(requests: [TranslationSession.Request]) async throws -> [TranslationSession.Response] {
        try await session.translations(from: requests)
    }
}

/// Service that handles translation of subtitle segments using Apple's Translation framework
@MainActor
public final class TranslationService: Sendable {
    // MARK: - Properties

    private weak var delegate: TranslationProgressDelegate?
    private let translationActor: TranslationActor

    // Create an actor to safely handle translation
    private actor TranslationActor {
        private let session: SendableTranslationSession
        private let targetLanguage: Locale.Language
        private let isSimulator: Bool

        init(session: TranslationSession, targetLanguage: Locale.Language, isSimulator: Bool) {
            self.session = SendableTranslationSession(session: session)
            self.targetLanguage = targetLanguage
            self.isSimulator = isSimulator
        }

        func translate(_ frameSegments: [FrameSegments]) async throws -> [String: String] {
            if isSimulator {
                var translations: [String: String] = [:]
                for frame in frameSegments {
                    for segment in frame.segments {
                        translations[segment.text] = "[TR] \(segment.text)"
                    }
                }
                return translations
            }

            // Collect unique texts
            var uniqueTexts = Set<String>()
            for frame in frameSegments {
                for segment in frame.segments {
                    uniqueTexts.insert(segment.text)
                }
            }

            // Create requests
            let requests = uniqueTexts.map { text in
                TranslationSession.Request(sourceText: text, clientIdentifier: text)
            }

            // Translate
            let responses = try await session.translate(requests: requests)

            // Create translations dictionary
            var translations: [String: String] = [:]
            for response in responses {
                if let sourceText = response.clientIdentifier {
                    translations[sourceText] = response.targetText
                }
            }

            return translations
        }
    }

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
        // Create a local copy of session to avoid data races
        let sendableSession = SendableTranslationSession(session: session)
        translationActor = TranslationActor(
            session: sendableSession.session,
            targetLanguage: target,
            isSimulator: isSimulator
        )
        self.delegate = delegate
    }

    /// Translate a collection of frame segments
    /// - Parameters:
    ///   - frameSegments: Array of frame segments to translate
    /// - Returns: Dictionary mapping original text to translated text
    public nonisolated func translate(_ frameSegments: [FrameSegments]) async throws -> [String: String] {
        logger.info("Starting translation of \(frameSegments.count) frame segments")

        // Log input frame segments
        for frame in frameSegments {
            logger
                .debug(
                    "Input frame at \(frame.timestamp, format: .fixed(precision: 3)): \(frame.segments.count) segments"
                )
            for segment in frame.segments {
                logger
                    .debug(
                        "  - Text: '\(segment.text)' at (\(segment.position.origin.x), \(segment.position.origin.y))"
                    )
            }
        }

        do {
            let translations = try await translationActor.translate(frameSegments)
            logger.info("Translation complete - processed \(translations.count) translations")
            // Log output translations
            for (source, target) in translations {
                logger.debug("  - '\(source)' -> '\(target)'")
            }
            await delegate?.translationDidComplete()
            return translations
        } catch {
            logger.error("Translation failed with error: \(error.localizedDescription)")
            await delegate?.translationDidFail(with: error)
            throw error
        }
    }
}
