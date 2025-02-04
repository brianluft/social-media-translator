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
        print("[WebViewNavigationDelegate] Page finished loading")

        // Get the page HTML and look for video meta tag
        webView.evaluateJavaScript("document.documentElement.outerHTML") { [weak self] result, error in
            guard let html = result as? String else {
                print("[WebViewNavigationDelegate] Failed to get HTML: \(String(describing: error))")
                return
            }

            if let videoURL = self?.extractVideoURL(from: html) {
                print("[WebViewNavigationDelegate] Found video URL: \(videoURL)")
                self?.startVideoDownload(from: videoURL)
            } else {
                print("[WebViewNavigationDelegate] No video URL found in page")
            }
        }
    }

    private func extractVideoURL(from html: String) -> URL? {
        print("[WebViewNavigationDelegate] Starting HTML parsing, length: \(html.count)")
        print("[WebViewNavigationDelegate] First 500 chars of HTML: \(String(html.prefix(500)))")

        do {
            let doc = try SwiftSoup.parse(html)
            print("[WebViewNavigationDelegate] Successfully parsed HTML document")

            // First try exact og:video meta tag
            print("[WebViewNavigationDelegate] Searching for meta[name=og:video]")
            let nameMetaTags = try doc.select("meta[name=og:video]")
            print("[WebViewNavigationDelegate] Found \(nameMetaTags.array().count) meta tags with name=og:video")

            print("[WebViewNavigationDelegate] Searching for meta[property=og:video]")
            let propertyMetaTags = try doc.select("meta[property=og:video]")
            print(
                "[WebViewNavigationDelegate] Found \(propertyMetaTags.array().count) meta tags with property=og:video"
            )

            // Print all meta tags to see what we have
            print("[WebViewNavigationDelegate] All meta tags in document:")
            let allMeta = try doc.select("meta")
            for meta in allMeta.array() {
                try print("[WebViewNavigationDelegate] Meta tag: \(meta.outerHtml())")
            }

            // Try name first
            if let videoMeta = nameMetaTags.first() {
                try print("[WebViewNavigationDelegate] Found meta tag with name=og:video: \(videoMeta.outerHtml())")
                if let videoURL = try? videoMeta.attr("content") {
                    print("[WebViewNavigationDelegate] Extracted video URL from name tag: \(videoURL)")
                    if !videoURL.isEmpty {
                        var urlString = videoURL
                        if urlString.hasPrefix("http://") {
                            print("[WebViewNavigationDelegate] Converting video URL from HTTP to HTTPS")
                            urlString = "https://" + urlString.dropFirst("http://".count)
                        }
                        print("[WebViewNavigationDelegate] Using secure URL: \(urlString)")
                        return URL(string: urlString)
                    }
                }
            }

            // Try property if name failed
            if let videoMeta = propertyMetaTags.first() {
                try print("[WebViewNavigationDelegate] Found meta tag with property=og:video: \(videoMeta.outerHtml())")
                if let videoURL = try? videoMeta.attr("content") {
                    print("[WebViewNavigationDelegate] Extracted video URL from property tag: \(videoURL)")
                    if !videoURL.isEmpty {
                        var urlString = videoURL
                        if urlString.hasPrefix("http://") {
                            print("[WebViewNavigationDelegate] Converting video URL from HTTP to HTTPS")
                            urlString = "https://" + urlString.dropFirst("http://".count)
                        }
                        print("[WebViewNavigationDelegate] Using secure URL: \(urlString)")
                        return URL(string: urlString)
                    }
                }
            }

            print("[WebViewNavigationDelegate] No video URL found in any meta tags")
            return nil
        } catch {
            print("[WebViewNavigationDelegate] HTML parsing error: \(error)")
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
