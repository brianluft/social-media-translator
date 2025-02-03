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
                    VideoDownloaderView(
                        videoURL: $urlToDownload,
                        onDownloadComplete: { url in
                            downloadedVideoURL = url
                            navigateToPlayerView = true
                        }
                    )
                }
        }
    }

    private var mainContent: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "film")
                .font(.system(size: 60))
                .foregroundColor(.accentColor)

            Text("Translate Video Subtitles")
                .font(.title2)
                .bold()

            Text("Choose a video from your photo library to translate its subtitles")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

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
                    if let url = parseURLFromClipboard() {
                        print("[VideoSelection] Setting urlToDownload to: '\(url)'")
                        urlToDownload = url
                        print("[VideoSelection] urlToDownload is now: '\(urlToDownload)'")
                        print("[VideoSelection] Setting showDownloader to true")
                        showDownloader = true
                        print("[VideoSelection] showDownloader is now: \(showDownloader)")
                    }
                },
                label: {
                    HStack {
                        Image(systemName: "doc.on.clipboard")
                        Text("Paste social media link")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
            )
            .buttonStyle(.bordered)
            .padding(.horizontal)
            .disabled(!viewModel.canSelectVideo)
        }
    }

    private func parseURLFromClipboard() -> String? {
        print("[VideoSelection] Checking clipboard contents...")
        guard let clipboardString = UIPasteboard.general.string else {
            print("[VideoSelection] Clipboard is empty or doesn't contain text")
            return nil
        }
        print("[VideoSelection] Raw clipboard contents: '\(clipboardString)'")

        // Split by commas (both standard and Chinese)
        let components = clipboardString.components(separatedBy: [",", "，"])
        print("[VideoSelection] Split into \(components.count) components: \(components)")

        // Look for URLs in each component
        for (index, component) in components.enumerated() {
            print("[VideoSelection] Checking component \(index): '\(component)'")
            let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
            let matches = detector?.matches(
                in: component,
                options: [],
                range: NSRange(location: 0, length: component.utf16.count)
            )
            print("[VideoSelection] Found \(matches?.count ?? 0) URLs in component")

            if let firstMatch = matches?.first,
               let range = Range(firstMatch.range, in: component) {
                let urlString = String(component[range])
                print("[VideoSelection] Extracted URL string: '\(urlString)'")
                if let url = URL(string: urlString) {
                    print("[VideoSelection] Successfully validated URL: \(url.absoluteString)")
                    return url.absoluteString
                } else {
                    print("[VideoSelection] Failed to validate URL string")
                }
            }
        }

        print("[VideoSelection] No valid URLs found in clipboard")
        return nil
    }
}
