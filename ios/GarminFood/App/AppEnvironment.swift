// AppEnvironment.swift
//
// The app's composition root: everything a screen needs, created once and
// injected with `.environment(...)`.
//
// The on-disk stores come from `AppServices.shared`, the same instances the
// in-app intents (Control, Siri) use (add-app-shell-and-meal-dashboard 1.1),
// so there is exactly one in-memory copy of each file per process.
//
// Delivery happens on foreground, right after a confirm, and in the
// background when iOS grants time (`BackgroundRefresh`, task 9.5). The
// confirm flow itself never waits on any of it.

import Foundation
import Observation
import GarminKit
import FoodLogCore
import Gamification

@MainActor
@Observable
final class AppEnvironment {
    let garminClient: GarminClient
    let authState: GarminAuthState
    let outbox: Outbox
    let reconciliation: Reconciliation
    let usageHistory: UsageHistoryStore
    let servingDefaults: ServingDefaultStore
    let customFoodStore: CustomFoodStore
    let foodCache: FoodCacheStore
    let catalogSearch: FoodCatalogSearch
    /// The Czech (Open Food Facts) search source (add-czech-food-catalog) --
    /// a completely separate network client from `garminClient`/
    /// `catalogSearch`, per proposal.md's "two sources, never silently
    /// merged" design.
    let openFoodFactsClient: OpenFoodFactsClient
    let logEntryCoordinator: LogEntryCoordinator
    let gamificationEngine: GamificationEngine
    /// The day shown on the Today tab, meal by meal.
    let dayLog: DayLogLoader
    let preferences: AppPreferences
    let profile: ProfileLoader
    let donations: LogDonations
    let router: AppRouter

    /// `true` while a drain is in flight, purely for a subtle "syncing"
    /// indicator. Never gates a user action.
    private(set) var isDraining = false

    /// Why a queued entry did not reach Garmin, when that is not an auth
    /// problem (auth has its own loud banner, per design.md D7). Garmin's
    /// own words, so a refused write can be turned into a fix.
    private(set) var lastDeliveryFailure: String?

    /// Queued entries Garmin has not accepted, and the entries themselves
    /// for the sync queue screen.
    private(set) var undeliveredCount = 0
    private(set) var undeliveredEntries: [OutboxEntry] = []

    @ObservationIgnored private var lastForegroundDay = Date()

    init() {
        let services = AppServices.shared
        let client = services.garminClient

        self.garminClient = client
        self.authState = GarminAuthState()
        self.outbox = services.outbox
        self.reconciliation = services.reconciliation
        self.usageHistory = services.usageHistory
        self.servingDefaults = services.servingDefaults
        self.customFoodStore = services.customFoodStore
        self.foodCache = services.foodCache
        self.catalogSearch = FoodCatalogSearch(searcher: client, foodCache: services.foodCache)
        self.openFoodFactsClient = OpenFoodFactsClient()
        self.logEntryCoordinator = services.logEntryCoordinator
        self.gamificationEngine = GamificationEngine(usageHistory: services.usageHistory, garminClient: client)
        self.dayLog = DayLogLoader(client: client, outbox: services.outbox, foodCache: services.foodCache)
        self.preferences = AppPreferences()
        self.profile = ProfileLoader(client: client)
        self.donations = LogDonations()
        self.router = AppRouter()

        services.logObserver = donations
        Haptics.isEnabled = preferences.hapticsEnabled
    }

    /// Launch and every return to the foreground.
    func refreshOnForeground() async {
        await authState.refresh()
        await dayLog.rollOverIfNeeded(previousToday: lastForegroundDay)
        lastForegroundDay = Date()
        await drainAndReconcile()
        // After the drain, so anything just delivered is already in the
        // numbers shown. The rest are independent reads.
        async let day: Void = dayLog.refresh()
        async let gamification: Void = gamificationEngine.refresh()
        async let goals: Void = gamificationEngine.refreshGoalStatus()
        async let garminProfile: Void = profile.refresh()
        _ = await (day, gamification, goals, garminProfile)
    }

    /// Right after an in-app confirm: the entry appears in its meal at once
    /// (local-first), the Siri donation is recorded, and delivery starts
    /// without the confirm flow waiting for it.
    func logConfirmed(food: Food?, date: String) async {
        if let food {
            await donations.didLog(food: food, date: date)
        }
        await refreshQueueState()
        await dayLog.rebuild()
        Task { await self.drainAndReconcile() }
    }

    func drainAndReconcile() async {
        guard !isDraining else { return }
        isDraining = true
        defer { isDraining = false }

        let result = await outbox.drain(using: garminClient)
        if !result.delivered.isEmpty {
            _ = await reconciliation.reconcile(delivered: result.delivered, using: garminClient)
            // Totals are read back from Garmin, so a delivery only shows
            // once the day is re-read.
            await dayLog.refresh()
            await gamificationEngine.refreshGoalStatus(for: dayLog.selectedDate)
        }

        var authFailed = true
        switch result.authOutcome {
        case .longLivedTokenExpired:
            authState.report(GarminAuthError.longLivedTokenExpired)
        case .notSignedIn:
            authState.report(GarminAuthError.notSignedIn)
        case .none:
            authFailed = false
        }

        await refreshQueueState(authFailed: authFailed)
        await dayLog.rebuild()
    }

    // MARK: - Entries

    /// Deletes an entry shown on the dashboard (design D5), and removes the
    /// Siri donation made for it.
    func delete(_ entry: MealEntry) async throws {
        let date = dayLog.dateString
        try await dayLog.delete(entry)
        await donations.entryDeleted(foodId: entry.foodId, date: date)
        await refreshQueueState()
        if entry.isSynced {
            await gamificationEngine.refreshGoalStatus(for: dayLog.selectedDate)
        }
    }

    func retryQueued(id: UUID) async {
        try? await outbox.retry(id: id)
        await refreshQueueState()
        await drainAndReconcile()
    }

    func deleteQueued(_ entry: OutboxEntry) async {
        try? await outbox.delete(id: entry.id)
        await donations.entryDeleted(foodId: entry.foodId, date: entry.date)
        await refreshQueueState()
        await dayLog.rebuild()
    }

    // MARK: - Account

    /// Removes the stored Garmin credentials. Queued entries stay queued
    /// and deliver after the next sign-in.
    func signOut() async {
        await garminClientTokenProvider.signOut()
        authState.markSignedOut()
        profile.clear()
    }

    private var garminClientTokenProvider: TokenProvider { .shared }

    // MARK: - Lifecycle

    func didEnterBackground() {
        if undeliveredCount > 0 {
            BackgroundRefresh.schedule()
        } else {
            BackgroundRefresh.cancel()
        }
    }

    func preferencesChanged() {
        Haptics.isEnabled = preferences.hapticsEnabled
    }

    // MARK: - Private

    /// `pendingCount()` only counts entries due NOW (a failed attempt moves
    /// an entry into a backoff window), and `DrainResult.failed` only lists
    /// entries out of retries, so neither answers "what hasn't Garmin
    /// accepted". This reads every entry that isn't `.sent`.
    private func refreshQueueState(authFailed: Bool = false) async {
        let pending = await outbox.pendingCount()
        authState.updatePendingCount(pending)

        let undelivered = await outbox.allEntries().filter { $0.state != .sent }
        undeliveredEntries = undelivered
        undeliveredCount = undelivered.count

        // Auth failures have their own banner. Newest first, since that's
        // the attempt the user just made.
        var failure: String?
        if !authFailed {
            for entry in undelivered.reversed() {
                if let error = entry.lastError, !error.hasPrefix("auth:") {
                    failure = error
                    break
                }
            }
        }
        lastDeliveryFailure = failure
    }
}
