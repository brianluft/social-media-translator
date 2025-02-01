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
public final class TranslationService {
    // MARK: - Properties

    private weak var delegate: TranslationProgressDelegate?
    private let translationActor: TranslationActor
    private var isCancelled = false

    // Create an actor to safely handle translation
    private actor TranslationActor {
        private let session: SendableTranslationSession
        private let targetLanguage: Locale.Language
        private let isSimulator: Bool
        private var isCancelled = false

        init(session: TranslationSession, targetLanguage: Locale.Language, isSimulator: Bool) {
            self.session = SendableTranslationSession(session: session)
            self.targetLanguage = targetLanguage
            self.isSimulator = isSimulator
        }

        func cancel() {
            isCancelled = true
        }

        func translate(_ frameSegments: [FrameSegments]) async throws -> [String: String] {
            // Check for cancellation
            if isCancelled {
                throw CancellationError()
            }

            if isSimulator {
                var translations: [String: String] = [:]
                for frame in frameSegments {
                    // Check for cancellation during simulation
                    if isCancelled {
                        throw CancellationError()
                    }
                    for segment in frame.segments {
                        translations[segment.text] = "[TR] \(segment.text)"
                    }
                }
                return translations
            }

            // Collect unique texts
            var uniqueTexts = Set<String>()
            for frame in frameSegments {
                // Check for cancellation during text collection
                if isCancelled {
                    throw CancellationError()
                }
                for segment in frame.segments {
                    uniqueTexts.insert(segment.text)
                }
            }

            // Create requests
            let requests = uniqueTexts.map { text in
                TranslationSession.Request(sourceText: text, clientIdentifier: text)
            }

            // Check for cancellation before translation
            if isCancelled {
                throw CancellationError()
            }

            // Translate
            let responses = try await session.translate(requests: requests)

            // Check for cancellation after translation
            if isCancelled {
                throw CancellationError()
            }

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

    // MARK: - Public Methods

    /// Cancels any ongoing translation
    public func cancelTranslation() {
        isCancelled = true
        Task {
            await translationActor.cancel()
        }
    }

    /// Translate a collection of frame segments
    /// - Parameters:
    ///   - frameSegments: Array of frame segments to translate
    /// - Returns: Dictionary mapping original text to translated text
    public nonisolated func translate(_ frameSegments: [FrameSegments]) async throws -> [String: String] {
        logger.info("Starting translation of \(frameSegments.count) frame segments")

        // Reset cancellation state
        await MainActor.run {
            isCancelled = false
        }

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
            await delegate?.translationDidComplete()
            return translations
        } catch {
            logger.error("Translation failed with error: \(error.localizedDescription)")
            await delegate?.translationDidFail(with: error)
            throw error
        }
    }
}
