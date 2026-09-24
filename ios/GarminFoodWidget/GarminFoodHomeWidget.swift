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
    /// This widget's own Edit Widget theme (WidgetTheme.swift, D13).
    var theme: WidgetThemeOption = .standard
}

struct GarminFoodHomeProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> GarminFoodHomeEntry {
        GarminFoodHomeEntry(date: .now)
    }

    func snapshot(for configuration: WidgetThemeIntent, in context: Context) async -> GarminFoodHomeEntry {
        GarminFoodHomeEntry(date: .now, theme: configuration.theme)
    }

    func timeline(for configuration: WidgetThemeIntent, in context: Context) async -> Timeline<GarminFoodHomeEntry> {
        // `.never`: there is nothing to refresh towards (see file header).
        // Requesting a future reload here would only spend WidgetKit's
        // limited per-widget daily reload budget for a widget that could
        // never have anything new to show anyway. Editing the widget's
        // theme reloads it by itself.
        Timeline(entries: [GarminFoodHomeEntry(date: .now, theme: configuration.theme)], policy: .never)
    }
}

struct GarminFoodHomeWidgetView: View {
    let entry: GarminFoodHomeEntry
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // The widget's own theme from AppearanceKit, not `Theme.*`: the
        // app's theme can't reach this process (WidgetTheme.swift).
        let colors = WidgetThemeColors(option: entry.theme, colorScheme: colorScheme)
        VStack(spacing: 6) {
            Image(systemName: "fork.knife.circle.fill")
                .font(.system(size: 30, weight: .semibold))
                .widgetAccentable()
            Text("Log Food")
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(colors.label)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(for: .widget) {
            colors.accentBackground
        }
        .widgetURL(GarminFoodDeepLink.logFoodURL)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Log Food")
        .accessibilityHint("Opens GarminFood")
    }
}

struct GarminFoodHomeWidget: Widget {
    static let kind = "com.mlcousek.garminfood.widget.home"

    var body: some WidgetConfiguration {
        // Same `kind` as the former StaticConfiguration, so placed widgets
        // stay put and start on the intent's default theme (D13).
        AppIntentConfiguration(kind: Self.kind, intent: WidgetThemeIntent.self, provider: GarminFoodHomeProvider()) { entry in
            GarminFoodHomeWidgetView(entry: entry)
        }
        .configurationDisplayName("Log Food")
        .description("A one-tap shortcut straight into GarminFood's food catalog, ready to log. Shows no live calorie data -- there is no way for a widget to read that on this account (design.md D2).")
        .supportedFamilies([.systemSmall])
    }
}

#Preview(as: .systemSmall) {
    GarminFoodHomeWidget()
} timeline: {
    GarminFoodHomeEntry(date: .now)
}
