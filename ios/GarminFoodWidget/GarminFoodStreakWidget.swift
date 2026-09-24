// GarminFoodStreakWidget.swift
//
// A second Home Screen widget variant (openspec/changes/add-streak-widget):
// streak-themed visual framing (a flame motif, "keep it going" copy)
// offered alongside the existing generic GarminFoodHomeWidget.swift
// shortcut, for anyone who wants their Home Screen tile to feel like it's
// cheering the streak on rather than just labeled "Log Food". This is a new
// variant, not a rewrite -- both widgets are registered side by side in
// GarminFoodWidgetBundle.swift, and the user picks whichever (or both) they
// want on their Home Screen.
//
// Same "static, data-free, tap-to-open" contract as GarminFoodHomeWidget.swift,
// for the exact same reason: this project's free Apple Developer account has
// no App Group and no Keychain Sharing (confirmed blocked on-device,
// `errSecMissingEntitlement`/-34018 -- see `add-garmin-auth-and-sync` task
// 6.4 and openspec/config.yaml's Hard Constraints, and
// GarminFoodHomeWidget.swift's own header for the full original reasoning).
// A `TimelineProvider` running in this extension's own process has no
// Garmin credential of its own to ask for the real streak count, and no
// shared storage to read the app's locally-computed one either -- so this
// widget never attempts to show a number, a flame count, or any other
// value that could be wrong. The flame glyph and "Keep your streak going" /
// "Log today" copy are deliberately generic encouragement, not a claim
// about today's actual streak state: a stale or wrong number would be worse
// than none (design.md D2, REVISED). CLAUDE.md's "Auth failures are loud;
// everything else degrades quietly" principle cuts the other way here --
// don't build something that LOOKS live but isn't.
//
// Reuses GarminFoodDeepLink.Action.logFood for its tap target, same as the
// other two widgets, rather than adding a new deep-link case: logging today
// IS what keeps the streak alive, so it is the same destination, not a
// different one (see GarminFoodDeepLink.swift's header on why `Action`
// exists for widgets that genuinely need a different destination -- this
// one doesn't).

import WidgetKit
import SwiftUI

struct GarminFoodStreakEntry: TimelineEntry {
    let date: Date
    /// This widget's own Edit Widget theme (WidgetTheme.swift, D13).
    var theme: WidgetThemeOption = .standard
}

struct GarminFoodStreakProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> GarminFoodStreakEntry {
        GarminFoodStreakEntry(date: .now)
    }

    func snapshot(for configuration: WidgetThemeIntent, in context: Context) async -> GarminFoodStreakEntry {
        GarminFoodStreakEntry(date: .now, theme: configuration.theme)
    }

    func timeline(for configuration: WidgetThemeIntent, in context: Context) async -> Timeline<GarminFoodStreakEntry> {
        // `.never`: same rationale as GarminFoodHomeWidget.swift -- this
        // process has nothing it could ever fetch, so there is nothing to
        // refresh towards. Requesting a future reload would only spend
        // WidgetKit's limited per-widget daily reload budget for a widget
        // that could never have anything new to show anyway.
        Timeline(entries: [GarminFoodStreakEntry(date: .now, theme: configuration.theme)], policy: .never)
    }
}

struct GarminFoodStreakWidgetView: View {
    let entry: GarminFoodStreakEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // The widget's own theme, not `Theme.*` (WidgetTheme.swift).
        let colors = WidgetThemeColors(option: entry.theme, colorScheme: colorScheme)
        Group {
            switch family {
            case .systemMedium:
                HStack(spacing: 14) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 44, weight: .bold))
                        .widgetAccentable()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Keep your streak going")
                            .font(.subheadline.weight(.bold))
                        Text("Log today")
                            .font(.caption)
                            .opacity(0.9)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 4)
            default:
                VStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 32, weight: .bold))
                        .widgetAccentable()
                    Text("Log today")
                        .font(.caption.weight(.semibold))
                }
            }
        }
        .foregroundStyle(colors.label)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(for: .widget) {
            // The same ember -> flame tip ramp as the app's own
            // `Theme.flameGradient`, in this widget's theme, so it reads as
            // "the streak thing" at a glance.
            colors.flameBackground
        }
        .widgetURL(GarminFoodDeepLink.logFoodURL)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Keep your streak going")
        .accessibilityHint("Opens GarminFood to log today")
    }
}

struct GarminFoodStreakWidget: Widget {
    static let kind = "com.mlcousek.garminfood.widget.streak"

    var body: some WidgetConfiguration {
        // Same `kind` as the former StaticConfiguration (D13).
        AppIntentConfiguration(kind: Self.kind, intent: WidgetThemeIntent.self, provider: GarminFoodStreakProvider()) { entry in
            GarminFoodStreakWidgetView(entry: entry)
        }
        .configurationDisplayName("Keep Your Streak")
        .description("A flame-themed shortcut straight into GarminFood's food catalog, ready to log. Shows no live streak count -- there is no way for a widget to read that on this account (design.md D2).")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview(as: .systemSmall) {
    GarminFoodStreakWidget()
} timeline: {
    GarminFoodStreakEntry(date: .now)
}

#Preview(as: .systemMedium) {
    GarminFoodStreakWidget()
} timeline: {
    GarminFoodStreakEntry(date: .now)
}
