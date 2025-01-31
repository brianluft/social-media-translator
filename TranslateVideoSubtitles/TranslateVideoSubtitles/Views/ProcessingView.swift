import AVFoundation
import os
import PhotosUI
import SwiftUI
import Translation
import VideoSubtitlesLib

private let logger = Logger(subsystem: "TranslateVideoSubtitles", category: "ProcessingView")

struct ProcessingView: View {
    let videoItem: PhotosPickerItem
    let sourceLanguage: Locale.Language
    @StateObject private var viewModel: ProcessingViewModel
    @Environment(\.dismiss) private var dismiss

    init(videoItem: PhotosPickerItem, sourceLanguage: Locale.Language) {
        self.videoItem = videoItem
        self.sourceLanguage = sourceLanguage
        _viewModel = StateObject(wrappedValue: ProcessingViewModel(sourceLanguage: sourceLanguage))
    }

    var body: some View {
        ZStack {
            // Main content
            VStack(spacing: 30) {
                Spacer()

                ProgressView(value: viewModel.progress) {
                    Text(viewModel.currentStatus)
                        .font(.headline)
                }
                .progressViewStyle(.circular)
                .scaleEffect(2)
                .padding(.bottom, 30)

                Text(viewModel.detailedStatus)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                if viewModel.showError {
                    Text(viewModel.errorMessage)
                        .foregroundColor(.red)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .padding()
                }

                Spacer()

                Button(role: .destructive, action: {
                    viewModel.cancelProcessing()
                    dismiss()
                }) {
                    Text("Cancel")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
        .navigationBarBackButtonHidden()
        .navigationDestination(isPresented: $viewModel.processingComplete) {
            if let processedVideo = viewModel.processedVideo {
                PlayerView(video: processedVideo)
            }
        }
        // Attach translation task to the main view
        .translationTask(TranslationSession.Configuration(
            source: sourceLanguage,
            target: viewModel.destinationLanguage
        )) { session in
            Task { @MainActor in
                viewModel.translationSessionCreated(session)
                await viewModel.processVideo(videoItem)
            }
        }
    }
}

@MainActor
final class ProcessingViewModel: ObservableObject {
    @Published var progress: Double = 0
    @Published var currentStatus: String = "Processing Video"
    @Published var detailedStatus: String = "Loading video from library..."
    @Published var showError: Bool = false
    @Published var errorMessage: String = ""
    @Published var processingComplete: Bool = false
    @Published var processedVideo: ProcessedVideo?

    private var isCancelled = false
    private var detector: SubtitleDetector?
    private var translator: TranslationService?
    private var videoURL: URL?
    private let sourceLanguage: Locale.Language
    let destinationLanguage = Locale.current.language
    private var translationSession: TranslationSession?

    init(sourceLanguage: Locale.Language) {
        self.sourceLanguage = sourceLanguage
    }

    func translationSessionCreated(_ session: TranslationSession) {
        logger.info("Translation session created")
        translationSession = session
    }

    func processVideo(_ item: PhotosPickerItem) async {
        logger.info("Starting video processing")

        // Wait for translation session
        guard let translationSession else {
            logger.error("Translation session not available")
            showError = true
            errorMessage = "Translation service not initialized"
            return
        }

        do {
            // Load video from PhotosPickerItem
            guard let videoData = try await item.loadTransferable(type: Data.self) else {
                logger.error("Failed to load video data from PhotosPickerItem")
                throw NSError(
                    domain: "VideoProcessing",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to load video data"]
                )
            }

            logger.debug("Successfully loaded video data")

            // Save to temporary file
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
            try videoData.write(to: tempURL)
            videoURL = tempURL
            logger.debug("Saved video to temporary file: \(tempURL.lastPathComponent)")

            // Create AVAsset
            let asset = AVURLAsset(url: tempURL)
            logger.debug("Created AVAsset from video")

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

            logger.info("Initializing SubtitleDetector")
            detector = SubtitleDetector(
                videoAsset: asset,
                delegate: detectionDelegate,
                recognitionLanguages: [sourceLanguage.languageCode?.identifier ?? "en-US"]
            )

            logger.info("Initializing TranslationService")
            translator = TranslationService(
                session: translationSession,
                delegate: translationDelegate,
                target: destinationLanguage
            )

            // Detect subtitles
            detailedStatus = "Detecting subtitles..."
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                Task { @MainActor in
                    do {
                        if let detector {
                            logger.info("Starting subtitle detection")
                            try await withThrowingTaskGroup(of: Void.self) { group in
                                group.addTask {
                                    try await detector.detectText()
                                }
                                _ = try await group.next()
                            }
                            logger.info("Subtitle detection completed")
                            continuation.resume()
                        } else {
                            logger.error("Detector not initialized before detection")
                            continuation.resume(throwing: NSError(
                                domain: "VideoProcessing",
                                code: -1,
                                userInfo: [NSLocalizedDescriptionKey: "Detector not initialized"]
                            ))
                        }
                    } catch {
                        logger.error("Subtitle detection failed: \(error.localizedDescription)")
                        continuation.resume(throwing: error)
                    }
                }
            }

        } catch {
            logger.error("Video processing failed: \(error.localizedDescription)")
            showError = true
            errorMessage = error.localizedDescription
        }
    }

    func cancelProcessing() {
        isCancelled = true
    }

    // MARK: - Detection Delegate Handlers

    private func handleDetectionProgress(progress: Float) {
        self.progress = Double(progress) * 0.6 // 60% of total progress
    }

    private func handleDetectionComplete(frames: [FrameSegments]) {
        logger.info("Detection complete with \(frames.count) frames")
        Task { @MainActor in
            do {
                detailedStatus = "Translating subtitles..."
                if let translatedByFrame =
                    try await withCheckedThrowingContinuation({ (continuation: CheckedContinuation<
                        [UUID: [TranslatedSegment]]?,
                        Error
                    >) in
                        Task { @MainActor in
                            do {
                                if let translator {
                                    logger.info("Starting translation of detected frames")
                                    let result = try await withThrowingTaskGroup(
                                        of: [UUID: [TranslatedSegment]]?
                                            .self
                                    ) { group in
                                        group.addTask {
                                            try await translator.translate(frames)
                                        }
                                        return try await group.next() ?? nil
                                    }
                                    logger.info("Translation completed successfully")
                                    continuation.resume(returning: result)
                                } else {
                                    logger.error("Translation failed - translator not initialized")
                                    continuation.resume(returning: nil)
                                }
                            } catch {
                                logger.error("Translation failed with error: \(error.localizedDescription)")
                                continuation.resume(throwing: error)
                            }
                        }
                    }) {
                    let translatedSegments = Array(translatedByFrame.values.joined())
                    logger.info("Created \(translatedSegments.count) translated segments")

                    guard let videoURL else {
                        throw NSError(
                            domain: "VideoProcessing",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "Video URL not available"]
                        )
                    }

                    processedVideo = ProcessedVideo(
                        url: videoURL,
                        frameSegments: frames,
                        translatedSegments: translatedSegments
                    )
                    processingComplete = true
                }
            } catch {
                logger.error("Failed to process translation results: \(error.localizedDescription)")
                showError = true
                errorMessage = error.localizedDescription
            }
        }
    }

    private func handleDetectionFail(error: Error) {
        showError = true
        errorMessage = error.localizedDescription
    }

    // MARK: - Translation Delegate Handlers

    private func handleTranslationProgress(progress: Float) {
        self.progress = 0.6 + Double(progress) * 0.4 // Remaining 40% of progress
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

    func translationDidProgress(_ progress: Float) {
        progressHandler(progress)
    }

    func translationDidComplete() {
        completionHandler()
    }

    func translationDidFail(with error: Error) {
        failureHandler(error)
    }
}

#Preview {
    NavigationStack {
        ProcessingView(
            videoItem: PhotosPickerItem(itemIdentifier: "preview-identifier"),
            sourceLanguage: Locale.Language(identifier: "en")
        )
    }
}
