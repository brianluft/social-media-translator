import AVKit
import os
import SwiftUI
import VideoSubtitlesLib

struct PlayerView: View {
    let video: ProcessedVideo
    @StateObject private var viewModel: PlayerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var videoSize: CGSize = .zero

    init(video: ProcessedVideo) {
        self.video = video
        _viewModel = StateObject(wrappedValue: PlayerViewModel(video: video))
    }

    var body: some View {
        GeometryReader { _ in
            ZStack {
                Color.black

                ZStack {
                    // Video player with tap/click gesture
                    VideoPlayerView(player: viewModel.player, onVideoSizeChange: { @MainActor size in
                        videoSize = size
                    })
                    #if os(iOS)
                    .edgesIgnoringSafeArea(.all)
                    #endif
                    .onTapGesture {
                        viewModel.togglePlayback()
                    }

                    // Subtitle overlay
                    viewModel.subtitleOverlay

                    // Play button overlay when paused
                    if !viewModel.isPlaying {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 72))
                            .foregroundColor(.white.opacity(0.8))
                            .onTapGesture {
                                viewModel.togglePlayback()
                            }
                    }
                }
                .aspectRatio(videoSize.width > 0 ? videoSize.width / videoSize.height : nil, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onDisappear {
            viewModel.pause()
        }
    }
}

// Custom AVPlayerView to support subtitle overlay
#if os(iOS)
struct VideoPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer
    let onVideoSizeChange: @MainActor (CGSize) -> Void

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false

        // Observe when the player item becomes ready
        if let playerItem = player.currentItem {
            context.coordinator.observe(playerItem)
        }

        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        // Update if needed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onVideoSizeChange: onVideoSizeChange)
    }

    class Coordinator: NSObject {
        let onVideoSizeChange: @MainActor (CGSize) -> Void
        private var observation: NSKeyValueObservation?

        init(onVideoSizeChange: @escaping @MainActor (CGSize) -> Void) {
            self.onVideoSizeChange = onVideoSizeChange
            super.init()
        }

        func observe(_ playerItem: AVPlayerItem) {
            observation = playerItem.observe(\.status, options: [.new]) { [weak self] playerItem, _ in
                guard playerItem.status == .readyToPlay else { return }

                // Get video track dimensions
                Task {
                    if let tracks = try? await playerItem.asset.loadTracks(withMediaType: .video),
                       let track = tracks.first {
                        let size = try? await track.load(.naturalSize)
                        let transform = try? await track.load(.preferredTransform)

                        if let size {
                            // Apply transform to get correct orientation
                            let videoSize = transform.map { size.applying($0) } ?? size
                            // Use absolute values since transform can make dimensions negative
                            await self?.onVideoSizeChange(CGSize(
                                width: abs(videoSize.width),
                                height: abs(videoSize.height)
                            ))
                        }
                    }
                }
            }
        }
    }
}

#elseif os(macOS)
struct VideoPlayerView: NSViewRepresentable {
    let player: AVPlayer
    let onVideoSizeChange: @MainActor (CGSize) -> Void

    class Coordinator: NSObject {
        let parent: VideoPlayerView
        private var observation: NSKeyValueObservation?

        init(_ parent: VideoPlayerView) {
            self.parent = parent
            super.init()
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

        func observe(_ playerItem: AVPlayerItem) {
            observation = playerItem.observe(\.status, options: [.new]) { [weak self] playerItem, _ in
                guard let self,
                      playerItem.status == .readyToPlay else { return }

                // Get video track dimensions
                Task {
                    if let tracks = try? await playerItem.asset.loadTracks(withMediaType: .video),
                       let track = tracks.first {
                        let size = try? await track.load(.naturalSize)
                        let transform = try? await track.load(.preferredTransform)

                        if let size {
                            // Apply transform to get correct orientation
                            let videoSize = transform.map { size.applying($0) } ?? size
                            // Use absolute values since transform can make dimensions negative
                            await self.parent.onVideoSizeChange(CGSize(
                                width: abs(videoSize.width),
                                height: abs(videoSize.height)
                            ))
                        }
                    }
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

        // Observe when the player item becomes ready
        if let playerItem = player.currentItem {
            context.coordinator.observe(playerItem)
        }

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
