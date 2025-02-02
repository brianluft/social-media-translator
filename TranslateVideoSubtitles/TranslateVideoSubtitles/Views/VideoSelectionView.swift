import os
import PhotosUI
import SwiftUI
import VideoSubtitlesLib

struct VideoSelectionView: View {
    @StateObject private var viewModel = VideoSelectionViewModel()
    @State private var isShowingPhotoPicker = false
    @State private var navigateToProcessing = false
    @State private var selectedItem: PhotosPickerItem?
    @State private var processedVideo: ProcessedVideo?

    var body: some View {
        NavigationStack {
            mainContent
                .navigationDestination(isPresented: $navigateToProcessing) {
                    if let selectedItem,
                       let sourceLanguage = viewModel.selectedSourceLanguage {
                        ProcessingView(
                            videoItem: selectedItem,
                            sourceLanguage: sourceLanguage,
                            processedVideo: ProcessedVideo(
                                targetLanguage: Locale.current.language.languageCode?.identifier ?? "en"
                            ),
                            onProcessingComplete: { video in
                                processedVideo = video
                                navigateToProcessing = false
                            }
                        )
                    }
                }
                .navigationDestination(item: $processedVideo) { video in
                    PlayerView(video: video)
                        .onDisappear {
                            // Reset state when returning from player
                            selectedItem = nil
                            processedVideo = nil
                        }
                }
                .photosPicker(
                    isPresented: $isShowingPhotoPicker,
                    selection: $selectedItem,
                    matching: .videos
                )
                .onChange(of: selectedItem) { _, newValue in
                    if newValue != nil {
                        // Always navigate to processing when a video is selected
                        processedVideo = nil
                        navigateToProcessing = true
                    }
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
    }
}
