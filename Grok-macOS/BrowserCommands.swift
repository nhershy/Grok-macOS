//
//  BrowserCommands.swift
//  Grok-macOS
//

import SwiftUI

struct BrowserCommands: Commands {
    @ObservedObject var state: BrowserState

    // Per-tab actions resolve state.focusedTab inside the closures so they
    // always hit the tab focused at invocation time.
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Chat") { state.focusedTab.newChat() }
                .keyboardShortcut("n", modifiers: .command)

            Button("New Tab") { state.newTab() }
                .keyboardShortcut("t", modifiers: .command)

            Button("Close Tab") { state.closeTab(state.focusedTab) }
                .keyboardShortcut("w", modifiers: .command)
        }

        CommandMenu("Navigate") {
            Button("Reload Page") { state.focusedTab.reload() }
                .keyboardShortcut("r", modifiers: .command)

            Divider()

            Button("Back") { state.focusedTab.goBack() }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(!state.focusedTab.canGoBack)

            Button("Forward") { state.focusedTab.goForward() }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(!state.focusedTab.canGoForward)

            Divider()

            Button("Home") { state.focusedTab.newChat() }
                .keyboardShortcut("h", modifiers: [.command, .shift])
        }

        CommandMenu("Tabs") {
            Button("Show Next Tab") { state.nextTab() }
                .keyboardShortcut("]", modifiers: [.command, .shift])

            Button("Show Previous Tab") { state.previousTab() }
                .keyboardShortcut("[", modifiers: [.command, .shift])

            Divider()

            ForEach(1...9, id: \.self) { i in
                Button("Tab \(i)") { state.selectTab(at: i - 1) }
                    .keyboardShortcut(KeyEquivalent(Character("\(i)")), modifiers: .command)
                    .disabled(i > state.tabs.count)
            }

            Divider()

            Button("Close Split View") { state.closeSplit() }
                .keyboardShortcut("d", modifiers: .command)
                .disabled(!state.isSplit)
        }

        CommandGroup(after: .toolbar) {
            Button("Zoom In") { state.focusedTab.zoomIn() }
                .keyboardShortcut("=", modifiers: .command)

            Button("Zoom Out") { state.focusedTab.zoomOut() }
                .keyboardShortcut("-", modifiers: .command)

            Button("Actual Size") { state.focusedTab.zoomReset() }
                .keyboardShortcut("0", modifiers: .command)
        }
    }
}
