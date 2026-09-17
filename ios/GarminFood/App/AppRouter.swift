// AppRouter.swift
//
// Where external entry points land (app-navigation spec): the selected tab,
// and a request for the Today tab to open the catalog. The shell applies
// widget links and Control requests here, so they work whichever screen was
// showing.

import Foundation
import Observation

@MainActor
@Observable
final class AppRouter {
    enum Tab: Hashable {
        case today
        case progress
        case profile
    }

    var selectedTab: Tab = .today

    /// Set when the barcode Control fired. The Today tab pushes the catalog,
    /// and the catalog consumes `AppNavigationBridge`'s route and opens the
    /// scanner. That is the scanner flow that already exists, reached from
    /// any tab instead of only from the catalog.
    var catalogRequested = false

    /// A `garminfood://` link. The widget's only link opens Today.
    func handle(url: URL) {
        guard url.scheme == GarminFoodDeepLink.scheme else { return }
        selectedTab = .today
    }

    func applyPendingRoute() {
        guard AppNavigationBridge.shared.pendingRoute == .barcodeScanner else { return }
        selectedTab = .today
        catalogRequested = true
    }
}
