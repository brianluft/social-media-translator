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

    public let player: AVPlayer
    private var timeObserver: TimeObserverToken?
    private var statusObserver: NSKeyValueObservation?
    public weak var delegate: VideoPlayerControllerDelegate?

    public var isPlaying: Bool {
        player.timeControlStatus == .playing
    }

    override public init() {
        fatalError("Use init(url:)")
    }

    public init(url: URL) {
        print("VideoPlayerController initializing with URL: \(url.absoluteString)")
        let playerItem = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)

        super.init()

        setupTimeObserver()

        // Add block-based KVO for player item status
        statusObserver = playerItem.observe(\.status, options: [.new, .initial]) { item, _ in
            switch item.status {
            case .failed:
                print("Player item failed: \(String(describing: item.error))")
            case .readyToPlay:
                print("Player item ready to play")
            case .unknown:
                print("Player item status unknown")
            @unknown default:
                break
            }
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemDidReachEnd),
            name: .AVPlayerItemDidPlayToEndTime,
            object: playerItem
        )
    }

    deinit {
        if let observer = timeObserver {
            player.removeTimeObserver(observer.token)
        }
        statusObserver?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    private func setupTimeObserver() {
        let interval = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        let token = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let seconds = CMTimeGetSeconds(time)
                print("⏱️ VideoPlayerController time observer: \(seconds)")
                self.delegate?.playerController(self, didUpdateTime: seconds)
            }
        }
        timeObserver = TimeObserverToken(token)
    }

    @objc private func playerItemDidReachEnd() {
        print("🔚 VideoPlayerController reached end")
        delegate?.playerController(self, didChangePlaybackState: false)
    }

    // MARK: - Playback Controls

    public func play() {
        print("▶️ VideoPlayerController play")
        player.play()
        delegate?.playerController(self, didChangePlaybackState: true)
    }

    public func pause() {
        print("⏸️ VideoPlayerController pause")
        player.pause()
        delegate?.playerController(self, didChangePlaybackState: false)
    }

    public func seek(to time: TimeInterval) {
        print("⏩ VideoPlayerController seeking to \(time)")
        let cmTime = CMTime(seconds: time, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        // Use exact seeking for better precision
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }
}
