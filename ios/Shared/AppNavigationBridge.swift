// AppNavigationBridge.swift
//
// A tiny, in-memory hand-off point from an App Intent running inside the
// app's OWN process (e.g. `OpenBarcodeScannerIntent.perform()`, once the
// system has foregrounded the app for it) to the app's own SwiftUI view
// tree, which observes it and reacts by presenting the right screen.
//
// This is NOT a replacement for, or an alternative route into, any
// GarminKit/FoodLogCore store -- it holds no durable state, is never
// persisted, and is never read by the widget extension process for
// anything meaningful. It is compiled into BOTH targets (it lives in
// `Shared`, per project.yml) only because the intent TYPES that write to it
// (Shared/OpenBarcodeScannerIntent.swift) must themselves be visible to the
// extension, to be named inside a `ControlWidgetButton`/Control
// declaration -- see that file's header. Reading/writing this singleton is
// safe as an ordinary in-process value because, by construction, both the
// intent's `perform()` and the app's own views only ever meaningfully run
// on the SAME process: the app's. (There is no world in which the
// extension process both sets this AND has a SwiftUI view tree reading it
// -- it has no such view tree at all outside its own widgets/Controls.)
//
// No SwiftUI/UIKit import -- matches GarminKit's `AuthState.swift`
// convention exactly (`@Observable` comes from the platform `Observation`
// module, not SwiftUI).

import Foundation
import Observation

@MainActor
@Observable
final class AppNavigationBridge {
    static let shared = AppNavigationBridge()

    enum PendingRoute: Equatable {
        case barcodeScanner
    }

    private(set) var pendingRoute: PendingRoute?

    private init() {}

    func request(_ route: PendingRoute) {
        pendingRoute = route
    }

    /// Reads and clears in one step, so presenting the destination screen
    /// can never re-trigger itself on a later, unrelated view update.
    @discardableResult
    func consume() -> PendingRoute? {
        defer { pendingRoute = nil }
        return pendingRoute
    }
}
