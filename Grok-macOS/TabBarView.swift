//
//  TabBarView.swift
//  Grok-macOS
//
//  In-window tab strip above the web content. The active tab gets the strong
//  highlight; when a split is open the pinned tab gets a muted one. Splits
//  are opened from a tab's right-click menu.
//

import SwiftUI

struct TabBarView: View {
    @ObservedObject var state: BrowserState

    var body: some View {
        HStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(state.tabs) { tab in
                        TabItemView(
                            tab: tab,
                            isActiveTab: tab === state.activeTab,
                            isPinnedTab: tab === state.pinnedTab,
                            canClose: state.tabs.count > 1,
                            select: { state.select(tab) },
                            close: { state.closeTab(tab) }
                        )
                        .contextMenu {
                            if state.isSplit {
                                if tab === state.activeTab || tab === state.pinnedTab {
                                    Button("Close Split View") { state.closeSplit() }
                                } else {
                                    // Communicates the one-split-at-a-time rule.
                                    Button("Open in Split View") {}
                                        .disabled(true)
                                }
                            } else if tab !== state.activeTab {
                                Button("Open in Split View") { state.openSplit(with: tab) }
                            }
                            Divider()
                            Button("Close Tab") { state.closeTab(tab) }
                        }
                    }
                }
                .padding(.horizontal, 8)
            }

            NewTabButton { state.newTab() }

            if state.isSplit {
                CloseSplitButton { state.closeSplit() }
            }
        }
        .padding(.trailing, 8)
        .frame(height: 34)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

private struct TabItemView: View {
    @ObservedObject var tab: WebViewModel
    let isActiveTab: Bool
    let isPinnedTab: Bool
    let canClose: Bool
    let select: () -> Void
    let close: () -> Void

    @State private var isHovered = false

    private var backgroundOpacity: Double {
        if isActiveTab { return 0.12 }
        if isPinnedTab { return 0.06 }
        return isHovered ? 0.08 : 0
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(tab.pageTitle)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(isActiveTab ? .primary : .secondary)
                .frame(maxWidth: .infinity)

            if canClose {
                CloseTabButton(action: close)
                    .opacity(isHovered || isActiveTab ? 1 : 0)
            }
        }
        .padding(.horizontal, 8)
        .frame(minWidth: 100, maxWidth: 200)
        .frame(height: 26)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(backgroundOpacity))
        )
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .onTapGesture(perform: select)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .help(tab.pageTitle)
    }
}

private struct CloseTabButton: View {
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
                .background(Color.primary.opacity(isHovered ? 0.12 : 0))
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Close Tab (⌘W)")
        .onHover { isHovered = $0 }
    }
}

private struct NewTabButton: View {
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .background(Color.primary.opacity(isHovered ? 0.08 : 0))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("New Tab (⌘T)")
        .onHover { isHovered = $0 }
    }
}

// Appears next to the + button only while a split is open.
private struct CloseSplitButton: View {
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "rectangle.split.2x1.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24, height: 24)
                .background(Color.primary.opacity(isHovered ? 0.08 : 0))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Close Split View (⌘D)")
        .onHover { isHovered = $0 }
    }
}
