import AVKit
import os
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
                // Video player with tap/click gesture
                VideoPlayerView(player: viewModel.player)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                #if os(iOS)
                    .edgesIgnoringSafeArea(.all)
                    .onTapGesture {
                        viewModel.togglePlayback()
                    }
                #endif

                // Subtitle overlay
                viewModel.subtitleOverlay
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") {
                    dismiss()
                }
            }
            #else
            ToolbarItem(placement: .automatic) {
                Button("Done") {
                    dismiss()
                }
            }
            #endif
        }
        .onAppear {
            viewModel.play()
        }
        .onDisappear {
            viewModel.pause()
        }
    }
}

// Custom AVPlayerView to support subtitle overlay
#if os(iOS)
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

#elseif os(macOS)
struct VideoPlayerView: NSViewRepresentable {
    let player: AVPlayer

    class Coordinator: NSObject {
        let parent: VideoPlayerView

        init(_ parent: VideoPlayerView) {
            self.parent = parent
        }

        @objc func handleClick(_ gesture: NSClickGestureRecognizer) {
            if gesture.view is AVPlayerView {
                if parent.player.timeControlStatus == .playing {
                    parent.player.pause()
                } else {
                    parent.player.play()
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> AVPlayerView {
        let playerView = AVPlayerView()
        playerView.player = player
        playerView.controlsStyle = .none

        // Add click gesture recognizer
        let clickGesture = NSClickGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleClick(_:))
        )
        playerView.addGestureRecognizer(clickGesture)

        return playerView
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        // Update if needed
    }
}
#endif

@MainActor
class PlayerViewModel: NSObject, ObservableObject {
    private let videoPlayerController: VideoPlayerController
    private let subtitleRenderer: SubtitleOverlayRenderer
    private let video: ProcessedVideo
    private var currentSegments: [(segment: TextSegment, text: String)] = []
    let logger = Logger(subsystem: "TranslateVideoSubtitles", category: "PlayerViewModel")
    private var observedPlayerItem: AVPlayerItem?
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var isPlaying: Bool = false

    var player: AVPlayer { videoPlayerController.player }

    var subtitleOverlay: some View {
        subtitleRenderer.createSubtitleOverlay(for: currentSegments)
    }

    init(video: ProcessedVideo) {
        self.video = video
        videoPlayerController = VideoPlayerController(url: video.url)
        subtitleRenderer = SubtitleOverlayRenderer()
        super.init()

        videoPlayerController.delegate = self
        logger.debug("PlayerViewModel initialized with video URL: \(video.url.lastPathComponent)")

        // Initial subtitle update
        updateSubtitles(at: 0)

        // Configure player for looping
        player.actionAtItemEnd = .none
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemDidReachEnd),
            name: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func playerItemDidReachEnd() {
        // Seek back to start and continue playing
        player.seek(to: .zero)
        player.play()
    }

    func play() {
        videoPlayerController.play()
    }

    func pause() {
        videoPlayerController.pause()
    }

    func togglePlayback() {
        if isPlaying {
            videoPlayerController.pause()
        } else {
            videoPlayerController.play()
        }
    }

    private func updateSubtitles(at time: TimeInterval) {
        let segmentsWithTranslations = video.segments(at: time)
        currentSegments = segmentsWithTranslations.compactMap { segment, translation in
            guard let translation else { return nil }
            return (segment: segment, text: translation)
        }
    }
}

extension PlayerViewModel: VideoPlayerControllerDelegate {
    nonisolated func playerController(_ controller: VideoPlayerController, didUpdateTime time: TimeInterval) {
        Task { @MainActor in
            logger.debug("⏱️ Player time updated to \(time)")
            currentTime = time
            updateSubtitles(at: time)
        }
    }

    nonisolated func playerController(_ controller: VideoPlayerController, didChangePlaybackState isPlaying: Bool) {
        Task { @MainActor in
            logger.debug("▶️ Playback state changed to \(isPlaying ? "playing" : "paused")")
            self.isPlaying = isPlaying
        }
    }
}
