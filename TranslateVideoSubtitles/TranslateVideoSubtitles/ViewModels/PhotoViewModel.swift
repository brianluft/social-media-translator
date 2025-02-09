import Foundation
import PhotosUI
import SwiftUI
import Translation

@MainActor
class PhotoViewModel: ObservableObject {
    @Published var readyToDisplay: Bool = false
    @Published var showError: Bool = false
    @Published var errorMessage: String = ""
    @Published var processingComplete: Bool = false
    @Published var image: UIImage?

    let sourceLanguage: Locale.Language
    let destinationLanguage = Locale.current.language
    let processedPhoto: ProcessedMedia
    private let photoProcessor: PhotoProcessor
    private let subtitleRenderer: PhotoSubtitleOverlayRenderer

    var subtitleOverlay: some View {
        subtitleRenderer.createSubtitleOverlay(
            for: processedPhoto.segments(at: 0).compactMap { pair in
                guard let txt = pair.translation else { return nil }
                return (segment: pair.segment, text: txt)
            }
        )
    }

    init(sourceLanguage: Locale.Language) {
        self.sourceLanguage = sourceLanguage
        self.processedPhoto = ProcessedMedia(
            targetLanguage: Locale.current.language.languageCode?
                .identifier ?? "en"
        )
        self.photoProcessor = PhotoProcessor(
            sourceLanguage: sourceLanguage,
            processedPhoto: processedPhoto
        )
        self.subtitleRenderer = PhotoSubtitleOverlayRenderer()

        // Bind processor state to view model
        photoProcessor.$showError.assign(to: &$showError)
        photoProcessor.$errorMessage.assign(to: &$errorMessage)
        photoProcessor.$processingComplete.assign(to: &$processingComplete)
        photoProcessor.$readyToDisplay.assign(to: &$readyToDisplay)
    }

    func processPhoto(_ item: PhotosPickerItem, translationSession: TranslationSession) async {
        do {
            // Load photo from PhotosPickerItem
            guard let imageData = try await item.loadTransferable(type: Data.self),
                  let uiImage = UIImage(data: imageData) else {
                throw NSError(
                    domain: "PhotoProcessing",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to load photo data"]
                )
            }

            // Store the image for display
            self.image = uiImage

            // Create CGImage for processing
            guard let cgImage = uiImage.cgImage else {
                throw NSError(
                    domain: "PhotoProcessing",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to create CGImage"]
                )
            }

            // Process the image
            await photoProcessor.processImage(
                cgImage,
                size: CGSize(width: uiImage.size.width, height: uiImage.size.height),
                translationSession: translationSession
            )

        } catch {
            showError = true
            errorMessage = error.localizedDescription
        }
    }

    func cancelProcessing() async {
        await photoProcessor.cancelProcessing()
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
