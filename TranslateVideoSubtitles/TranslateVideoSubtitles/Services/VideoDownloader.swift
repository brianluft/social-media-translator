import Foundation

enum VideoDownloadError: Error {
    case invalidURL
    case noVideoFound
    case downloadFailed(String)
    case cancelled
    case networkError(String)
}

enum DownloadProgress {
    case indeterminate
    case progress(Double) // 0.0 to 1.0
}

protocol VideoDownloaderDelegate: AnyObject {
    func downloadProgressUpdated(_ progress: DownloadProgress)
    func downloadCompleted(tempURL: URL)
    func downloadFailed(_ error: VideoDownloadError)
}

class VideoDownloader {
    // Use the same temporary directory as VideoProcessor
    static var temporaryVideoDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("VideoSubtitles", isDirectory: true)
    }

    weak var delegate: VideoDownloaderDelegate?
    private var isDownloading = false
    private var downloadTask: URLSessionDownloadTask?
    private let session: URLSession
    private let progressDelegate: ProgressDelegate
    var currentDestinationURL: URL?

    init() {
        print("[VideoDownloader] Initializing")
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300 // 5 minutes max for video download
        config.waitsForConnectivity = true
        config.allowsConstrainedNetworkAccess = true
        config.allowsExpensiveNetworkAccess = true
        config.shouldUseExtendedBackgroundIdleMode = true
        print("[VideoDownloader] Configured URLSession settings")

        // First create the delegate with a temporary reference
        let delegate = ProgressDelegate(downloader: nil)
        print("[VideoDownloader] Created progress delegate")

        // Then create the session with the delegate
        session = URLSession(
            configuration: config,
            delegate: delegate,
            delegateQueue: .main
        )
        print("[VideoDownloader] Created URLSession with delegate")

        // Store the delegate and update its downloader reference
        progressDelegate = delegate
        delegate.updateDownloader(self)
        print("[VideoDownloader] Updated progress delegate with self reference")
    }

    private func downloadVideo(from videoURL: URL, to destinationURL: URL) {
        print("[VideoDownloader] Starting video download")
        print("[VideoDownloader] From: \(videoURL.absoluteString)")
        print("[VideoDownloader] To: \(destinationURL.path)")

        // Create directory if needed
        try? FileManager.default.createDirectory(
            at: Self.temporaryVideoDirectory,
            withIntermediateDirectories: true
        )

        var request = URLRequest(url: videoURL)
        request.setValue(Constants.chromeUserAgent, forHTTPHeaderField: "User-Agent")

        downloadTask = session.downloadTask(with: request)
        print("[VideoDownloader] Starting download task")
        downloadTask?.resume()
    }

    func startDownload(from url: String) async {
        guard !isDownloading else {
            print("[VideoDownloader] Download already in progress, skipping")
            return
        }
        isDownloading = true
        currentDestinationURL = nil
        delegate?.downloadProgressUpdated(.indeterminate)

        do {
            // 1. Validate and create URL, upgrading HTTP to HTTPS if needed
            print("[VideoDownloader] Attempting to create URL from: '\(url)'")
            var urlString = url
            if urlString.hasPrefix("http://") {
                print("[VideoDownloader] Converting HTTP to HTTPS")
                urlString = "https://" + urlString.dropFirst("http://".count)
            }

            guard let videoURL = URL(string: urlString) else {
                print("[VideoDownloader] Failed to create URL object from string: '\(urlString)'")
                throw VideoDownloadError.invalidURL
            }
            print("[VideoDownloader] Successfully created URL: \(videoURL.absoluteString)")

            // 2. Create destination URL
            let destinationURL = VideoDownloader.temporaryVideoDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mp4")
            print("[VideoDownloader] Will save video to: \(destinationURL.path)")

            // 3. Download the video
            print("[VideoDownloader] Starting video download from: \(videoURL.absoluteString)")
            downloadVideo(from: videoURL, to: destinationURL)

        } catch {
            print("[VideoDownloader] Error occurred: \(error)")
            if !isDownloading { // Was cancelled
                delegate?.downloadFailed(.cancelled)
            } else if let downloadError = error as? VideoDownloadError {
                delegate?.downloadFailed(downloadError)
            } else {
                delegate?.downloadFailed(.downloadFailed(error.localizedDescription))
            }
            isDownloading = false
            downloadTask = nil
        }
    }

    func cancelDownload() {
        isDownloading = false
        downloadTask?.cancel()
        downloadTask = nil

        // Clean up any downloaded file
        if let url = currentDestinationURL {
            try? FileManager.default.removeItem(at: url)
            currentDestinationURL = nil
        }
    }
}

private class ProgressDelegate: NSObject, URLSessionDownloadDelegate {
    private weak var downloader: VideoDownloader?
    // Keep a strong reference to self while download is in progress
    private static var activeInstances: Set<ProgressDelegate> = []
    private var lastProgressUpdate: TimeInterval = 0
    private let progressUpdateThreshold: TimeInterval = 0.1 // Update at most every 0.1 seconds

    init(downloader: VideoDownloader?) {
        print("[ProgressDelegate] Initializing with downloader: \(String(describing: downloader))")
        self.downloader = downloader
        super.init()
        Self.activeInstances.insert(self)
        print("[ProgressDelegate] Added to active instances. Count: \(Self.activeInstances.count)")
    }

    func updateDownloader(_ downloader: VideoDownloader) {
        print("[ProgressDelegate] Updating downloader reference")
        self.downloader = downloader
        print("[ProgressDelegate] New downloader: \(String(describing: self.downloader))")
        print("[ProgressDelegate] Delegate exists: \(String(describing: self.downloader?.delegate))")
    }

    // Called when the download starts
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didResumeAtOffset fileOffset: Int64,
        expectedTotalBytes: Int64
    ) {
        print("[ProgressDelegate] Download resumed at offset: \(fileOffset)/\(expectedTotalBytes)")
    }

    // Called periodically during download
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        print("[ProgressDelegate] didWriteData called")
        print("[ProgressDelegate] Bytes written this time: \(bytesWritten)")
        print("[ProgressDelegate] Total bytes written: \(totalBytesWritten)")
        print("[ProgressDelegate] Total bytes expected: \(totalBytesExpectedToWrite)")
        print("[ProgressDelegate] Downloader exists: \(downloader != nil)")
        print("[ProgressDelegate] Delegate exists: \(String(describing: downloader?.delegate))")

        let now = ProcessInfo.processInfo.systemUptime
        if now - lastProgressUpdate >= progressUpdateThreshold {
            guard totalBytesExpectedToWrite > 0 else {
                print("[ProgressDelegate] Total bytes expected is 0, skipping progress update")
                return
            }

            let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            print("[ProgressDelegate] Sending progress update: \(progress)")
            downloader?.delegate?.downloadProgressUpdated(.progress(progress))
            lastProgressUpdate = now
            print("[ProgressDelegate] Progress update sent")
        }
    }

    // Called when download completes successfully
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        print("[ProgressDelegate] Download finished successfully")
        print("[ProgressDelegate] Temporary location: \(location.path)")
        print("[ProgressDelegate] Downloader exists: \(downloader != nil)")
        print("[ProgressDelegate] Delegate exists: \(String(describing: downloader?.delegate))")
        print("[ProgressDelegate] Active instances before removal: \(Self.activeInstances.count)")
        Self.activeInstances.remove(self)
        print("[ProgressDelegate] Active instances after removal: \(Self.activeInstances.count)")

        // Move the downloaded file to the destination
        // This must happen here instead of the completion block
        guard let downloader else { return }
        let destinationURL = VideoDownloader.temporaryVideoDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")

        do {
            try FileManager.default.moveItem(at: location, to: destinationURL)
            print("[ProgressDelegate] Successfully moved file to: \(destinationURL.path)")
            downloader.currentDestinationURL = destinationURL
            downloader.delegate?.downloadCompleted(tempURL: destinationURL)
        } catch {
            print("[ProgressDelegate] Failed to move downloaded file: \(error)")
            downloader.delegate?.downloadFailed(.downloadFailed(error.localizedDescription))
        }
    }

    // Called when download completes (with or without error)
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        print("[ProgressDelegate] Download task completed")
        print("[ProgressDelegate] Error: \(String(describing: error))")
        print("[ProgressDelegate] Downloader exists: \(downloader != nil)")
        print("[ProgressDelegate] Delegate exists: \(String(describing: downloader?.delegate))")

        if let error {
            downloader?.delegate?.downloadFailed(.downloadFailed(error.localizedDescription))
        }

        print("[ProgressDelegate] Active instances before removal: \(Self.activeInstances.count)")
        Self.activeInstances.remove(self)
        print("[ProgressDelegate] Active instances after removal: \(Self.activeInstances.count)")
    }

    deinit {
        print("[ProgressDelegate] Deinitializing")
        print("[ProgressDelegate] Active instances before removal: \(Self.activeInstances.count)")
        Self.activeInstances.remove(self)
        print("[ProgressDelegate] Active instances after removal: \(Self.activeInstances.count)")
    }
}
