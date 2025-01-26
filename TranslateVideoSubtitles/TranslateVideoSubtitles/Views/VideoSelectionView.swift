import PhotosUI
import SwiftUI

struct VideoSelectionView: View {
    @StateObject private var viewModel = VideoSelectionViewModel()

    var body: some View {
        NavigationView {
            VStack {
                Text("Select a video to translate its subtitles")
                    .font(.headline)
                    .padding()

                Spacer()

                // TODO: Add PHPickerViewController integration
                Button("Select Video") {
                    // TODO: Implement video selection
                }
                .buttonStyle(.borderedProminent)

                Spacer()
            }
            .navigationTitle("Video Subtitles Translator")
        }
    }
}
