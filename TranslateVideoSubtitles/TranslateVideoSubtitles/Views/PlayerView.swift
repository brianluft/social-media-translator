import AVKit
import SwiftUI
import VideoSubtitlesLib

struct PlayerView: View {
    let video: ProcessedVideo
    @StateObject private var viewModel: PlayerViewModel
    @Environment(\.dismiss) private var dismiss

    init(video: ProcessedVideo) {
        self.video = video
        _viewModel = StateObject(wrappedValue: PlayerViewModel(video: video))
    }

    var body: some View {
        GeometryReader { _ in
            ZStack {
                VideoPlayerView(player: viewModel.player)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Subtitle overlay
                viewModel.subtitleOverlay
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Playback controls overlay
                VStack {
                    Spacer()

                    // Progress slider and controls
                    VStack(spacing: 8) {
                        Slider(
                            value: $viewModel.currentTime,
                            in: 0 ... viewModel.duration,
                            onEditingChanged: viewModel.onSliderEditingChanged
                        )
                        .padding(.horizontal)

                        HStack {
                            Button(action: viewModel.togglePlayback) {
                                Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.title2)
                            }

                            Text(viewModel.timeString)
                                .font(.caption)
                                .monospacedDigit()

                            Spacer()
                        }
                        .padding(.horizontal)
                    }
                    .padding(.bottom)
                    .background {
                        Rectangle()
                            .fill(.black.opacity(0.4))
                            .blur(radius: 10)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }
}

// Custom AVPlayerView to support subtitle overlay
struct VideoPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        // Update if needed
    }
}

@MainActor
class PlayerViewModel: ObservableObject {
    private let videoPlayerController: VideoPlayerController
    private let subtitleRenderer: SubtitleOverlayRenderer
    private let video: ProcessedVideo
    private var currentSegments: [TranslatedSegment] = []

    @Published var currentTime: Double = 0
    @Published var isPlaying: Bool = false

    var player: AVPlayer { videoPlayerController.player }
    var duration: Double { player.currentItem?.duration.seconds ?? 0 }

    var timeString: String {
        let current = Int(currentTime)
        let total = Int(duration)
        return String(
            format: "%d:%02d / %d:%02d",
            current / 60,
            current % 60,
            total / 60,
            total % 60
        )
    }

    var subtitleOverlay: some View {
        subtitleRenderer.createSubtitleOverlay(for: currentSegments)
    }

    init(video: ProcessedVideo) {
        self.video = video
        videoPlayerController = VideoPlayerController(url: video.url)
        subtitleRenderer = SubtitleOverlayRenderer()
        videoPlayerController.delegate = self

        // Initial subtitle update
        updateSubtitles(at: 0)
    }

    func togglePlayback() {
        if isPlaying {
            videoPlayerController.pause()
        } else {
            videoPlayerController.play()
        }
    }

    func onSliderEditingChanged(_ isEditing: Bool) {
        if !isEditing {
            videoPlayerController.seek(to: currentTime)
            updateSubtitles(at: currentTime)
        }
    }

    private func updateSubtitles(at time: TimeInterval) {
        currentSegments = video.segments(at: time)
    }
}

extension PlayerViewModel: VideoPlayerControllerDelegate {
    nonisolated func playerController(_ controller: VideoPlayerController, didUpdateTime time: TimeInterval) {
        Task { @MainActor in
            currentTime = time
            updateSubtitles(at: time)
        }
    }

    nonisolated func playerController(_ controller: VideoPlayerController, didChangePlaybackState isPlaying: Bool) {
        Task { @MainActor in
            self.isPlaying = isPlaying
        }
    }
}
