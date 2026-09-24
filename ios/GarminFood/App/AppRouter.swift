// AppRouter.swift
//
// Where external entry points land (app-navigation spec): the selected tab,
// and a request for the Today tab to open the catalog. The shell applies
// widget links and Control requests here, so they work whichever screen was
// showing.

import Foundation
import Observation
import AppearanceKit

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

    /// A count, not a plain flag, because `FoodCatalogView` instances can
    /// legitimately nest (a meal-scoped catalog -> a Czech-database match
    /// -> its own "log anyway with a different Garmin food" fallback
    /// search, each pushing another `FoodCatalogView`). A pushed view's
    /// `.onDisappear` only fires when IT is popped, not when something is
    /// merely pushed on top of it -- so a plain boolean cleared by any one
    /// instance's `.onDisappear` could go `false` while an OUTER instance
    /// is still on screen. `isCatalogPresented`/`catalogDidAppear()`/
    /// `catalogDidDisappear()` below track how many are currently mounted.
    private var catalogPresentationCount = 0

    /// True while ANY `FoodCatalogView` is on screen, however it was
    /// reached -- directly from `TodayView`, or one level deeper via
    /// `MealDetailView`'s own independent `catalogContext`/push.
    ///
    /// 2026-09-21 bug fix: `TodayView`'s Control-driven listener used to
    /// only check its OWN local `catalogContext` before deciding whether a
    /// catalog was already open, which missed the case where the catalog
    /// was reached through `MealDetailView` instead -- `TodayView` stays
    /// mounted underneath `MealDetailView` in the same `NavigationStack`,
    /// so its listener still fired and pushed a SECOND, no-meal-preset
    /// catalog on top of the already-open, meal-scoped one. A single
    /// app-level flag (not per-view local state) is the only way to
    /// correctly answer "is a catalog open right now" regardless of which
    /// view's navigation path reached it.
    var isCatalogPresented: Bool { catalogPresentationCount > 0 }

    func catalogDidAppear() { catalogPresentationCount += 1 }
    func catalogDidDisappear() { catalogPresentationCount = max(0, catalogPresentationCount - 1) }

    /// A `garminfood://theme?c=<code>` link (a shared theme, opened from a
    /// message or its QR code) waiting for ContentView's import preview.
    /// Nothing is applied until the user taps Apply there (design D11).
    var pendingThemeImport: ThemeImportRequest?

    /// A `garminfood://` link: a widget tap, or a shared theme.
    func handle(url: URL) {
        if let code = ThemeShareCode.code(fromLink: url, scheme: GarminFoodDeepLink.scheme) {
            pendingThemeImport = ThemeImportRequest(code: code)
            return
        }
        guard let action = GarminFoodDeepLink.action(from: url) else { return }
        selectedTab = .today
        switch action {
        case .logFood:
            catalogRequested = true
        }
    }

    func applyPendingRoute() {
        guard AppNavigationBridge.shared.pendingRoute == .barcodeScanner else { return }
        selectedTab = .today
        catalogRequested = true
    }
}
