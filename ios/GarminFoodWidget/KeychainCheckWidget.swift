// KeychainCheckWidget.swift
//
// Task 6.4's observable result. Add this widget to the Home Screen and look
// at it — that is the entire test:
//   "SHARED: <value>"  -> the free-tier Keychain Sharing entitlement works
//                          between the app and this extension; D3's shared-
//                          token design proceeds as planned.
//   "NOT SHARED"        -> it doesn't; D3's degraded fallback (each process
//                          bootstraps independently) is what gets built.
//
// Throwaway spike code, same as Shared/KeychainSpike.swift — does not carry
// forward into the real glanceable-surfaces widgets.

import WidgetKit
import SwiftUI

struct KeychainCheckEntry: TimelineEntry {
    let date: Date
    let resultText: String
}

struct KeychainCheckProvider: TimelineProvider {
    func placeholder(in context: Context) -> KeychainCheckEntry {
        KeychainCheckEntry(date: Date(), resultText: "Loading…")
    }

    func getSnapshot(in context: Context, completion: @escaping (KeychainCheckEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<KeychainCheckEntry>) -> Void) {
        let entry = currentEntry()
        // Refresh periodically so re-launching the app (which rewrites the
        // value) shows up here without needing to remove/re-add the widget.
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: entry.date) ?? entry.date
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func currentEntry() -> KeychainCheckEntry {
        let (value, status) = KeychainSpike.read()
        let text = value.map { "SHARED:\n\($0)" } ?? "NOT SHARED\n(status \(status))"
        return KeychainCheckEntry(date: Date(), resultText: text)
    }
}

struct KeychainCheckWidgetView: View {
    let entry: KeychainCheckEntry

    var body: some View {
        VStack(spacing: 4) {
            Text("Keychain spike")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(entry.resultText)
                .font(.caption)
                .multilineTextAlignment(.center)
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct KeychainCheckWidget: Widget {
    let kind = "KeychainCheckWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: KeychainCheckProvider()) { entry in
            KeychainCheckWidgetView(entry: entry)
        }
        .configurationDisplayName("Keychain Spike")
        .description("Task 6.4: shows whether the widget can read what the app wrote to the shared Keychain group.")
        .supportedFamilies([.systemSmall])
    }
}
