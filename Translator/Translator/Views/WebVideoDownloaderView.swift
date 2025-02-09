import SwiftSoup
import SwiftUI
import WebKit

struct WebVideoDownloaderView: View {
    @Binding var videoURL: String
    let onDownloadComplete: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    @State var downloadProgress: DownloadProgress = .indeterminate
    @State var error: VideoDownloadError?
    @State var showError = false
    @State var tempVideoURL: URL?
    @State private var webViewNavigationDelegate: WebViewNavigationDelegate?
    @State var isDownloadingVideo = false

    private var secureURL: URL? {
        var urlString = videoURL
        if urlString.hasPrefix("http://") {
            urlString = "https://" + urlString.dropFirst("http://".count)
        }
        return URL(string: urlString)
    }

    func dismissView() {
        dismiss()
    }

    var body: some View {
        VStack {
            Text(isDownloadingVideo ? "Downloading Video" : "Loading Video Page")
                .font(.title2)
                .bold()
                .padding(.top)

            if isDownloadingVideo {
                Spacer()

                if case let .progress(value) = downloadProgress {
                    ProgressView(value: value) {
                        Text("\(Int(value * 100))%")
                            .font(.caption)
                    }
                    .progressViewStyle(CircularProgressViewStyle())
                    .controlSize(.large)
                    .scaleEffect(2.0)
                    .frame(width: 150, height: 150)
                    .padding()
                }

                Spacer()
            } else if let url = secureURL {
                WebView(url: url, delegate: $webViewNavigationDelegate)
                    .onAppear {
                        webViewNavigationDelegate = WebViewNavigationDelegate(view: self)
                    }
            } else {
                Text("Invalid URL")
                    .foregroundColor(.red)
            }

            Text(
                isDownloadingVideo ?
                    "Downloading the video. Please wait." :
                    "Waiting for the video to load.\nIf there is a CAPTCHA, please complete it."
            )
            .font(.subheadline)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .padding()

            Button(role: .destructive) {
                dismissView()
            } label: {
                Text("Cancel")
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.bordered)
            .padding(.horizontal)
            .padding(.bottom)
        }
        .alert("Download Failed", isPresented: $showError, presenting: error) { _ in
            Button("OK") {
                dismissView()
            }
        } message: { error in
            Text(error.localizedDescription)
        }
    }
}

struct WebView: UIViewRepresentable {
    let url: URL
    @Binding var delegate: WebViewNavigationDelegate?

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = Constants.chromeUserAgent
        webView.navigationDelegate = delegate
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.navigationDelegate = delegate
        var urlString = url.absoluteString
        if urlString.hasPrefix("http://") {
            urlString = "https://" + urlString.dropFirst("http://".count)
        }
        if let secureURL = URL(string: urlString) {
            webView.load(URLRequest(url: secureURL))
        }
    }
}

class WebViewNavigationDelegate: NSObject, WKNavigationDelegate {
    private var view: WebVideoDownloaderView
    private var downloader: VideoDownloader?
    private var isDownloading = false

    init(view: WebVideoDownloaderView) {
        self.view = view
        super.init()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Get the page HTML and look for video meta tag
        webView.evaluateJavaScript("document.documentElement.outerHTML") { [weak self] result, _ in
            guard let html = result as? String else {
                return
            }

            if let videoURL = self?.extractVideoURL(from: html) {
                self?.startVideoDownload(from: videoURL)
            }
        }
    }

    private func extractVideoURL(from html: String) -> URL? {
        do {
            let doc = try SwiftSoup.parse(html)

            // First try exact og:video meta tag
            let nameMetaTags = try doc.select("meta[name=og:video]")

            let propertyMetaTags = try doc.select("meta[property=og:video]")

            // Try name first
            if let videoMeta = nameMetaTags.first() {
                if let videoURL = try? videoMeta.attr("content") {
                    if !videoURL.isEmpty {
                        var urlString = videoURL
                        if urlString.hasPrefix("http://") {
                            urlString = "https://" + urlString.dropFirst("http://".count)
                        }
                        return URL(string: urlString)
                    }
                }
            }

            // Try property if name failed
            if let videoMeta = propertyMetaTags.first() {
                if let videoURL = try? videoMeta.attr("content") {
                    if !videoURL.isEmpty {
                        var urlString = videoURL
                        if urlString.hasPrefix("http://") {
                            urlString = "https://" + urlString.dropFirst("http://".count)
                        }
                        return URL(string: urlString)
                    }
                }
            }

            return nil
        } catch {
            return nil
        }
    }

    private func startVideoDownload(from videoURL: URL) {
        guard !isDownloading else { return }
        isDownloading = true

        Task { @MainActor in
            view.isDownloadingVideo = true
        }

        downloader = VideoDownloader()
        downloader?.delegate = self

        Task {
            await downloader?.startDownload(from: videoURL.absoluteString)
        }
    }
}

extension WebViewNavigationDelegate: VideoDownloaderDelegate {
    func downloadProgressUpdated(_ progress: DownloadProgress) {
        Task { @MainActor in
            view.downloadProgress = progress
        }
    }

    func downloadCompleted(tempURL: URL) {
        Task { @MainActor in
            view.tempVideoURL = tempURL
            view.onDownloadComplete(tempURL)
            view.dismissView()
        }
    }

    func downloadFailed(_ error: VideoDownloadError) {
        Task { @MainActor in
            view.error = error
            view.showError = true
            view.isDownloadingVideo = false
        }
    }
}
