// GarminFoodWidgetBundle.swift
//
// The widget extension's entry point (`GarminFoodWidgetExtension`, see
// ios/project.yml). Task 6.4's throwaway Keychain-sharing spike widget
// (formerly KeychainCheckWidget.swift, now removed) is gone -- its job was
// answering one empirical question, and its answer (no App Group, no
// Keychain Sharing on this free-tier account -- `errSecMissingEntitlement`
// / -34018, confirmed live) is recorded in openspec/config.yaml's Hard
// Constraints and is exactly what shaped every real widget/Control below:
// none of them can ever show live data (design.md D2), and the logging
// Controls must foreground the app rather than run invisibly (design.md D1).
//
// Widgets and Controls are declared together in this one `WidgetBundle`,
// per Apple's WWDC24 "Extend your app's controls across the system"
// session, which demonstrates adding a `ControlWidget`-conforming type
// directly into an existing `WidgetBundle`'s `body` alongside ordinary
// `Widget`s -- no separate extension/target needed for Controls, matching
// design.md's own framing ("the same API surfaces in Control Center...
// from one implementation") and ios/project.yml's comment that "a Control
// can live in the same extension bundle."
//
// Controls are iOS 18+ only (design.md's Context section); the `Widget`
// entries are not, so they're listed unconditionally and the Controls are
// gated behind `if #available` rather than bumping this target's whole
// deployment target off of 17.0.

import WidgetKit
import SwiftUI

@main
struct GarminFoodWidgetBundle: WidgetBundle {
    var body: some Widget {
        GarminFoodHomeWidget()
        GarminFoodLockScreenWidget()

        if #available(iOS 18.0, *) {
            QuickPickControl1()
            QuickPickControl2()
            QuickPickControl3()
            QuickPickControl4()
            ScanBarcodeControl()
        }
    }
}
