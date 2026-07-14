//
//  Grok_macOSApp.swift
//  Grok-macOS
//
//  Created by Nicholas Hershy on 7/8/26.
//

import AppKit
import SwiftUI

@main
struct Grok_macOSApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = BrowserState()

    var body: some Scene {
        Window("Grok", id: "main") {
            ContentView(state: state)
        }
        .defaultSize(width: 1200, height: 800)
        .commands {
            BrowserCommands(state: state)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        HotKeyManager.shared.register()
    }

    // Keep running when the window closes so Option+Space can resummon.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            HotKeyManager.shared.showMainWindow()
        }
        return true
    }
}
