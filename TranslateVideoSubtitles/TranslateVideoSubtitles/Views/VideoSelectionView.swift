import PhotosUI
import SwiftUI
import VideoSubtitlesLib

struct VideoSelectionView: View {
    @StateObject private var viewModel = VideoSelectionViewModel()
    @State private var isShowingPhotoPicker = false
    @State private var navigateToProcessing = false
    @State private var selectedVideo: PHPickerResult?
    
    var body: some View {
        NavigationStack {
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
                
                Spacer()
                
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
                
                Spacer()
            }
            .navigationDestination(isPresented: $navigateToProcessing) {
                if let selectedVideo = selectedVideo {
                    ProcessingView(videoAsset: selectedVideo)
                }
            }
            .photosPicker(isPresented: $isShowingPhotoPicker,
                         selection: $viewModel.selectedItem,
                         matching: .videos)
            .onChange(of: viewModel.selectedItem) { newValue in
                if let newValue = newValue {
                    selectedVideo = newValue
                    navigateToProcessing = true
                }
            }
        }
    }
}

class VideoSelectionViewModel: ObservableObject {
    @Published var selectedItem: PHPickerResult?
}

#Preview {
    VideoSelectionView()
}
