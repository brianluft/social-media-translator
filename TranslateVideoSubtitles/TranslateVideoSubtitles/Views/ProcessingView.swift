import AVFoundation
import os
import PhotosUI
import SwiftUI
import Translation
import VideoSubtitlesLib

private let logger = Logger(subsystem: "com.brianluft.TranslateVideoSubtitles", category: "ProcessingView")

struct CircularProgressViewStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        Circle()
            .trim(from: 0.0, to: CGFloat(configuration.fractionCompleted ?? 0))
            .stroke(style: StrokeStyle(lineWidth: 4.0, lineCap: .round, lineJoin: .round))
            .foregroundColor(.blue)
            .rotationEffect(.degrees(-90))
            .frame(width: 60, height: 60)
            .animation(.linear, value: configuration.fractionCompleted)
            .background(
                Circle()
                    .stroke(lineWidth: 4.0)
                    .opacity(0.3)
                    .foregroundColor(.blue)
                    .frame(width: 60, height: 60)
            )
    }
}

struct ProcessingView: View {
    let videoItem: PhotosPickerItem
    let sourceLanguage: Locale.Language
    let onProcessingComplete: (ProcessedVideo) -> Void
    @StateObject private var viewModel: ProcessingViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isCancelling = false

    init(
        videoItem: PhotosPickerItem,
        sourceLanguage: Locale.Language,
        onProcessingComplete: @escaping (ProcessedVideo) -> Void
    ) {
        self.videoItem = videoItem
        self.sourceLanguage = sourceLanguage
        self.onProcessingComplete = onProcessingComplete
        _viewModel = StateObject(wrappedValue: ProcessingViewModel(sourceLanguage: sourceLanguage))
    }

    var body: some View {
        ZStack {
            // Main content
            VStack(spacing: 30) {
                Spacer()

                Text("Processing Video")
                    .font(.title)

                ProgressView(value: viewModel.progress)
                    .progressViewStyle(CircularProgressViewStyle())

                if viewModel.showError {
                    Text(viewModel.errorMessage)
                        .foregroundColor(.red)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .padding()
                }

                Spacer()

                Button(
                    role: .destructive,
                    action: {
                        Task {
                            isCancelling = true
                            await viewModel.cancelProcessing()
                            dismiss()
                        }
                    },
                    label: {
                        Text(isCancelling ? "Cancelling..." : "Cancel")
                            .frame(maxWidth: .infinity)
                    }
                )
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .padding(.horizontal)
                .padding(.bottom)
                .disabled(isCancelling)
            }
        }
        .navigationBarBackButtonHidden()
        .onChange(of: viewModel.processingComplete) { _, isComplete in
            if isComplete, let video = viewModel.processedVideo {
                onProcessingComplete(video)
            }
        }
        // Attach translation task to the main view
        .translationTask(
            TranslationSession.Configuration(
                source: sourceLanguage,
                target: viewModel.destinationLanguage
            ),
            action: { session in
                Task { @MainActor in
                    await viewModel.processVideo(videoItem, translationSession: session)
                }
            }
        )
    }
}

@MainActor
final class ProcessingViewModel: ObservableObject {
    @Published var progress: Double = 0
    @Published var showError: Bool = false
    @Published var errorMessage: String = ""
    @Published var processingComplete: Bool = false
    @Published var processedVideo: ProcessedVideo?

    private var _isCancelled = false
    var isCancelled: Bool {
        get async {
            await MainActor.run { _isCancelled }
        }
    }

    private var detector: SubtitleDetector?
    private var translator: TranslationService?
    private var videoURL: URL?
    private var cancellationTask: Task<Void, Never>?
    private let sourceLanguage: Locale.Language
    let destinationLanguage = Locale.current.language

    init(sourceLanguage: Locale.Language) {
        self.sourceLanguage = sourceLanguage
    }

    func processVideo(_ item: PhotosPickerItem, translationSession: TranslationSession) async {
        // Create a task we can wait on during cancellation
        cancellationTask = Task { @MainActor in
            logger.info("Starting video processing")

            do {
                // Check for cancellation before starting
                if await isCancelled {
                    logger.info("Processing cancelled before starting")
                    return
                }

                // Load video from PhotosPickerItem
                guard let videoData = try await item.loadTransferable(type: Data.self) else {
                    logger.error("Failed to load video data from PhotosPickerItem")
                    throw NSError(
                        domain: "VideoProcessing",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to load video data"]
                    )
                }

                // Save to temporary file
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
                try videoData.write(to: tempURL)
                videoURL = tempURL

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

                logger.info("Initializing TranslationService")
                translator = TranslationService(
                    session: translationSession,
                    delegate: translationDelegate,
                    target: destinationLanguage
                )

                logger.info("Initializing SubtitleDetector")
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
                                logger.info("Starting subtitle detection")
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
                                    logger.info("Subtitle detection completed")
                                    continuation.resume()
                                } else {
                                    logger.info("Subtitle detection cancelled")
                                    continuation.resume(throwing: CancellationError())
                                }
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
        if let videoURL {
            try? FileManager.default.removeItem(at: videoURL)
        }
    }

    // MARK: - Detection Delegate Handlers

    private func handleDetectionProgress(progress: Float) {
        self.progress = Double(progress) // Use full progress range for detection
    }

    private func handleDetectionComplete(frames: [FrameSegments]) {
        logger.info("Detection complete with \(frames.count) frames")
        Task { @MainActor in
            do {
                guard let videoURL else {
                    logger.error("Video URL not available")
                    throw NSError(
                        domain: "VideoProcessing",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Video URL not available"]
                    )
                }

                // Create translations dictionary from the already-translated segments
                var translations: [String: String] = [:]
                for frame in frames {
                    for segment in frame.segments {
                        if let translatedText = segment.translatedText {
                            translations[segment.text] = translatedText
                        }
                    }
                }

                processedVideo = ProcessedVideo(
                    url: videoURL,
                    frameSegments: frames,
                    translations: translations,
                    targetLanguage: destinationLanguage.languageCode?.identifier ?? "unknown"
                )
                processingComplete = true
            } catch {
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

#Preview {
    NavigationStack {
        ProcessingView(
            videoItem: PhotosPickerItem(itemIdentifier: "preview-identifier"),
            sourceLanguage: Locale.Language(identifier: "en"),
            onProcessingComplete: { _ in }
        )
    }
}
