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

                // Playback controls overlay
                VStack {
                    Spacer()

                    // Progress slider
                    VStack(spacing: 4) {
                        Slider(
                            value: $viewModel.currentTime,
                            in: 0 ... viewModel.duration,
                            onEditingChanged: viewModel.onSliderEditingChanged
                        )
                        .padding(.horizontal)
                    }
                    .padding(.bottom, 8)
                    .background {
                        Rectangle()
                            .fill(.black.opacity(0.6))
                            .blur(radius: 8)
                            .allowsHitTesting(false)
                    }
                }
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
    private let logger = Logger(subsystem: "TranslateVideoSubtitles", category: "PlayerViewModel")
    private var observedPlayerItem: AVPlayerItem? // Store reference to observed item
    @Published private(set) var duration: Double = 1.0 // Default to 1.0 to avoid slider issues

    @Published var currentTime: Double = 0
    @Published var isPlaying: Bool = false

    var player: AVPlayer { videoPlayerController.player }

    var timeString: String {
        let current = Int(currentTime)
        let total = Int(duration)
        return String(
            format: "%d:%02d / %d:%02d",
            current / 60, current % 60,
            total / 60, total % 60
        )
    }

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

        // Observe player item status
        if let playerItem = player.currentItem {
            observedPlayerItem = playerItem
            playerItem.addObserver(
                self,
                forKeyPath: #keyPath(AVPlayerItem.status),
                options: [.new, .initial],
                context: nil
            )
        }
    }

    deinit {
        // Remove observer when view model is deallocated
        observedPlayerItem?.removeObserver(self, forKeyPath: #keyPath(AVPlayerItem.status))
    }

    override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        if keyPath == #keyPath(AVPlayerItem.status),
           let item = object as? AVPlayerItem {
            if item.status == .readyToPlay {
                let newDuration = item.duration.seconds
                logger.debug("Player item ready - duration: \(newDuration) seconds")
                if !newDuration.isNaN && newDuration > 0 {
                    duration = newDuration
                }
            }
        }
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

    func onSliderEditingChanged(_ isEditing: Bool) {
        if !isEditing {
            videoPlayerController.seek(to: currentTime)
            updateSubtitles(at: currentTime)
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
