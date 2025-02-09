import AVFoundation
import CoreImage
import Foundation
import Translation

/// Handles processing of photos to detect and translate text
@MainActor
final class PhotoProcessor {
    // MARK: - Instance Properties

    /// Whether an error occurred during processing
    @Published var showError: Bool = false
    /// Error message if an error occurred
    @Published var errorMessage: String = ""
    /// Whether processing is complete
    @Published var processingComplete: Bool = false
    /// Whether the photo is ready to display
    @Published var readyToDisplay: Bool = false

    /// The processed photo containing detected and translated text
    let processedPhoto: ProcessedMedia

    private var _isCancelled = false
    /// Whether processing has been cancelled
    var isCancelled: Bool {
        get async {
            await MainActor.run { _isCancelled }
        }
    }

    private var detector: SubtitleDetector?
    private var translator: TranslationService?
    private var cancellationTask: Task<Void, Never>?

    private let sourceLanguage: Locale.Language
    private let destinationLanguage: Locale.Language

    /// Creates a new photo processor
    /// - Parameters:
    ///   - sourceLanguage: The language of text in the photo
    ///   - processedPhoto: The model to store processed results in
    init(sourceLanguage: Locale.Language, processedPhoto: ProcessedMedia) {
        self.sourceLanguage = sourceLanguage
        self.processedPhoto = processedPhoto
        // For consistency, we preserve the idea of the "current language" as the destination
        self.destinationLanguage = Locale.current.language
    }

    /// Processes an image to detect and translate text
    /// - Parameters:
    ///   - cgImage: The image to process
    ///   - size: The size of the image in points
    ///   - translationSession: The session to use for translation
    func processImage(_ cgImage: CGImage, size: CGSize, translationSession: TranslationSession) async {
        cancellationTask = Task { @MainActor in
            do {
                // Check for cancellation before starting
                if await isCancelled {
                    return
                }

                // Update photo size
                processedPhoto.updateVideo(
                    url: URL(fileURLWithPath: ""), // Photos don't need a URL
                    size: size
                )

                // Initialize translation service
                let translationDelegate = TranslationDelegate(
                    progressHandler: { _ in
                        // No progress needed for photos
                    },
                    didComplete: { [weak self] in
                        Task { @MainActor [weak self] in
                            self?.handleTranslationComplete()
                        }
                    },
                    didFail: { [weak self] error in
                        Task { @MainActor [weak self] in
                            self?.handleTranslationFail(error: error)
                        }
                    }
                )

                translator = TranslationService(
                    session: translationSession,
                    delegate: translationDelegate,
                    target: destinationLanguage
                )

                // Initialize detector
                let detectionDelegate = DetectionDelegate(
                    progressHandler: { _ in
                        // No progress needed for photos
                    },
                    frameHandler: { [weak self] frame in
                        Task { @MainActor [weak self] in
                            self?.handleDetectionFrame(frame)
                        }
                    },
                    didComplete: { [weak self] in
                        Task { @MainActor [weak self] in
                            self?.handleDetectionComplete()
                        }
                    },
                    didFail: { [weak self] error in
                        Task { @MainActor [weak self] in
                            self?.handleDetectionFail(error: error)
                        }
                    }
                )

                // Create a dummy AVAsset for the photo
                let dummyAsset = AVURLAsset(url: URL(fileURLWithPath: ""))

                detector = SubtitleDetector(
                    videoAsset: dummyAsset,
                    delegate: detectionDelegate,
                    recognitionLanguages: [sourceLanguage.languageCode?.identifier ?? "en-US"],
                    translationService: translator
                )

                // Process the single image
                let frameSegments = try await detector?.detectText(in: cgImage, at: .zero)
                if let frameSegments {
                    detectionDelegate.detectionDidReceiveFrame(frameSegments)
                }
                detectionDelegate.detectionDidComplete()

            } catch {
                showError = true
                errorMessage = error.localizedDescription
            }
        }

        // Wait for the processing task to complete
        await cancellationTask?.value
    }

    /// Cancels any ongoing processing
    func cancelProcessing() async {
        await MainActor.run { _isCancelled = true }
        detector?.cancelDetection()
        translator?.cancelTranslation()
        if let task = cancellationTask {
            await task.value
        }
    }

    // MARK: - Detection Delegate Handlers

    private func handleDetectionComplete() {
        processingComplete = true
        readyToDisplay = true
    }

    private func handleDetectionFail(error: Error) {
        showError = true
        errorMessage = error.localizedDescription
    }

    private func handleDetectionFrame(_ frame: FrameSegments) {
        processedPhoto.appendFrameSegments([frame])
        readyToDisplay = true
    }

    // MARK: - Translation Delegate Handlers

    private func handleTranslationComplete() {
        // Translation is handled in detection complete
    }

    private func handleTranslationFail(error: Error) {
        showError = true
        errorMessage = error.localizedDescription
    }
}

// MARK: - Delegate Wrappers

private final class DetectionDelegate: TextDetectionDelegate, @unchecked Sendable {
    private let progressHandler: @Sendable (Float) -> Void
    private let frameHandler: @Sendable (FrameSegments) -> Void
    private let completionHandler: @Sendable () -> Void
    private let failureHandler: @Sendable (Error) -> Void

    init(
        progressHandler: @escaping @Sendable (Float) -> Void,
        frameHandler: @escaping @Sendable (FrameSegments) -> Void,
        didComplete: @escaping @Sendable () -> Void,
        didFail: @escaping @Sendable (Error) -> Void
    ) {
        self.progressHandler = progressHandler
        self.frameHandler = frameHandler
        completionHandler = didComplete
        failureHandler = didFail
    }

    func detectionDidProgress(_ progress: Float) {
        progressHandler(progress)
    }

    func detectionDidReceiveFrame(_ frame: FrameSegments) {
        frameHandler(frame)
    }

    func detectionDidComplete() {
        completionHandler()
    }

    func detectionDidFail(with error: Error) {
        failureHandler(error)
    }
}

private final class TranslationDelegate: TranslationProgressDelegate, @unchecked Sendable {
    private let progressHandler: @Sendable (Float) -> Void
    private let completionHandler: @Sendable () -> Void
    private let failureHandler: @Sendable (Error) -> Void

    init(
        progressHandler: @escaping @Sendable (Float) -> Void,
        didComplete: @escaping @Sendable () -> Void,
        didFail: @escaping @Sendable (Error) -> Void
    ) {
        self.progressHandler = progressHandler
        completionHandler = didComplete
        failureHandler = didFail
    }

    func translationDidProgress(_ progress: Float) async {
        progressHandler(progress)
    }

    func translationDidComplete() async {
        completionHandler()
    }

    func translationDidFail(with error: Error) async {
        failureHandler(error)
    }
}
