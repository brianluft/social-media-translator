import AVFoundation
import Foundation
import PhotosUI

@MainActor
class VideoSelectionViewModel: ObservableObject {
    @Published var selectedVideo: AVAsset?
    @Published var isProcessing = false
    @Published var error: Error?

    func selectVideo() {
        // TODO: Implement PHPickerViewController presentation
    }

    func processVideo(_ asset: AVAsset) {
        // TODO: Implement video processing using VideoSubtitlesLib
    }
}
