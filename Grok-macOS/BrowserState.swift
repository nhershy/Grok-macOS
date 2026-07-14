//
//  BrowserState.swift
//  Grok-macOS
//
//  Owns the open tabs (each a WebViewModel) and the split layout: the active
//  tab fills the window (left pane when split) and follows tab-bar clicks,
//  while an optional pinned tab sits in the right pane until the split is
//  closed. Menu commands route to the pane the user last clicked.
//

import AppKit
import Combine
import SwiftUI

@MainActor
final class BrowserState: ObservableObject {

    @Published private(set) var tabs: [WebViewModel]
    @Published private(set) var activeTab: WebViewModel
    @Published private(set) var pinnedTab: WebViewModel?

    var isSplit: Bool { pinnedTab != nil }

    // Menu-command target: the displayed webview the user last clicked.
    // Falls back to the active tab whenever the layout changes.
    @Published private(set) var focusedTab: WebViewModel

    private var mouseMonitor: Any?
    private var tabChangeForwarder: AnyCancellable?

    init() {
        let tab = WebViewModel()
        tabs = [tab]
        activeTab = tab
        focusedTab = tab
        rewireForwarding()

        // WKWebView swallows clicks before SwiftUI gestures see them, so the
        // last-clicked pane is tracked by peeking at mouse-downs here and
        // passing the event through untouched.
        mouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            MainActor.assumeIsolated { self?.updateFocus(for: event) }
            return event
        }
    }

    // MARK: - Tabs

    func newTab() {
        let tab = WebViewModel()
        tabs.append(tab)
        rewireForwarding()
        activate(tab)
    }

    func select(_ tab: WebViewModel) {
        guard tabs.contains(where: { $0 === tab }) else { return }
        if tab === pinnedTab {
            // Already visible in the right pane; a tab can't be in both
            // panes, so just hand it keyboard focus.
            focusedTab = tab
            makeFirstResponder(tab)
            return
        }
        activate(tab)
    }

    func selectTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        select(tabs[index])
    }

    func closeTab(_ tab: WebViewModel) {
        guard let index = tabs.firstIndex(where: { $0 === tab }) else { return }

        // Last tab: keep it (and the session) alive, just hide the window,
        // matching the pre-tabs ⌘W behavior with Option+Space re-summon.
        if tabs.count == 1 {
            let window = tab.webView.window ?? HotKeyManager.shared.mainWindow
            window?.performClose(nil)
            return
        }

        tabs.remove(at: index)
        rewireForwarding()

        if tab === pinnedTab {
            closeSplit()
        } else if tab === activeTab {
            if let replacement = nearestTab(to: index, excluding: pinnedTab) {
                activate(replacement)
            } else if let pinned = pinnedTab {
                // Only the pinned tab is left; it becomes the active tab.
                pinnedTab = nil
                activate(pinned)
            }
        } else if tab === focusedTab {
            focusedTab = activeTab
        }
    }

    func nextTab() {
        cycleActiveTab(by: 1)
    }

    func previousTab() {
        cycleActiveTab(by: -1)
    }

    // MARK: - Split

    func openSplit(with tab: WebViewModel) {
        guard !isSplit, tab !== activeTab, tabs.contains(where: { $0 === tab }) else { return }
        pinnedTab = tab
        focusedTab = activeTab
        makeFirstResponder(activeTab)
    }

    func closeSplit() {
        guard isSplit else { return }
        pinnedTab = nil
        focusedTab = activeTab
        makeFirstResponder(activeTab)
    }

    // MARK: - Helpers

    private func activate(_ tab: WebViewModel) {
        activeTab = tab
        focusedTab = tab
        makeFirstResponder(tab)
    }

    private func cycleActiveTab(by step: Int) {
        guard let current = tabs.firstIndex(where: { $0 === activeTab }) else { return }
        var index = current
        for _ in 1..<tabs.count {
            index = (index + step + tabs.count) % tabs.count
            let candidate = tabs[index]
            if candidate !== pinnedTab {
                activate(candidate)
                return
            }
        }
    }

    private func nearestTab(to removedIndex: Int, excluding excluded: WebViewModel?) -> WebViewModel? {
        let candidates = tabs.enumerated()
            .filter { $0.element !== excluded }
            .sorted { abs($0.offset - removedIndex) < abs($1.offset - removedIndex) }
        return candidates.first?.element
    }

    // Deferred so SwiftUI has re-parented the webview before it takes focus.
    private func makeFirstResponder(_ tab: WebViewModel) {
        let webView = tab.webView
        DispatchQueue.main.async {
            webView.window?.makeFirstResponder(webView)
        }
    }

    private func updateFocus(for event: NSEvent) {
        guard isSplit, let window = event.window else { return }
        func hit(_ model: WebViewModel?) -> Bool {
            guard let webView = model?.webView, webView.window === window else { return false }
            return webView.bounds.contains(webView.convert(event.locationInWindow, from: nil))
        }
        if hit(pinnedTab), let pinned = pinnedTab {
            if focusedTab !== pinned { focusedTab = pinned }
        } else if hit(activeTab) {
            if focusedTab !== activeTab { focusedTab = activeTab }
        }
    }

    // Nested ObservableObjects don't propagate: menu items disabled off the
    // focused tab's canGoBack/canGoForward would go stale without this.
    private func rewireForwarding() {
        tabChangeForwarder = Publishers.MergeMany(tabs.map(\.objectWillChange))
            .sink { [weak self] _ in self?.objectWillChange.send() }
    }
}
