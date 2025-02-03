import AVFoundation
import os
import PhotosUI
import SwiftUI
import Translation
import VideoSubtitlesLib

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
    let processedVideo: ProcessedVideo
    let onProcessingComplete: (ProcessedVideo) -> Void
    @StateObject private var viewModel: ProcessingViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isCancelling = false

    init(
        videoItem: PhotosPickerItem,
        sourceLanguage: Locale.Language,
        processedVideo: ProcessedVideo,
        onProcessingComplete: @escaping (ProcessedVideo) -> Void
    ) {
        self.videoItem = videoItem
        self.sourceLanguage = sourceLanguage
        self.processedVideo = processedVideo
        self.onProcessingComplete = onProcessingComplete
        _viewModel = StateObject(wrappedValue: ProcessingViewModel(
            sourceLanguage: sourceLanguage,
            processedVideo: processedVideo
        ))
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
            if isComplete {
                onProcessingComplete(viewModel.processedVideo)
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
                    await viewModel.videoProcessor.processVideo(videoItem, translationSession: session)
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
    var processedVideo: ProcessedVideo

    let sourceLanguage: Locale.Language
    let destinationLanguage = Locale.current.language

    let videoProcessor: VideoProcessor

    init(sourceLanguage: Locale.Language, processedVideo: ProcessedVideo) {
        self.sourceLanguage = sourceLanguage
        self.processedVideo = processedVideo

        self.videoProcessor = VideoProcessor(
            sourceLanguage: sourceLanguage,
            processedVideo: processedVideo
        )

        videoProcessor.$progress.assign(to: &$progress)
        videoProcessor.$showError.assign(to: &$showError)
        videoProcessor.$errorMessage.assign(to: &$errorMessage)
        videoProcessor.$processingComplete.assign(to: &$processingComplete)
    }

    func cancelProcessing() async {
        await videoProcessor.cancelProcessing()
    }
}
