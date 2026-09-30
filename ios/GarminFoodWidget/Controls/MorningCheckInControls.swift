// MorningCheckInControls.swift
//
// Three Controls for the 4:00 morning check (add-training-checkins design
// D7; decision T6): Green, Amber, Red. Placeable in Control Center, the
// Lock Screen's bottom slots and the Action Button, like the quick-pick
// Controls. Each is static -- the extension can't read the app's plan on a
// free account (no App Group) -- and its action,
// `MorningCheckInIntent(light:)` (Shared/MorningCheckInIntents.swift),
// opens the app and records `checkin.morning` there for the current
// training day.
//
// Letter and shape as well as colour, as on Today (G circle, A triangle,
// R square): the symbols are the design system's traffic-light shapes, and
// the labels say the colour in words.
//
// iOS 18+ (Controls), gated in GarminFoodWidgetBundle. Kinds are stable ids
// (`...control.checkin.green|amber|red`); renaming one removes the Control a
// user placed.

import SwiftUI
import WidgetKit
import AppIntents

@available(iOS 18.0, *)
struct MorningCheckInGreenControl: ControlWidget {
    static let kind = "com.mlcousek.garminfood.widget.control.checkin.green"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: MorningCheckInIntent(light: .greenLight)) {
                Label("Check-in: Green", systemImage: "circle.fill")
            }
        }
        .displayName("Check-in: Green")
        .description("Records a green morning check-in. Briefly opens Jirka's Arc to do it.")
    }
}

@available(iOS 18.0, *)
struct MorningCheckInAmberControl: ControlWidget {
    static let kind = "com.mlcousek.garminfood.widget.control.checkin.amber"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: MorningCheckInIntent(light: .amberLight)) {
                Label("Check-in: Amber", systemImage: "triangle.fill")
            }
        }
        .displayName("Check-in: Amber")
        .description("Records an amber morning check-in. Briefly opens Jirka's Arc to do it.")
    }
}

@available(iOS 18.0, *)
struct MorningCheckInRedControl: ControlWidget {
    static let kind = "com.mlcousek.garminfood.widget.control.checkin.red"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: MorningCheckInIntent(light: .redLight)) {
                Label("Check-in: Red", systemImage: "square.fill")
            }
        }
        .displayName("Check-in: Red")
        .description("Records a red morning check-in. Briefly opens Jirka's Arc to do it.")
    }
}
