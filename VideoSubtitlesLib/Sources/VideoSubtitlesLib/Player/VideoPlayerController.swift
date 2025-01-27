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

        // Add KVO for player item status
        playerItem.addObserver(
            self,
            forKeyPath: #keyPath(AVPlayerItem.status),
            options: [.new, .initial],
            context: nil
        )

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
        NotificationCenter.default.removeObserver(self)
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

    @objc private func playerItemDidReachEnd() {
        delegate?.playerController(self, didChangePlaybackState: false)
    }

    // MARK: - Playback Controls

    public func play() {
        player.play()
        delegate?.playerController(self, didChangePlaybackState: true)
    }

    public func pause() {
        player.pause()
        delegate?.playerController(self, didChangePlaybackState: false)
    }

    public func seek(to time: TimeInterval) {
        let cmTime = CMTime(seconds: time, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player.seek(to: cmTime)
    }

    override public func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        if keyPath == #keyPath(AVPlayerItem.status),
           let item = object as? AVPlayerItem {
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
    }
}
