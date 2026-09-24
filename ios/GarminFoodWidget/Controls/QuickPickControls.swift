// QuickPickControls.swift
//
// Four Controls, one per quick-pick rank (design.md D1, REVISED 2026-09-14;
// tasks.md 17.1-17.4). Placeable in Control Center, either Lock Screen
// bottom-button slot, and the Action Button (iPhone 15 Pro+ only -- tasks.md
// 17.4 / design.md Open Question 1; the Action Button binding specifically
// needs that hardware, Control Center and the Lock Screen slots do not).
//
// Each Control's label is a GENERIC rank position ("Quick Log #1"), not the
// actual food's name. This is deliberate, not a missed detail: this
// extension process has no App Group and no Keychain Sharing on this
// account (openspec/config.yaml Hard Constraints, confirmed 2026-09-14), so
// it cannot read FoodLogCore's `UsageHistoryStore`/`FoodCacheStore` (files
// in the APP's own sandboxed container) to find out which food is actually
// ranked #1 -- not even to LABEL the button, let alone log against it. The
// real food lookup happens entirely inside
// `QuickPickControlAction.performLog(rankIndex:)`
// (../../Shared/QuickPickLoggingIntents.swift), which only ever runs once
// the tap has escalated execution into the app's own process (see that
// file's header for the full reasoning and its genuinely-unconfirmed
// caveats, which apply identically to every Control below).

import SwiftUI
import WidgetKit
import AppIntents

@available(iOS 18.0, *)
struct QuickPickControl1: ControlWidget {
    static let kind = "com.mlcousek.garminfood.widget.control.quickpick1"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: LogQuickPick1Intent()) {
                Label("Quick Log #1", systemImage: "1.circle.fill")
                    .controlWidgetActionHint("Logs your most-used food")
            }
        }
        .displayName("Quick Log #1")
        // Briefly opens the app because there is no App Group on this
        // account, so the real work can only happen there (design.md D1).
        .description("Logs your most-used food. Briefly opens GarminFood to do it.")
    }
}

@available(iOS 18.0, *)
struct QuickPickControl2: ControlWidget {
    static let kind = "com.mlcousek.garminfood.widget.control.quickpick2"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: LogQuickPick2Intent()) {
                Label("Quick Log #2", systemImage: "2.circle.fill")
                    .controlWidgetActionHint("Logs your #2 most-used food")
            }
        }
        .displayName("Quick Log #2")
        .description("Logs your #2 most-used food. Briefly opens GarminFood to do it.")
    }
}

@available(iOS 18.0, *)
struct QuickPickControl3: ControlWidget {
    static let kind = "com.mlcousek.garminfood.widget.control.quickpick3"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: LogQuickPick3Intent()) {
                Label("Quick Log #3", systemImage: "3.circle.fill")
                    .controlWidgetActionHint("Logs your #3 most-used food")
            }
        }
        .displayName("Quick Log #3")
        .description("Logs your #3 most-used food. Briefly opens GarminFood to do it.")
    }
}

@available(iOS 18.0, *)
struct QuickPickControl4: ControlWidget {
    static let kind = "com.mlcousek.garminfood.widget.control.quickpick4"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: LogQuickPick4Intent()) {
                Label("Quick Log #4", systemImage: "4.circle.fill")
                    .controlWidgetActionHint("Logs your #4 most-used food")
            }
        }
        .displayName("Quick Log #4")
        .description("Logs your #4 most-used food. Briefly opens GarminFood to do it.")
    }
}
