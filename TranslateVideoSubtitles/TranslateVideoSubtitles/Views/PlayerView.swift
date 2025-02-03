import AVKit
import os
import PhotosUI
import SwiftUI
import Translation
import VideoSubtitlesLib

struct PlayerView: View {
    private let videoSource: VideoSource
    let sourceLanguage: Locale.Language

    @StateObject private var viewModel: PlayerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var videoSize: CGSize = .zero

    init(videoItem: PhotosPickerItem, sourceLanguage: Locale.Language) {
        self.videoSource = .photosItem(videoItem)
        self.sourceLanguage = sourceLanguage
        _viewModel = StateObject(
            wrappedValue: PlayerViewModel(sourceLanguage: sourceLanguage)
        )
    }

    init(videoURL: URL, sourceLanguage: Locale.Language) {
        self.videoSource = .url(videoURL)
        self.sourceLanguage = sourceLanguage
        _viewModel = StateObject(
            wrappedValue: PlayerViewModel(sourceLanguage: sourceLanguage)
        )
    }

    private enum VideoSource {
        case photosItem(PhotosPickerItem)
        case url(URL)
    }

    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)

            if !viewModel.readyToPlay {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(1.5)
                    .tint(.white)
            } else {
                GeometryReader { geometry in
                    let size = calculateVideoFrame(
                        videoSize: viewModel.processedVideo.naturalSize ?? videoSize,
                        containerSize: geometry.size
                    )

                    // Container exactly matching video frame
                    ZStack {
                        ZStack(alignment: .topLeading) {
                            VideoPlayerView(player: viewModel.player, onVideoSizeChange: { @MainActor size in
                                videoSize = size
                            })
                            .frame(width: size.width, height: size.height)
                            .onTapGesture {
                                viewModel.togglePlayback()
                            }

                            GeometryReader { _ in
                                viewModel.subtitleOverlay
                                    .frame(width: size.width, height: size.height)
                            }
                        }
                        .frame(width: size.width, height: size.height)
                    }
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                }
            }

            // Play button overlay
            if viewModel.readyToPlay && !viewModel.isPlaying {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 72))
                    .foregroundColor(.white.opacity(0.8))
                    .onTapGesture {
                        viewModel.togglePlayback()
                    }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if !viewModel.readyToPlay || !viewModel.processingComplete {
                    ProgressView(value: viewModel.progress)
                        .progressViewStyle(CircularProgressViewStyle())
                }
            }
        }
        .onDisappear {
            Task {
                await viewModel.cancelProcessing()
            }
            viewModel.pause()
            viewModel.cleanup()
        }
        .translationTask(
            TranslationSession.Configuration(
                source: sourceLanguage,
                target: viewModel.destinationLanguage
            ),
            action: { session in
                Task { @MainActor in
                    switch videoSource {
                    case let .photosItem(item):
                        await viewModel.processVideo(item, translationSession: session)
                    case let .url(url):
                        await viewModel.processVideo(url, translationSession: session)
                    }
                }
            }
        )
    }

    private func calculateVideoFrame(videoSize: CGSize, containerSize: CGSize) -> CGSize {
        guard videoSize.width > 0 && videoSize.height > 0 else {
            return containerSize
        }

        let videoAspectRatio = videoSize.width / videoSize.height
        let screenAspectRatio = containerSize.width / containerSize.height

        if videoAspectRatio > screenAspectRatio {
            // Video is wider than screen - fit to width
            return CGSize(
                width: containerSize.width,
                height: containerSize.width / videoAspectRatio
            )
        } else {
            // Video is taller than screen - fit to height
            return CGSize(
                width: containerSize.height * videoAspectRatio,
                height: containerSize.height
            )
        }
    }
}

struct VideoPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer
    let onVideoSizeChange: @MainActor (CGSize) -> Void

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false

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

                Task {
                    if let tracks = try? await playerItem.asset.loadTracks(withMediaType: .video),
                       let track = tracks.first {
                        let size = try? await track.load(.naturalSize)
                        let transform = try? await track.load(.preferredTransform)

                        if let size {
                            let videoSize = transform.map { size.applying($0) } ?? size
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

@MainActor
class PlayerViewModel: NSObject, ObservableObject, VideoPlayerControllerDelegate {
    @Published var progress: Double = 0
    @Published var showError: Bool = false
    @Published var errorMessage: String = ""
    @Published var processingComplete: Bool = false
    @Published private(set) var readyToPlay: Bool = false
    private var hasSetVideo: Bool = false

    let sourceLanguage: Locale.Language
    let destinationLanguage = Locale.current.language

    let processedVideo: ProcessedVideo

    let videoProcessor: VideoProcessor

    private let videoPlayerController: VideoPlayerController
    private let subtitleRenderer: SubtitleOverlayRenderer

    @Published private(set) var currentTime: Double = 0
    @Published private(set) var isPlaying: Bool = false

    var player: AVPlayer { videoPlayerController.player }

    var subtitleOverlay: some View {
        subtitleRenderer.createSubtitleOverlay(
            for: processedVideo.segments(at: currentTime).compactMap { pair in
                guard let txt = pair.translation else { return nil }
                return (segment: pair.segment, text: txt)
            }
        )
    }

    init(sourceLanguage: Locale.Language) {
        self.sourceLanguage = sourceLanguage
        self.processedVideo = ProcessedVideo(
            targetLanguage: Locale.current.language.languageCode?
                .identifier ?? "en"
        )
        self.videoProcessor = VideoProcessor(
            sourceLanguage: sourceLanguage,
            processedVideo: processedVideo
        )

        videoPlayerController = VideoPlayerController()
        subtitleRenderer = SubtitleOverlayRenderer()

        super.init()

        videoPlayerController.delegate = self

        videoProcessor.$progress.assign(to: &$progress)
        videoProcessor.$showError.assign(to: &$showError)
        videoProcessor.$errorMessage.assign(to: &$errorMessage)
        videoProcessor.$processingComplete.assign(to: &$processingComplete)
        videoProcessor.$readyToPlay.assign(to: &$readyToPlay)

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
        player.seek(to: .zero)
        play()
    }

    func play() {
        videoPlayerController.play()
    }

    func pause() {
        videoPlayerController.pause()
    }

    func togglePlayback() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func processVideo(_ item: PhotosPickerItem, translationSession: TranslationSession) async {
        // Start a task to monitor readyToPlay state
        Task {
            for await ready in videoProcessor.$readyToPlay.values {
                if ready && !hasSetVideo {
                    if let url = processedVideo.currentURL as URL?, url.isFileURL {
                        videoPlayerController.setVideo(url: url)
                        hasSetVideo = true
                        play() // Auto-play when video is ready
                    }
                }
            }
        }

        await videoProcessor.processVideo(item, translationSession: translationSession)
    }

    func processVideo(_ url: URL, translationSession: TranslationSession) async {
        // Start a task to monitor readyToPlay state
        Task {
            for await ready in videoProcessor.$readyToPlay.values {
                if ready && !hasSetVideo {
                    if let url = processedVideo.currentURL as URL?, url.isFileURL {
                        videoPlayerController.setVideo(url: url)
                        hasSetVideo = true
                        play() // Auto-play when video is ready
                    }
                }
            }
        }

        await videoProcessor.processVideo(url, translationSession: translationSession)
    }

    func cancelProcessing() async {
        await videoProcessor.cancelProcessing()
    }

    nonisolated func cleanup() {
        videoPlayerController.cleanup()
    }

    nonisolated func playerController(_ controller: VideoPlayerController, didUpdateTime time: TimeInterval) {
        Task { @MainActor in
            self.currentTime = time
        }
    }

    nonisolated func playerController(_ controller: VideoPlayerController, didChangePlaybackState isPlaying: Bool) {
        Task { @MainActor in
            self.isPlaying = isPlaying
        }
    }
}
