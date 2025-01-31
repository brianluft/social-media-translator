import PhotosUI
import SwiftUI
import VideoSubtitlesLib

struct VideoSelectionView: View {
    @StateObject private var viewModel = VideoSelectionViewModel()
    @State private var isShowingPhotoPicker = false
    @State private var navigateToProcessing = false
    @State private var selectedItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            mainContent
                .navigationDestination(isPresented: $navigateToProcessing) {
                    if let selectedItem,
                       let sourceLanguage = viewModel.selectedSourceLanguage {
                        ProcessingView(
                            videoItem: selectedItem,
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
            Picker("Source Language", selection: $viewModel.selectedSourceLanguage) {
                ForEach(viewModel.supportedSourceLanguages, id: \.self) { language in
                    if let languageCode = language.languageCode?.identifier,
                       let localizedName = Locale.current.localizedString(forLanguageCode: languageCode) {
                        Text(localizedName)
                            .tag(Optional(language))
                    }
                }
            }
            .pickerStyle(.menu)
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
        Button(action: {
            isShowingPhotoPicker = true
        }) {
            HStack {
                Image(systemName: "photo.on.rectangle")
                Text("Choose from Photo Library")
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
        .buttonStyle(.borderedProminent)
        .padding(.horizontal)
        .disabled(!viewModel.canSelectVideo)
    }
}

#Preview {
    VideoSelectionView()
}
