//
//  UsagePill.swift
//  Grok-macOS
//
//  Floating rate-limit pill overlaid at the bottom-right of the web
//  content, styled to match ZoomControls. One segment per model seen,
//  with a locally ticking refill countdown when a limit is exhausted.
//

import SwiftUI

struct UsagePill: View {
    @ObservedObject var model: WebViewModel

    var body: some View {
        HStack(spacing: 0) {
            if model.usageByModel.isEmpty {
                // Placeholder so the toggle gives feedback before first data
                // arrives (or while signed out).
                Text("–/–")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color(nsColor: .windowBackgroundColor).opacity(0.5))
                    .padding(.horizontal, 10)
                    .frame(height: 24)
            } else {
                let entries = model.usageByModel.sorted { $0.key < $1.key }
                ForEach(Array(entries.enumerated()), id: \.element.key) { index, entry in
                    if index > 0 {
                        Rectangle()
                            .fill(Color(nsColor: .windowBackgroundColor).opacity(0.3))
                            .frame(width: 1, height: 11)
                    }
                    UsageSegment(modelName: entry.key, info: entry.value)
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.9)))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
    }
}

private struct UsageSegment: View {
    let modelName: String
    let info: ModelRateLimit

    var body: some View {
        Group {
            if let wait = info.waitTimeSeconds, wait > 0 {
                // TimelineView drives the refill countdown at 1 Hz between
                // refreshes; the next poll re-syncs it.
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    content(at: context.date)
                }
            } else {
                content(at: info.fetchedAt)
            }
        }
        .help(helpText)
    }

    private func content(at date: Date) -> some View {
        HStack(spacing: 4) {
            Text(shortName)
                .foregroundStyle(Color(nsColor: .windowBackgroundColor).opacity(0.55))

            if let remaining = info.remainingQueries, let total = info.totalQueries {
                Text("\(remaining)/\(total)")
                    .foregroundStyle(info.statusColor ?? Color(nsColor: .windowBackgroundColor))
            }

            if let refill = info.refillRemaining(at: date) {
                Image(systemName: "clock")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .windowBackgroundColor).opacity(0.7))
                Text(Self.format(seconds: refill))
                    .foregroundStyle(Color(nsColor: .windowBackgroundColor).opacity(0.7))
            }
        }
        .font(.system(size: 10, weight: .semibold, design: .monospaced))
        .padding(.horizontal, 10)
        .frame(height: 24)
    }

    private var shortName: String {
        modelName.hasPrefix("grok-") ? String(modelName.dropFirst("grok-".count)) : modelName
    }

    private var helpText: String {
        var parts = [modelName]
        if let remaining = info.remainingQueries, let total = info.totalQueries {
            parts.append("\(remaining) of \(total) queries remaining")
        }
        if let low = info.lowEffortRemaining {
            parts.append("low effort: \(low)")
        }
        if let high = info.highEffortRemaining {
            parts.append("high effort: \(high)")
        }
        if let window = info.windowSizeSeconds {
            parts.append("window: \(Self.format(seconds: window))")
        }
        return parts.joined(separator: " · ")
    }

    private static func format(seconds: Int) -> String {
        if seconds >= 3600 {
            return "\(seconds / 3600)h \(String(format: "%02d", (seconds % 3600) / 60))m"
        }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
