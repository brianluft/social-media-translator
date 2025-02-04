import Foundation
import SwiftSoup

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
    weak var delegate: VideoDownloaderDelegate?
    private var isDownloading = false
    private var downloadTask: URLSessionDownloadTask?
    private let session: URLSession
    private let progressDelegate: ProgressDelegate

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

    private func extractVideoURL(from html: String, pageURL: URL) -> URL? {
        do {
            print("[VideoDownloader] Parsing HTML from \(pageURL.absoluteString)")
            let doc = try SwiftSoup.parse(html)

            // Look for og:video meta tag
            let metaTags = try doc.select("meta[name=og:video], meta[property=og:video]")
            print("[VideoDownloader] Found \(metaTags.array().count) og:video meta tags")

            if let videoMeta = metaTags.first() {
                try print("[VideoDownloader] Found meta tag: \(videoMeta.outerHtml())")
                if let videoURL = try? videoMeta.attr("content") {
                    print("[VideoDownloader] Extracted video URL: \(videoURL)")
                    if !videoURL.isEmpty {
                        var urlString = videoURL
                        if urlString.hasPrefix("http://") {
                            print("[VideoDownloader] Converting video URL from HTTP to HTTPS")
                            urlString = "https://" + urlString.dropFirst("http://".count)
                        }

                        if let url = URL(string: urlString) {
                            print("[VideoDownloader] Successfully created URL object: \(url.absoluteString)")
                            return url
                        } else {
                            print("[VideoDownloader] Failed to create URL object from: \(urlString)")
                        }
                    } else {
                        print("[VideoDownloader] Video URL was empty")
                    }
                } else {
                    print("[VideoDownloader] Failed to get content attribute")
                }
            } else {
                print("[VideoDownloader] No og:video meta tag found")
                // Let's also print all meta tags to see what we have
                let allMeta = try doc.select("meta")
                print("[VideoDownloader] All meta tags:")
                for meta in allMeta.array() {
                    try print(meta.outerHtml())
                }
            }

            return nil

        } catch {
            print("[VideoDownloader] HTML parsing error: \(error)")
            return nil
        }
    }

    private func downloadVideo(from videoURL: URL, to destinationURL: URL) {
        print("[VideoDownloader] Starting video download")
        print("[VideoDownloader] From: \(videoURL.absoluteString)")
        print("[VideoDownloader] To: \(destinationURL.path)")

        // Removed the withCheckedThrowingContinuation and completion-based downloadTask
        // Create the task **without** a completion block so delegates will be called
        downloadTask = session.downloadTask(with: videoURL)
        print("[VideoDownloader] Starting download task")
        downloadTask?.resume()
    }

    func startDownload(from url: String) async {
        guard !isDownloading else {
            print("[VideoDownloader] Download already in progress, skipping")
            return
        }
        isDownloading = true
        delegate?.downloadProgressUpdated(.indeterminate)

        do {
            // 1. Validate and create URL, upgrading HTTP to HTTPS if needed
            print("[VideoDownloader] Attempting to create URL from: '\(url)'")
            var urlString = url
            if urlString.hasPrefix("http://") {
                print("[VideoDownloader] Converting HTTP to HTTPS")
                urlString = "https://" + urlString.dropFirst("http://".count)
            }

            guard let pageURL = URL(string: urlString) else {
                print("[VideoDownloader] Failed to create URL object from string: '\(urlString)'")
                throw VideoDownloadError.invalidURL
            }
            print("[VideoDownloader] Successfully created URL: \(pageURL.absoluteString)")

            // 2. Fetch the HTML page
            print("[VideoDownloader] Fetching HTML page from: \(pageURL.absoluteString)")
            let (data, response) = try await session.data(from: pageURL)
            guard let httpResponse = response as? HTTPURLResponse else {
                print("[VideoDownloader] Response was not HTTP: \(response)")
                throw VideoDownloadError.networkError("Invalid response type")
            }
            print("[VideoDownloader] Got HTTP response: \(httpResponse.statusCode)")
            print("[VideoDownloader] Response headers: \(httpResponse.allHeaderFields)")

            guard (200 ... 299).contains(httpResponse.statusCode) else {
                print("[VideoDownloader] Bad HTTP status: \(httpResponse.statusCode)")
                throw VideoDownloadError.networkError("HTTP \(httpResponse.statusCode)")
            }

            guard let html = String(data: data, encoding: .utf8) else {
                print("[VideoDownloader] Failed to decode HTML as UTF-8. Data size: \(data.count) bytes")
                throw VideoDownloadError.networkError("Failed to decode webpage")
            }
            print("[VideoDownloader] Successfully decoded HTML (\(html.count) characters)")
            print("[VideoDownloader] First 500 chars of HTML: \(String(html.prefix(500)))")

            // 3. Extract video URL from HTML
            guard let videoURL = extractVideoURL(from: html, pageURL: pageURL) else {
                print("[VideoDownloader] No video URL found in HTML")
                throw VideoDownloadError.noVideoFound
            }
            print("[VideoDownloader] Found video URL: \(videoURL.absoluteString)")

            // 4. Create destination URL
            let destinationURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mp4")
            print("[VideoDownloader] Will save video to: \(destinationURL.path)")

            // 5. Download the video
            print("[VideoDownloader] Starting video download from: \(videoURL.absoluteString)")
            downloadVideo(from: videoURL, to: destinationURL)

            if isDownloading { // Check if we weren't cancelled
                print("[VideoDownloader] Download completed successfully")
                delegate?.downloadCompleted(tempURL: destinationURL)
            } else {
                print("[VideoDownloader] Download was cancelled")
            }

        } catch {
            print("[VideoDownloader] Error occurred: \(error)")
            if !isDownloading { // Was cancelled
                delegate?.downloadFailed(.cancelled)
            } else if let downloadError = error as? VideoDownloadError {
                delegate?.downloadFailed(downloadError)
            } else {
                delegate?.downloadFailed(.downloadFailed(error.localizedDescription))
            }
        }

        isDownloading = false
        downloadTask = nil
    }

    func cancelDownload() {
        isDownloading = false
        downloadTask?.cancel()
        downloadTask = nil
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
        let destinationURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")

        do {
            try FileManager.default.moveItem(at: location, to: destinationURL)
            print("[ProgressDelegate] Successfully moved file to: \(destinationURL.path)")
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
