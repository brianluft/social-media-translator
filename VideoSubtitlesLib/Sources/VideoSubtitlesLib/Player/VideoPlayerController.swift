import AVKit
import Foundation

public protocol VideoPlayerControllerDelegate: AnyObject {
    func playerController(_ controller: VideoPlayerController, didUpdateTime time: TimeInterval)
    func playerController(_ controller: VideoPlayerController, didChangePlaybackState isPlaying: Bool)
}

@MainActor
public class VideoPlayerController: NSObject {
    private final class TimeObserverToken: @unchecked Sendable {
        let token: Any

        init(_ token: Any) {
            self.token = token
        }
    }

    public private(set) var player: AVPlayer
    private var timeObserver: TimeObserverToken?
    private var timeControlObserver: NSKeyValueObservation?
    public weak var delegate: VideoPlayerControllerDelegate?

    public var isPlaying: Bool {
        player.timeControlStatus == .playing
    }

    override public init() {
        // Initialize with an empty player
        self.player = AVPlayer()
        super.init()
        setupTimeObserver()
        setupTimeControlObserver()
    }

    public func setVideo(url: URL) {
        let playerItem = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: playerItem)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemDidReachEnd),
            name: .AVPlayerItemDidPlayToEndTime,
            object: playerItem
        )

        // Re-establish timeControlObserver since we created a new player
        timeControlObserver?.invalidate()
        setupTimeControlObserver()
    }

    public nonisolated func cleanup() {
        Task { @MainActor in
            // Stop playback
            player.pause()

            // Remove the current item
            player.replaceCurrentItem(with: nil)

            // Remove observers
            if let observer = timeObserver {
                player.removeTimeObserver(observer.token)
                timeObserver = nil
            }
            timeControlObserver?.invalidate()
            timeControlObserver = nil
        }
    }

    deinit {
        // Remove notification center observer in deinit
        NotificationCenter.default.removeObserver(self)
        cleanup()
    }

    private func setupTimeObserver() {
        let interval = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        let token = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let seconds = CMTimeGetSeconds(time)
                self.delegate?.playerController(self, didUpdateTime: seconds)
            }
        }
        timeObserver = TimeObserverToken(token)
    }

    private func setupTimeControlObserver() {
        timeControlObserver = player.observe(\.timeControlStatus) { [weak self] player, _ in
            guard let self else { return }
            Task { @MainActor in
                self.delegate?.playerController(self, didChangePlaybackState: player.timeControlStatus == .playing)
            }
        }
    }

    @objc private func playerItemDidReachEnd() {
        delegate?.playerController(self, didChangePlaybackState: false)
    }

    // MARK: - Playback Controls

    public func play() {
        player.play()
    }

    public func pause() {
        player.pause()
    }

    public func seek(to time: TimeInterval) {
        let cmTime = CMTime(seconds: time, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        // Use exact seeking for better precision
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }
}
