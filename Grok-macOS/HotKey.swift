//
//  HotKey.swift
//  Grok-macOS
//
//  Global Option+Space hotkey via Carbon RegisterEventHotKey: works inside
//  the sandbox and needs no Accessibility/Input Monitoring permission.
//

import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
final class HotKeyManager {

    static let shared = HotKeyManager()

    weak var mainWindow: NSWindow?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    private init() {}

    func register() {
        guard hotKeyRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetApplicationEventTarget(), hotKeyEventHandler, 1, &eventType, nil, &handlerRef)

        let hotKeyID = EventHotKeyID(signature: OSType(0x47_52_4F_4B), id: 1) // 'GROK'
        RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    func toggle() {
        if NSApp.isActive, let window = mainWindow, window.isVisible {
            NSApp.hide(nil)
        } else {
            showMainWindow()
        }
    }

    func showMainWindow() {
        // Cooperative activation: take focus from the frontmost app so the
        // hotkey works even while another app is active.
        if let frontmost = NSWorkspace.shared.frontmostApplication, frontmost != .current {
            NSRunningApplication.current.activate(from: frontmost, options: [.activateAllWindows])
        } else {
            NSApp.activate()
        }
        mainWindow?.makeKeyAndOrderFront(nil)
    }
}

// Carbon requires a C function pointer, which cannot carry actor isolation;
// the event arrives on the main thread, so hop back explicitly.
private nonisolated func hotKeyEventHandler(
    _ handler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    MainActor.assumeIsolated {
        HotKeyManager.shared.toggle()
    }
    return noErr
}

// Grabs the hosting NSWindow so the hotkey can order it front after it has
// been closed (SwiftUI keeps the Window scene's NSWindow instance alive).
struct WindowGrabber: NSViewRepresentable {

    private final class GrabberView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window {
                HotKeyManager.shared.mainWindow = window
            }
        }
    }

    func makeNSView(context: Context) -> NSView {
        GrabberView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
