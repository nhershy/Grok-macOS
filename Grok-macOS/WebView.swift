//
//  WebView.swift
//  Grok-macOS
//

import SwiftUI
import WebKit

struct WebView: NSViewRepresentable {
    let model: WebViewModel

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        // Dark backing matching underPageBackgroundColor so nothing white
        // can peek through while the webview lays out or swaps.
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(white: 0.08, alpha: 1).cgColor
        attach(to: container)
        return container
    }

    // The model owns the webview and its navigation; all we do here is keep
    // the container showing the current model's webview when the pane's tab
    // changes. Re-parenting does not reload the page.
    func updateNSView(_ container: NSView, context: Context) {
        let webView = model.webView
        if webView.superview !== container {
            container.subviews.forEach { $0.removeFromSuperview() }
            attach(to: container)
        } else if webView.frame != container.bounds {
            // Stale frame: the webview was detached while the window resized.
            webView.frame = container.bounds
        }
    }

    private func attach(to container: NSView) {
        let webView = model.webView
        webView.frame = container.bounds
        webView.autoresizingMask = [.width, .height]
        container.addSubview(webView)
    }
}
