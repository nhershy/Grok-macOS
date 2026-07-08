//
//  ZoomControls.swift
//  Grok-macOS
//
//  Floating −/+ zoom pill overlaid at the top-left of the web content,
//  styled after Grok's monochrome buttons. ContentView offsets it by the
//  zoom-scaled sidebar width so it hugs the sidebar edge at any zoom.
//

import SwiftUI

struct ZoomControls: View {
    @ObservedObject var model: WebViewModel

    var body: some View {
        HStack(spacing: 0) {
            ZoomButton(systemName: "minus", help: "Zoom out (⌘−)") {
                model.zoomOut()
            }

            Rectangle()
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.3))
                .frame(width: 1, height: 11)

            ZoomButton(systemName: "plus", help: "Zoom in (⌘+)") {
                model.zoomIn()
            }
        }
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.9)))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
    }
}

// Grok-style inverted pill button: background-colored glyph on a primary
// (black in light mode, white in dark) capsule, brightening on hover.
private struct ZoomButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color(nsColor: .windowBackgroundColor))
                .frame(width: 30, height: 24)
                .background(Color(nsColor: .windowBackgroundColor).opacity(isHovered ? 0.22 : 0))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}
