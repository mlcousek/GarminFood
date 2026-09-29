// AppRouter.swift
//
// Where external entry points land (app-navigation spec): the selected tab,
// and a request for the Today tab to open the catalog. The shell applies
// widget links and Control requests here, so they work whichever screen was
// showing. The tab at launch is the user's start tab (Settings ->
// Appearance -> Layout); those entry points still take priority over it.
//
// rebrand-to-jirkas-arc D6/D8: the tab set depends on the experience
// (food-first: Today, Progress, Profile; training: Today, Plan, Progress,
// Profile). Which tab a route lands on, the start-tab fallback and the
// correction when the experience changes are AppearanceKit's pure
// `AppShell` rules; this class only applies them. `Tab` is AppShell's
// `ShellTab`, so there is one tab enum, not two to keep in step.

import Foundation
import Observation
import AppearanceKit

@MainActor
@Observable
final class AppRouter {
    typealias Tab = ShellTab

    var selectedTab: Tab

    /// A `garminfood://plan?date=YYYY-MM-DD` link's day, kept for the Plan
    /// tab to consume (add-training-today-and-plan). Set only when the link
    /// opened Plan with a valid date; `nil` otherwise.
    var pendingPlanDate: DateComponents?

    /// The current experience (AppEnvironment.experience), read when a
    /// route arrives.
    @ObservationIgnored private let experience: @MainActor () -> AppExperience

    /// `startTab` is the user's "Start on" choice (add-themes-and-layout
    /// task 4.3), already resolved for the experience
    /// (`LayoutStore.resolvedStartTab`), read once at launch. It only sets
    /// the initial selection: a widget link or Control route arriving after
    /// launch (`handle(url:)`, `applyPendingRoute()`) still switches to the
    /// tab it needs.
    init(startTab: StartTab = .default, experience: @escaping @MainActor () -> AppExperience = { .foodFirst }) {
        self.experience = experience
        selectedTab = AppShell.tab(for: startTab)
    }

    /// The experience changed (the preview toggle, later the vault
    /// connection): keep the selected tab if the new set shows it, else
    /// Today (design D8).
    func experienceDidChange(to experience: AppExperience) {
        let corrected = AppShell.correctedSelection(selectedTab, experience: experience)
        if corrected != selectedTab { selectedTab = corrected }
        if !AppShell.shows(.plan, in: experience) { pendingPlanDate = nil }
    }

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

    /// A `garminfood://` link: a widget tap, a `plan` link, or a shared
    /// theme.
    func handle(url: URL) {
        if let code = ThemeShareCode.code(fromLink: url, scheme: GarminFoodDeepLink.scheme) {
            pendingThemeImport = ThemeImportRequest(code: code)
            return
        }
        guard let action = GarminFoodDeepLink.action(from: url) else { return }
        switch action {
        case .logFood:
            selectedTab = AppShell.destination(for: .logFood, experience: experience())
            catalogRequested = true
        case .plan:
            let destination = AppShell.destination(for: .plan, experience: experience())
            selectedTab = destination
            if destination == .plan {
                pendingPlanDate = AppShell.planLinkDate(
                    GarminFoodDeepLink.queryValue(GarminFoodDeepLink.planDateQueryItem, in: url)
                )
            }
        }
    }

    /// The barcode Control: Today plus the catalog, in both experiences.
    func applyPendingRoute() {
        guard AppNavigationBridge.shared.pendingRoute == .barcodeScanner else { return }
        selectedTab = AppShell.destination(for: .logFood, experience: experience())
        catalogRequested = true
    }
}
