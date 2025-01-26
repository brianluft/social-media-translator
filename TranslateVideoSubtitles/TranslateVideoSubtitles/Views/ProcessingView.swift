import PhotosUI
import SwiftUI
import VideoSubtitlesLib

struct ProcessingView: View {
    let videoAsset: PHPickerResult
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
            await viewModel.processVideo(videoAsset)
        }
    }
}

@MainActor
class ProcessingViewModel: ObservableObject {
    @Published var progress: Double = 0
    @Published var currentStatus: String = "Processing Video"
    @Published var detailedStatus: String = "Loading video from library..."
    @Published var showError: Bool = false
    @Published var errorMessage: String = ""
    @Published var processingComplete: Bool = false
    @Published var processedVideo: ProcessedVideo?

    private var isCancelled = false

    func processVideo(_ asset: PHPickerResult) async {
        // TODO: Implement video processing using VideoSubtitlesLib
        // This is a placeholder for now
        for i in 0 ... 100 {
            if isCancelled { return }
            try? await Task.sleep(nanoseconds: 50_000_000)
            progress = Double(i) / 100.0

            if i < 30 {
                detailedStatus = "Detecting subtitles..."
            } else if i < 60 {
                detailedStatus = "Extracting text..."
            } else if i < 90 {
                detailedStatus = "Translating subtitles..."
            } else {
                detailedStatus = "Finalizing..."
            }
        }

        processingComplete = true
        // TODO: Set processedVideo with actual processed video
    }

    func cancelProcessing() {
        isCancelled = true
    }
}

struct ProcessedVideo {
    // TODO: Add properties for processed video
}

#Preview {
    NavigationStack {
        ProcessingView(videoAsset: PHPickerResult())
    }
}
