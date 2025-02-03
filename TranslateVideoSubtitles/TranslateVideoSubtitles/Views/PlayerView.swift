import AVKit
import os
import PhotosUI
import SwiftUI
import Translation
import VideoSubtitlesLib

struct PlayerView: View {
    let videoItem: PhotosPickerItem
    let sourceLanguage: Locale.Language

    @StateObject private var viewModel: PlayerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var videoSize: CGSize = .zero

    init(videoItem: PhotosPickerItem, sourceLanguage: Locale.Language) {
        self.videoItem = videoItem
        self.sourceLanguage = sourceLanguage
        _viewModel = StateObject(
            wrappedValue: PlayerViewModel(sourceLanguage: sourceLanguage)
        )
    }

    var body: some View {
        GeometryReader { _ in
            ZStack {
                Color.black

                if viewModel.readyToPlay {
                    ZStack {
                        VideoPlayerView(player: viewModel.player, onVideoSizeChange: { @MainActor size in
                            videoSize = size
                        })
                        #if os(iOS)
                        .edgesIgnoringSafeArea(.all)
                        #endif
                        .onTapGesture {
                            viewModel.togglePlayback()
                        }

                        viewModel.subtitleOverlay

                        if !viewModel.isPlaying && viewModel.processingComplete {
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

                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        if !viewModel.readyToPlay || !viewModel.processingComplete {
                            ProgressView(value: viewModel.progress)
                                .progressViewStyle(CircularProgressViewStyle())
                                .padding()
                        }
                    }
                }
            }
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onDisappear {
            Task {
                await viewModel.cancelProcessing()
            }
            viewModel.pause()
        }
        .translationTask(
            TranslationSession.Configuration(
                source: sourceLanguage,
                target: viewModel.destinationLanguage
            ),
            action: { session in
                Task { @MainActor in
                    await viewModel.processVideo(videoItem, translationSession: session)
                }
            }
        )
    }
}

struct CircularProgressViewStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        Circle()
            .trim(from: 0.0, to: CGFloat(configuration.fractionCompleted ?? 0))
            .stroke(style: StrokeStyle(lineWidth: 4.0, lineCap: .round, lineJoin: .round))
            .foregroundColor(.blue)
            .rotationEffect(.degrees(-90))
            .frame(width: 40, height: 40)
            .animation(.linear, value: configuration.fractionCompleted)
            .background(
                Circle()
                    .stroke(lineWidth: 4.0)
                    .opacity(0.3)
                    .foregroundColor(.blue)
                    .frame(width: 40, height: 40)
            )
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

    private var processedVideo = ProcessedVideo(
        targetLanguage: Locale.current.language.languageCode?
            .identifier ?? "en"
    )

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
        self.videoProcessor = VideoProcessor(
            sourceLanguage: sourceLanguage,
            processedVideo: processedVideo
        )

        print("[PlayerViewModel] Initializing with empty VideoPlayerController")
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
            pause()
        } else {
            play()
        }
    }

    func processVideo(_ item: PhotosPickerItem, translationSession: TranslationSession) async {
        print("[PlayerViewModel] Starting video processing for ProcessedVideo \(processedVideo.id)")
        
        // Start a task to monitor readyToPlay state
        Task {
            for await ready in videoProcessor.$readyToPlay.values {
                if ready && !hasSetVideo {
                    print("[PlayerViewModel] Ready to play, setting video URL for ProcessedVideo \(processedVideo.id)")
                    if let url = processedVideo.currentURL as URL?, url.isFileURL {
                        print("[PlayerViewModel] Setting video URL: \(url.path)")
                        print("[PlayerViewModel] URL exists?: \(FileManager.default.fileExists(atPath: url.path))")
                        videoPlayerController.setVideo(url: url)
                        hasSetVideo = true
                    }
                }
            }
        }
        
        await videoProcessor.processVideo(item, translationSession: translationSession)
    }

    func cancelProcessing() async {
        print("[PlayerViewModel] Cancelling processing for ProcessedVideo \(processedVideo.id)")
        await videoProcessor.cancelProcessing()
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
