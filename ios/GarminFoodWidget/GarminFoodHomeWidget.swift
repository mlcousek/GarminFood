// GarminFoodHomeWidget.swift
//
// The Home Screen widget (design.md D2, REVISED 2026-09-14; tasks.md
// 19.1-19.2, superseding their original wording): a static, data-free
// "open the app" shortcut, `systemSmall` only.
//
// Earlier drafts of this change (proposal.md's original "What Changes" list,
// tasks.md's original 19.1-19.4) planned a `Gauge`-based calorie ring plus
// 2-4 interactive quick-add buttons, read fresh from Garmin. That is ruled
// out entirely, not delayed or degraded: `add-garmin-auth-and-sync` task 6.4
// confirmed there is no App Group and no Keychain Sharing on this account
// (`errSecMissingEntitlement`/-34018, live). A `TimelineProvider` running in
// this extension's own process has no channel to Garmin (no credential of
// its own, and no way to present a sign-in UI from a widget's
// non-interactive rendering context) and no channel to the app's own local
// data either -- there is nothing this widget could ever successfully
// fetch, so it fetches nothing, ever. See openspec/config.yaml's Hard
// Constraints and design.md D2's REVISED section for the full reasoning.
//
// Also carries no `Button(intent:)` quick-add tiles: those would need the
// same "runs in the app's own process" treatment as the logging Controls
// (QuickPickLoggingIntents.swift), and this project already has a dedicated,
// better-suited surface for that (Controls, placeable in Control Center, the
// Lock Screen, and the Action Button, none of which are exclusive to being
// unlocked the way opening a Home Screen widget's button is). Keeping this
// widget to a single, whole-widget tap target keeps its one honest job --
// "get to the app fast" -- simple and unambiguous.

import WidgetKit
import SwiftUI

struct GarminFoodHomeEntry: TimelineEntry {
    let date: Date
}

struct GarminFoodHomeProvider: TimelineProvider {
    func placeholder(in context: Context) -> GarminFoodHomeEntry {
        GarminFoodHomeEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (GarminFoodHomeEntry) -> Void) {
        completion(GarminFoodHomeEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GarminFoodHomeEntry>) -> Void) {
        // `.never`: there is nothing to refresh towards (see file header).
        // Requesting a future reload here would only spend WidgetKit's
        // limited per-widget daily reload budget for a widget that could
        // never have anything new to show anyway.
        completion(Timeline(entries: [GarminFoodHomeEntry(date: .now)], policy: .never))
    }
}

struct GarminFoodHomeWidgetView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "fork.knife.circle.fill")
                .font(.system(size: 30, weight: .semibold))
                .widgetAccentable()
            Text("Log Food")
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(for: .widget) {
            // Theme lives in Shared/, compiled into this extension too, so
            // the widget and the app can't drift apart.
            LinearGradient(
                colors: [Theme.accent, Theme.accentDeep],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .widgetURL(GarminFoodDeepLink.openAppURL)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Log Food")
        .accessibilityHint("Opens GarminFood")
    }
}

struct GarminFoodHomeWidget: Widget {
    static let kind = "com.mlcousek.garminfood.widget.home"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: GarminFoodHomeProvider()) { _ in
            GarminFoodHomeWidgetView()
        }
        .configurationDisplayName("Log Food")
        .description("A one-tap shortcut to open GarminFood and log a food. Shows no live calorie data -- there is no way for a widget to read that on this account (design.md D2).")
        .supportedFamilies([.systemSmall])
    }
}

#Preview(as: .systemSmall) {
    GarminFoodHomeWidget()
} timeline: {
    GarminFoodHomeEntry(date: .now)
}
