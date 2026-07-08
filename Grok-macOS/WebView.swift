//
//  WebView.swift
//  Grok-macOS
//

import SwiftUI
import WebKit

struct WebView: NSViewRepresentable {
    let model: WebViewModel

    func makeNSView(context: Context) -> WKWebView {
        model.webView
    }

    // Deliberately empty: the model owns the webview and its navigation;
    // reacting to SwiftUI updates here would re-trigger loads.
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
