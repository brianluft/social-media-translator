import os
import PhotosUI
import SwiftUI
import VideoSubtitlesLib

struct VideoSelectionView: View {
    @StateObject private var viewModel = VideoSelectionViewModel()
    @State private var isShowingPhotoPicker = false
    @State private var navigateToPlayerView = false
    @State private var selectedItem: PhotosPickerItem?
    @State private var showDownloader = false
    @State private var urlToDownload: String = ""
    @State private var downloadedVideoURL: URL?
    @State private var showPasteError = false
    @State private var pasteErrorMessage = ""

    private enum URLError: Error {
        case emptyClipboard
        case noValidURL
        case unsupportedDomain(String)

        var message: String {
            switch self {
            case .emptyClipboard:
                return "No text found in clipboard. Please copy a video URL and try again."
            case .noValidURL:
                return "No valid URL found in clipboard. Please copy a video URL and try again."
            case let .unsupportedDomain(domain):
                return "\(domain) is not supported. Try saving the video to your Photo Library."
            }
        }
    }

    var body: some View {
        NavigationStack {
            mainContent
                .navigationDestination(isPresented: $navigateToPlayerView) {
                    if let selectedItem,
                       let sourceLanguage = viewModel.selectedSourceLanguage {
                        PlayerView(
                            videoItem: selectedItem,
                            sourceLanguage: sourceLanguage
                        )
                    } else if let downloadedVideoURL,
                              let sourceLanguage = viewModel.selectedSourceLanguage {
                        PlayerView(
                            videoURL: downloadedVideoURL,
                            sourceLanguage: sourceLanguage
                        )
                    }
                }
                .photosPicker(
                    isPresented: $isShowingPhotoPicker,
                    selection: $selectedItem,
                    matching: .videos
                )
                .onChange(of: selectedItem) { _, newValue in
                    if newValue != nil {
                        navigateToPlayerView = true
                    }
                }
                .sheet(isPresented: $showDownloader) {
                    WebVideoDownloaderView(videoURL: $urlToDownload) { url in
                        downloadedVideoURL = url
                        navigateToPlayerView = true
                    }
                }
        }
    }

    private var mainContent: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "film")
                .font(.system(size: 60))
                .foregroundColor(.primary)

            Text("Translate Video Subtitles")
                .font(.title2)
                .bold()

            languageSelectionContent

            Spacer()

            selectVideoButton

            Spacer()
        }
    }

    @ViewBuilder
    private var languageSelectionContent: some View {
        if viewModel.isLoading {
            ProgressView()
                .padding()
        } else if !viewModel.supportedSourceLanguages.isEmpty {
            VStack(spacing: 8) {
                Text("Source Language")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Picker("", selection: $viewModel.selectedSourceLanguage) {
                    ForEach(viewModel.supportedSourceLanguages, id: \.self) { language in
                        Text(viewModel.displayName(for: language))
                            .tag(Optional(language))
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity)
            }
            .padding()
        } else if let error = viewModel.error {
            Text(error)
                .foregroundColor(.red)
                .padding()
        } else {
            Text("No supported languages found")
                .foregroundColor(.red)
                .padding()
        }
    }

    private var selectVideoButton: some View {
        VStack(spacing: 12) {
            Button(
                action: {
                    downloadedVideoURL = nil
                    urlToDownload = ""
                    selectedItem = nil
                    isShowingPhotoPicker = true
                },
                label: {
                    HStack {
                        Image(systemName: "photo.on.rectangle")
                        Text("Choose from Photo Library")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
            )
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)
            .disabled(!viewModel.canSelectVideo)

            Button(
                action: {
                    selectedItem = nil
                    switch parseURLFromClipboard() {
                    case let .success(url):
                        urlToDownload = url
                        showDownloader = true
                    case let .failure(error):
                        pasteErrorMessage = error.message
                        showPasteError = true
                    }
                },
                label: {
                    HStack {
                        Image(systemName: "doc.on.clipboard")
                        Text("Paste Link")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
            )
            .buttonStyle(.borderless)
            .padding(.horizontal)
            .disabled(!viewModel.canSelectVideo)
            .alert("Paste Error", isPresented: $showPasteError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(pasteErrorMessage)
            }
        }
    }

    private func parseURLFromClipboard() -> Result<String, URLError> {
        guard let clipboardString = UIPasteboard.general.string else {
            return .failure(.emptyClipboard)
        }

        // Split by commas (both standard and Chinese)
        let components = clipboardString.components(separatedBy: [",", "，"])

        let unsupportedDomains = ["tiktok.com", "instagram.com", "facebook.com", "youtube.com", "x.com"]

        // Look for URLs in each component
        for component in components {
            let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
            let matches = detector?.matches(
                in: component,
                options: [],
                range: NSRange(location: 0, length: component.utf16.count)
            )

            if let firstMatch = matches?.first,
               let range = Range(firstMatch.range, in: component) {
                let urlString = String(component[range])
                if let url = URL(string: urlString) {
                    // Check for unsupported domains
                    if let host = url.host?.lowercased(),
                       let unsupportedDomain = unsupportedDomains.first(where: { host.contains($0) }) {
                        return .failure(.unsupportedDomain(unsupportedDomain))
                    }

                    return .success(url.absoluteString)
                }
            }
        }

        return .failure(.noValidURL)
    }
}
