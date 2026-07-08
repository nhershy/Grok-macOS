//
//  WebViewModel.swift
//  Grok-macOS
//
//  Owns the long-lived WKWebView and implements all WebKit delegates:
//  navigation policy, popups, uploads, downloads, and media capture.
//

import AppKit
import Combine
import SwiftUI
import WebKit

@MainActor
final class WebViewModel: NSObject, ObservableObject {

    static let homeURL = URL(string: "https://grok.com")!

    // Hosts that stay inside the app. Everything else opens in the default browser.
    // Auth providers must be in-app or sign-in flows break.
    private static let inAppHosts: [String] = [
        "grok.com",
        "x.ai",
        "x.com",
        "twitter.com",
        "accounts.google.com",
        "accounts.youtube.com",  // Google auth cookie-sync redirect
        "google.com",            // OAuth consent intermediate pages
        "gstatic.com",
        "appleid.apple.com",
        "apple.com",
        "recaptcha.net",
        "hcaptcha.com",
        "cloudflare.com",
        "challenges.cloudflare.com",
    ]

    // A real Safari UA (no app token) so Google OAuth doesn't reject the
    // embedded webview with "This browser or app may not be secure".
    private static let safariUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.4 Safari/605.1.15"

    private static let zoomDefaultsKey = "pageZoom"

    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var pageTitle = "Grok"

    let webView: WKWebView

    private var observations: [NSKeyValueObservation] = []
    private var popupWindows: [NSWindow] = []
    private var activeDownloads: [WKDownload: URL] = [:]

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.preferences.isElementFullscreenEnabled = true

        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()

        webView.customUserAgent = Self.safariUserAgent
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        webView.underPageBackgroundColor = NSColor(white: 0.08, alpha: 1)
        #if DEBUG
        webView.isInspectable = true
        #endif

        webView.navigationDelegate = self
        webView.uiDelegate = self

        if UserDefaults.standard.object(forKey: Self.zoomDefaultsKey) != nil {
            let stored = UserDefaults.standard.double(forKey: Self.zoomDefaultsKey)
            webView.pageZoom = min(max(stored, 0.5), 3.0)
        }

        observations = [
            webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] view, _ in
                MainActor.assumeIsolated { self?.canGoBack = view.canGoBack }
            },
            webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] view, _ in
                MainActor.assumeIsolated { self?.canGoForward = view.canGoForward }
            },
            webView.observe(\.title, options: [.initial, .new]) { [weak self] view, _ in
                MainActor.assumeIsolated {
                    let title = view.title ?? ""
                    self?.pageTitle = title.isEmpty ? "Grok" : title
                }
            },
        ]

        webView.load(URLRequest(url: Self.homeURL))
    }

    // MARK: - Commands

    func newChat() {
        webView.load(URLRequest(url: Self.homeURL))
    }

    func reload() {
        webView.reload()
    }

    func goBack() {
        webView.goBack()
    }

    func goForward() {
        webView.goForward()
    }

    func zoomIn() {
        webView.pageZoom = min(webView.pageZoom * 1.1, 3.0)
        saveZoom()
    }

    func zoomOut() {
        webView.pageZoom = max(webView.pageZoom / 1.1, 0.5)
        saveZoom()
    }

    func zoomReset() {
        webView.pageZoom = 1.0
        saveZoom()
    }

    private func saveZoom() {
        UserDefaults.standard.set(webView.pageZoom, forKey: Self.zoomDefaultsKey)
    }

    // MARK: - Host policy

    private func isInAppURL(_ url: URL) -> Bool {
        guard let host = url.host()?.lowercased() else { return false }
        return Self.inAppHosts.contains { host == $0 || host.hasSuffix(".\($0)") }
    }
}

// MARK: - WKNavigationDelegate

extension WebViewModel: WKNavigationDelegate {

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        // mailto:, facetime:, etc. go to the system handler.
        if let scheme = url.scheme?.lowercased(), scheme != "http", scheme != "https" {
            if scheme != "about" && scheme != "blob" && scheme != "data" {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
        }

        if navigationAction.shouldPerformDownload {
            decisionHandler(.download)
            return
        }

        // Only user-clicked main-frame links leave the app; redirects,
        // subframes, and form posts must stay or OAuth flows break.
        if navigationAction.navigationType == .linkActivated,
           navigationAction.targetFrame?.isMainFrame ?? true,
           !isInAppURL(url) {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download)
    }

    func webView(
        _ webView: WKWebView,
        navigationAction: WKNavigationAction,
        didBecome download: WKDownload
    ) {
        download.delegate = self
    }

    func webView(
        _ webView: WKWebView,
        navigationResponse: WKNavigationResponse,
        didBecome download: WKDownload
    ) {
        download.delegate = self
    }
}

// MARK: - WKUIDelegate

extension WebViewModel: WKUIDelegate {

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url, !isInAppURL(url) {
            NSWorkspace.shared.open(url)
            return nil
        }

        // Auth popups (window.open from Google/Apple sign-in) need a real
        // child webview built from the provided configuration so the
        // opener/postMessage relationship survives.
        let popup = WKWebView(frame: NSRect(x: 0, y: 0, width: 560, height: 640), configuration: configuration)
        popup.customUserAgent = Self.safariUserAgent
        popup.navigationDelegate = self
        popup.uiDelegate = self

        let window = NSWindow(
            contentRect: popup.frame,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = popup
        window.title = "Grok"
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        popupWindows.append(window)

        return popup
    }

    func webViewDidClose(_ webView: WKWebView) {
        if let index = popupWindows.firstIndex(where: { $0.contentView === webView }) {
            popupWindows[index].close()
            popupWindows.remove(at: index)
        }
    }

    func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping ([URL]?) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.canChooseFiles = true

        let respond: (NSApplication.ModalResponse) -> Void = { response in
            completionHandler(response == .OK ? panel.urls : nil)
        }
        if let window = webView.window {
            panel.beginSheetModal(for: window, completionHandler: respond)
        } else {
            respond(panel.runModal())
        }
    }

    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        let host = origin.host.lowercased()
        let trusted = Self.inAppHosts.contains { host == $0 || host.hasSuffix(".\($0)") }
        decisionHandler(trusted ? .grant : .deny)
    }
}

// MARK: - WKDownloadDelegate

extension WebViewModel: WKDownloadDelegate {

    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping (URL?) -> Void
    ) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedFilename
        panel.canCreateDirectories = true

        let respond: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url else {
                completionHandler(nil)
                return
            }
            // WKDownload refuses to overwrite; the save panel already
            // confirmed replacement with the user.
            try? FileManager.default.removeItem(at: url)
            self?.activeDownloads[download] = url
            completionHandler(url)
        }
        if let window = download.webView?.window ?? webView.window {
            panel.beginSheetModal(for: window, completionHandler: respond)
        } else {
            respond(panel.runModal())
        }
    }

    func downloadDidFinish(_ download: WKDownload) {
        if let url = activeDownloads.removeValue(forKey: download) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        activeDownloads.removeValue(forKey: download)
        NSSound.beep()
    }
}
