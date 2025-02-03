import AVFoundation
import Foundation
import os
import PhotosUI
import SwiftUI
import Translation
import VideoSubtitlesLib

/// A mechanical refactor of the old `processVideo(_ item:translationSession:)` function.
/// This class replicates that logic unmodified — no behavioral changes.
@MainActor
final class VideoProcessor {
    @Published var progress: Double = 0
    @Published var showError: Bool = false
    @Published var errorMessage: String = ""
    @Published var processingComplete: Bool = false

    var processedVideo: ProcessedVideo

    private var _isCancelled = false
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

    init(sourceLanguage: Locale.Language, processedVideo: ProcessedVideo) {
        self.sourceLanguage = sourceLanguage
        self.processedVideo = processedVideo
        // For consistency, we preserve the idea of the "current language" as the destination
        self.destinationLanguage = Locale.current.language
    }

    func processVideo(_ item: PhotosPickerItem, translationSession: TranslationSession) async {
        // Create a task we can wait on during cancellation
        cancellationTask = Task { @MainActor in
            do {
                // Check for cancellation before starting
                if await isCancelled {
                    return
                }

                // Load video from PhotosPickerItem
                guard let videoData = try await item.loadTransferable(type: Data.self) else {
                    throw NSError(
                        domain: "VideoProcessing",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to load video data"]
                    )
                }

                // Save to temporary file
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
                try videoData.write(to: tempURL)

                processedVideo.updateURL(tempURL)

                // Create AVAsset
                let asset = AVURLAsset(url: tempURL)

                // Initialize processing components with Sendable closures
                let detectionDelegate = DetectionDelegate(
                    progressHandler: { [weak self] progress in
                        Task { @MainActor [weak self] in
                            self?.handleDetectionProgress(progress: progress)
                        }
                    },
                    didComplete: { [weak self] frames in
                        Task { @MainActor [weak self] in
                            self?.handleDetectionComplete(frames: frames)
                        }
                    },
                    didFail: { [weak self] error in
                        Task { @MainActor [weak self] in
                            self?.handleDetectionFail(error: error)
                        }
                    }
                )

                let translationDelegate = TranslationDelegate(
                    progressHandler: { [weak self] progress in
                        Task { @MainActor [weak self] in
                            self?.handleTranslationProgress(progress: progress)
                        }
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

                detector = SubtitleDetector(
                    videoAsset: asset,
                    delegate: detectionDelegate,
                    recognitionLanguages: [sourceLanguage.languageCode?.identifier ?? "en-US"],
                    translationService: translator
                )

                // Detect subtitles
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    Task { @MainActor in
                        do {
                            if let detector {
                                try await withThrowingTaskGroup(of: Void.self) { group in
                                    group.addTask {
                                        let shouldContinue = await !(self.isCancelled)
                                        if shouldContinue {
                                            try await detector.detectText()
                                        }
                                    }
                                    _ = try await group.next()
                                }

                                let shouldComplete = await !(self.isCancelled)
                                if shouldComplete {
                                    continuation.resume()
                                } else {
                                    continuation.resume(throwing: CancellationError())
                                }
                            } else {
                                continuation.resume(throwing: NSError(
                                    domain: "VideoProcessing",
                                    code: -1,
                                    userInfo: [NSLocalizedDescriptionKey: "Detector not initialized"]
                                ))
                            }
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                }

            } catch {
                showError = true
                errorMessage = error.localizedDescription
            }
        }

        // Wait for the processing task to complete
        await cancellationTask?.value
    }

    func cancelProcessing() async {
        await MainActor.run { _isCancelled = true }

        // Cancel any ongoing detection
        detector?.cancelDetection()

        // Cancel any ongoing translation
        translator?.cancelTranslation()

        // Wait for any ongoing tasks to complete
        if let task = cancellationTask {
            await task.value
        }

        // Clean up temporary video file
        try? FileManager.default.removeItem(at: processedVideo.url)
    }

    // MARK: - Detection Delegate Handlers

    private func handleDetectionProgress(progress: Float) {
        self.progress = Double(progress) // Use full progress range for detection
    }

    private func handleDetectionComplete(frames: [FrameSegments]) {
        Task { @MainActor in
            processedVideo.appendFrameSegments(frames)
            processingComplete = true
        }
    }

    private func handleDetectionFail(error: Error) {
        showError = true
        errorMessage = error.localizedDescription
    }

    // MARK: - Translation Delegate Handlers

    private func handleTranslationProgress(progress: Float) {
        // Translation progress no longer affects the progress bar
    }

    private func handleTranslationComplete() {
        // Handled in detection complete when creating ProcessedVideo
    }

    private func handleTranslationFail(error: Error) {
        showError = true
        errorMessage = error.localizedDescription
    }
}

// MARK: - Delegate Wrappers

private final class DetectionDelegate: TextDetectionDelegate, @unchecked Sendable {
    private let progressHandler: @Sendable (Float) -> Void
    private let completionHandler: @Sendable ([FrameSegments]) -> Void
    private let failureHandler: @Sendable (Error) -> Void

    init(
        progressHandler: @escaping @Sendable (Float) -> Void,
        didComplete: @escaping @Sendable ([FrameSegments]) -> Void,
        didFail: @escaping @Sendable (Error) -> Void
    ) {
        self.progressHandler = progressHandler
        completionHandler = didComplete
        failureHandler = didFail
    }

    func detectionDidProgress(_ progress: Float) {
        progressHandler(progress)
    }

    func detectionDidComplete(frames: [FrameSegments]) {
        completionHandler(frames)
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
