import AVFoundation
import PhotosUI
import SwiftUI
import Translation
import VideoSubtitlesLib

struct ProcessingView: View {
    let videoItem: PhotosPickerItem
    @StateObject private var viewModel = ProcessingViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
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
        .navigationBarBackButtonHidden()
        .navigationDestination(isPresented: $viewModel.processingComplete) {
            if let processedVideo = viewModel.processedVideo {
                PlayerView(video: processedVideo)
            }
        }
        .task {
            await viewModel.processVideo(videoItem)
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
    private var translationHostView: some View {
        Color.clear // Minimal view to host translation session
    }

    private var frameSegments: [FrameSegments] = []

    func processVideo(_ item: PhotosPickerItem) async {
        do {
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

            detector = SubtitleDetector(videoAsset: asset, delegate: detectionDelegate)
            translator = TranslationService(hostView: translationHostView, delegate: translationDelegate)
            translator?.startSession(target: .init(languageCode: .english))

            // Detect subtitles
            detailedStatus = "Detecting subtitles..."
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                Task { @MainActor in
                    do {
                        if let detector {
                            try await withThrowingTaskGroup(of: Void.self) { group in
                                group.addTask {
                                    try await detector.detectText()
                                }
                                _ = try await group.next()
                            }
                            continuation.resume()
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

    func cancelProcessing() {
        isCancelled = true
    }

    // MARK: - Detection Delegate Handlers

    private func handleDetectionProgress(progress: Float) {
        self.progress = Double(progress) * 0.6 // 60% of total progress
    }

    private func handleDetectionComplete(frames: [FrameSegments]) {
        frameSegments = frames
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
                                    let result = try await withThrowingTaskGroup(
                                        of: [UUID: [TranslatedSegment]]?
                                            .self
                                    ) { group in
                                        group.addTask {
                                            try await translator.translate(frames)
                                        }
                                        return try await group.next() ?? nil
                                    }
                                    continuation.resume(returning: result)
                                } else {
                                    continuation.resume(returning: nil)
                                }
                            } catch {
                                continuation.resume(throwing: error)
                            }
                        }
                    }) {
                    let translatedSegments = Array(translatedByFrame.values.joined())
                    processedVideo = ProcessedVideo(
                        url: processedVideo?.url ?? URL(fileURLWithPath: ""),
                        frameSegments: frames,
                        translatedSegments: translatedSegments
                    )
                    processingComplete = true
                }
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
        ProcessingView(videoItem: PhotosPickerItem(itemIdentifier: "preview-identifier"))
    }
}
