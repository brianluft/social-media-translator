import Foundation
import os
import SwiftUI
import Translation

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
        private var isCancelled = false
        private var translationCache: [String: String] = [:]

        init(session: TranslationSession, targetLanguage: Locale.Language) {
            self.session = SendableTranslationSession(session: session)
            self.targetLanguage = targetLanguage
        }

        func cancel() {
            isCancelled = true
        }

        func translateText(_ text: String) async throws -> String {
            // Check cache first
            if let cached = translationCache[text] {
                return cached
            }

            // Check for cancellation
            if isCancelled {
                throw CancellationError()
            }

            // Create request
            let request = TranslationSession.Request(sourceText: text, clientIdentifier: text)

            #if targetEnvironment(simulator)
            // Mock translation in simulator by appending (TR)
            let translatedText = text + " (TR)"
            translationCache[text] = translatedText
            return translatedText
            #else
            // Translate
            let responses = try await session.translate(requests: [request])

            // Check for cancellation after translation
            if isCancelled {
                throw CancellationError()
            }

            guard let response = responses.first,
                  let translatedText = response.clientIdentifier.map({ _ in response.targetText })
            else {
                throw NSError(
                    domain: "TranslationService",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Translation failed"]
                )
            }

            // Cache the result
            translationCache[text] = translatedText
            return translatedText
            #endif
        }

        func translate(_ frameSegments: [FrameSegments]) async throws -> [String: String] {
            // Check for cancellation
            if isCancelled {
                throw CancellationError()
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

            #if targetEnvironment(simulator)
            // Mock translations in simulator by appending (TR)
            return uniqueTexts.reduce(into: [:]) { result, text in
                result[text] = text + " (TR)"
            }
            #else
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
            #endif
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
        // Create a local copy of session to avoid data races
        let sendableSession = SendableTranslationSession(session: session)
        translationActor = TranslationActor(
            session: sendableSession.session,
            targetLanguage: target
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
        // Reset cancellation state
        await MainActor.run {
            isCancelled = false
        }

        do {
            let translations = try await translationActor.translate(frameSegments)
            await delegate?.translationDidComplete()
            return translations
        } catch {
            await delegate?.translationDidFail(with: error)
            throw error
        }
    }

    /// Translate a single string
    /// - Parameter text: The string to translate
    /// - Returns: The translated string
    public func translateText(_ text: String) async throws -> String {
        try await translationActor.translateText(text)
    }
}
