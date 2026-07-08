//
//  BrowserCommands.swift
//  Grok-macOS
//

import SwiftUI

struct BrowserCommands: Commands {
    @ObservedObject var model: WebViewModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Chat") { model.newChat() }
                .keyboardShortcut("n", modifiers: .command)
        }

        CommandMenu("Navigate") {
            Button("Reload Page") { model.reload() }
                .keyboardShortcut("r", modifiers: .command)

            Divider()

            Button("Back") { model.goBack() }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(!model.canGoBack)

            Button("Forward") { model.goForward() }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(!model.canGoForward)

            Divider()

            Button("Home") { model.newChat() }
                .keyboardShortcut("h", modifiers: [.command, .shift])
        }

        CommandGroup(after: .toolbar) {
            Button("Zoom In") { model.zoomIn() }
                .keyboardShortcut("=", modifiers: .command)

            Button("Zoom Out") { model.zoomOut() }
                .keyboardShortcut("-", modifiers: .command)

            Button("Actual Size") { model.zoomReset() }
                .keyboardShortcut("0", modifiers: .command)

            Divider()
        }
    }
}
