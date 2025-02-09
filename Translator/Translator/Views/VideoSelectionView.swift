import os
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct VideoSelectionView: View {
    enum TranslationMode {
        case text
        case audio
    }

    @StateObject private var viewModel = VideoSelectionViewModel()
    @State private var translationMode: TranslationMode = .text
    @State private var isShowingMediaPicker = false
    @State private var navigateToMediaView = false
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
                .navigationDestination(isPresented: $navigateToMediaView) {
                    if let selectedItem,
                       let sourceLanguage = viewModel.selectedSourceLanguage {
                        Group {
                            switch selectedItem.supportedContentTypes.first {
                            case .some(UTType.movie), .some(UTType.video), .some(UTType.quickTimeMovie),
                                 .some(UTType.mpeg4Movie):
                                PlayerView(
                                    videoItem: selectedItem,
                                    sourceLanguage: sourceLanguage
                                )
                            case .some(UTType.image), .some(UTType.jpeg), .some(UTType.png), .some(UTType.heic):
                                PhotoView(
                                    photoItem: selectedItem,
                                    sourceLanguage: sourceLanguage
                                )
                            default:
                                Text("Unsupported media type")
                            }
                        }
                    } else if let downloadedVideoURL,
                              let sourceLanguage = viewModel.selectedSourceLanguage {
                        PlayerView(
                            videoURL: downloadedVideoURL,
                            sourceLanguage: sourceLanguage
                        )
                    }
                }
                .photosPicker(
                    isPresented: $isShowingMediaPicker,
                    selection: $selectedItem,
                    matching: PHPickerFilter.any(of: [.videos, .images])
                )
                .onChange(of: selectedItem) { _, newValue in
                    if let newValue {
                        print("Selected media types: \(newValue.supportedContentTypes)")
                        navigateToMediaView = true
                    }
                }
                .sheet(isPresented: $showDownloader) {
                    WebVideoDownloaderView(videoURL: $urlToDownload) { url in
                        downloadedVideoURL = url
                        navigateToMediaView = true
                    }
                }
        }
    }

    private var mainContent: some View {
        GeometryReader { geometry in
            let isPortrait = geometry.size.width < geometry.size.height
            ZStack {
                // Background image
                Image("Background")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .edgesIgnoringSafeArea(.all)
                    .frame(minWidth: geometry.size.width, minHeight: geometry.size.height)

                VStack {
                    if isPortrait {
                        Spacer() // In portrait, push to bottom
                    }

                    VStack(spacing: isPortrait ? 24 : 12) {
                        languageSelectionContent
                        selectVideoButton
                    }
                    .padding(24)
                    .padding(.horizontal, 16)
                    .background(Color(.systemGray6))
                    .cornerRadius(24)
                    .frame(maxWidth: 375)

                    if isPortrait {
                        Spacer()
                            .frame(height: 48) // Fixed bottom margin for portrait
                    }
                }
                .frame(maxHeight: isPortrait ? nil : .infinity) // Center vertically in landscape
            }
        }
    }

    @ViewBuilder
    private var languageSelectionContent: some View {
        if viewModel.isLoading {
            ProgressView()
                .padding()
        } else if !viewModel.supportedSourceLanguages.isEmpty {
            VStack(spacing: 8) {
                Text("Original Language")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Picker("", selection: $viewModel.selectedSourceLanguage) {
                    ForEach(viewModel.supportedSourceLanguages, id: \.self) { language in
                        Text(viewModel.displayName(for: language))
                            .tag(Optional(language))
                    }
                }
                .accentColor(.primary)
                .buttonStyle(.bordered)
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity)

                Text("What to Translate")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 16)
                
                Picker("Translation Mode", selection: $translationMode) {
                    Text("Text").tag(TranslationMode.text)
                    Text("Audio").tag(TranslationMode.audio)
                }
                .pickerStyle(.segmented)
            }
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
                    isShowingMediaPicker = true
                },
                label: {
                    HStack(spacing: 8) {
                        Image(systemName: "photo.on.rectangle")
                        Text("Choose from Photo Library")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            )
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)
            .disabled(!viewModel.canSelectVideo)
            .frame(height: 48)

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
                    HStack(spacing: 8) {
                        Image(systemName: "doc.on.clipboard")
                        Text("Paste Video Link")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            )
            .foregroundStyle(.primary)
            .buttonStyle(.bordered)
            .padding(.horizontal)
            .disabled(!viewModel.canSelectVideo)
            .frame(height: 48)
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
