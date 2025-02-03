import SwiftUI

struct VideoDownloaderView: View {
    @Binding var videoURL: String
    let onDownloadComplete: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var downloadProgress: DownloadProgress = .indeterminate
    @State private var error: VideoDownloadError?
    @State private var showError = false
    @State private var tempVideoURL: URL?
    @State private var hasStartedDownload = false

    private let downloader = VideoDownloader()
    @State private var downloaderDelegate: DownloaderDelegate?

    var body: some View {
        VStack {
            Text("Downloading Video")
                .font(.title2)
                .bold()
                .padding(.top)
                .onAppear {
                    print("[VideoDownloaderView] View appeared with URL: '\(videoURL)'")
                }

            Spacer()

            Group {
                switch downloadProgress {
                case .indeterminate:
                    ProgressView()
                        .controlSize(.large)
                case let .progress(value):
                    ProgressView(value: value) {
                        Text("\(Int(value * 100))%")
                            .font(.caption)
                    }
                    .progressViewStyle(CircularProgressViewStyle())
                    .controlSize(.large)
                }
            }
            .frame(width: 100, height: 100)

            Spacer()

            Button(role: .destructive) {
                downloader.cancelDownload()
                dismiss()
            } label: {
                Text("Cancel")
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.bordered)
            .padding(.horizontal)
            .padding(.bottom)
        }
        .alert("Download Failed", isPresented: $showError, presenting: error) { _ in
            Button("OK") {
                dismiss()
            }
        } message: { error in
            Text(error.localizedDescription)
        }
        .task {
            print("[VideoDownloaderView] Task started, URL: '\(videoURL)'")
            if !hasStartedDownload && !videoURL.isEmpty {
                hasStartedDownload = true
                downloaderDelegate = DownloaderDelegate(view: self)
                downloader.delegate = downloaderDelegate
                print("[VideoDownloaderView] Starting download...")
                await downloader.startDownload(from: videoURL)
            }
        }
        .onDisappear {
            print("[VideoDownloaderView] View disappeared")
            downloader.cancelDownload()
        }
    }

    private class DownloaderDelegate: VideoDownloaderDelegate {
        private var view: VideoDownloaderView

        init(view: VideoDownloaderView) {
            print("[DownloaderDelegate] Initializing with view")
            self.view = view
        }

        func downloadProgressUpdated(_ progress: DownloadProgress) {
            print("[DownloaderDelegate] Progress update received: \(progress)")
            Task { @MainActor in
                print("[DownloaderDelegate] Updating view progress")
                view.downloadProgress = progress
                print("[DownloaderDelegate] View progress updated")
            }
        }

        func downloadCompleted(tempURL: URL) {
            print("[DownloaderDelegate] Download completed with URL: \(tempURL.path)")
            Task { @MainActor in
                print("[DownloaderDelegate] Calling completion handler")
                view.tempVideoURL = tempURL
                view.onDownloadComplete(tempURL)
                print("[DownloaderDelegate] Dismissing view")
                view.dismiss()
            }
        }

        func downloadFailed(_ error: VideoDownloadError) {
            print("[DownloaderDelegate] Download failed with error: \(error)")
            Task { @MainActor in
                print("[DownloaderDelegate] Updating view with error")
                view.error = error
                view.showError = true
            }
        }
    }
}

extension VideoDownloadError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The provided URL is invalid"
        case .noVideoFound:
            return "No video found at the specified URL"
        case let .downloadFailed(message):
            return "Download failed: \(message)"
        case .cancelled:
            return "Download was cancelled"
        case let .networkError(message):
            return message
        }
    }
}
