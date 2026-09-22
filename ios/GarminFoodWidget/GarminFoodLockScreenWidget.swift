// GarminFoodLockScreenWidget.swift
//
// The Lock Screen accessory widget (design.md D1/D2, REVISED 2026-09-14;
// tasks.md 18.1-18.2, superseding their original wording): `accessoryCircular`,
// `accessoryRectangular`, and `accessoryInline`, strictly a static,
// data-free "open the app" shortcut -- same reasoning as
// GarminFoodHomeWidget.swift's header, plus one more: per the
// lock-screen-and-controls spec's "Lock Screen accessory widgets are
// read-only" requirement and Apple's own documented behavior (design.md's
// Context section -- "the system doesn't perform actions unless a person
// authenticates and unlocks their device"), a button placed here would
// silently do nothing while the device is locked regardless of what data it
// could show. The actual interactive, works-while-locked surface is the
// Controls (GarminFoodWidget/Controls/), not this widget.
//
// Tapping this still opens the app like any other icon tap on a locked
// device -- which still requires unlocking, exactly as it would for any
// app icon. That is expected and is not a bug this widget could somehow
// fix (design.md's Context section again).
//
// 2026-09-22 (owner: "make him more visible"): iOS renders every Lock
// Screen accessory widget in its own fixed vibrant/tinted style -- there is
// no custom color or gradient to add here, unlike the Home Screen widget.
// What IS available and was NOT being used: `AccessoryWidgetBackground()`,
// the system-provided backing SwiftUI gives circular/rectangular accessory
// widgets specifically so their glyph reads clearly against any wallpaper
// (Apple's own built-in Lock Screen widgets use it); a larger, bolder icon
// that actually fills the circular slot instead of floating small inside
// it; a bolder, larger rectangular label; and the third Lock Screen slot,
// `accessoryInline` (the single line next to the clock/date), which this
// widget didn't support at all before -- adding it doesn't change how the
// existing two look, it just means there's now a third place on the Lock
// Screen the user can put this shortcut.

import WidgetKit
import SwiftUI

struct GarminFoodLockScreenEntry: TimelineEntry {
    let date: Date
}

struct GarminFoodLockScreenProvider: TimelineProvider {
    func placeholder(in context: Context) -> GarminFoodLockScreenEntry {
        GarminFoodLockScreenEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (GarminFoodLockScreenEntry) -> Void) {
        completion(GarminFoodLockScreenEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GarminFoodLockScreenEntry>) -> Void) {
        // `.never` -- same rationale as GarminFoodHomeWidget.swift: nothing
        // this process could ever fetch, so nothing to refresh towards.
        completion(Timeline(entries: [GarminFoodLockScreenEntry(date: .now)], policy: .never))
    }
}

struct GarminFoodLockScreenWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: "fork.knife")
                        .font(.system(size: 26, weight: .bold))
                        .widgetAccentable()
                }
            case .accessoryInline:
                Label("Log Food", systemImage: "fork.knife")
            default:
                Label("Log Food", systemImage: "fork.knife")
                    .font(.headline.weight(.bold))
                    .widgetAccentable()
            }
        }
        // No `fullColor`/tinted asset content anywhere here (tasks.md 18.2)
        // -- a bare SF Symbol renders correctly in the Lock Screen's
        // vibrant/accented modes without any extra work.
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(GarminFoodDeepLink.logFoodURL)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Log Food")
        .accessibilityHint("Opens GarminFood")
    }
}

struct GarminFoodLockScreenWidget: Widget {
    static let kind = "com.mlcousek.garminfood.widget.lockscreen"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: GarminFoodLockScreenProvider()) { _ in
            GarminFoodLockScreenWidgetView()
        }
        .configurationDisplayName("Log Food")
        .description("A Lock Screen shortcut straight into GarminFood's food catalog, ready to log. Shows no live total (design.md D2) and has no interactive element (Lock Screen widget buttons are inert while locked, per Apple's own documentation).")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

#Preview(as: .accessoryCircular) {
    GarminFoodLockScreenWidget()
} timeline: {
    GarminFoodLockScreenEntry(date: .now)
}
