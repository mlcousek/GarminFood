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
    let mealPresetStore: MealPresetStore
    let foodCache: FoodCacheStore
    let fastingStore: FastingSessionStore
    let catalogSearch: FoodCatalogSearch
    /// The Czech (Open Food Facts) search source (add-czech-food-catalog) --
    /// a completely separate network client from `garminClient`/
    /// `catalogSearch`, per proposal.md's "two sources, never silently
    /// merged" design.
    let openFoodFactsClient: OpenFoodFactsClient
    let logEntryCoordinator: LogEntryCoordinator
    /// add-weight-tracking: mirrors `outbox`/`logEntryCoordinator` above,
    /// plus a loader (`weightLoader`) since, unlike the food dashboard,
    /// there's no existing `dayLog`-shaped object weight can piggyback on.
    let weightOutbox: WeightOutbox
    let weightLogCoordinator: WeightLogCoordinator
    let weightLoader: WeightLoader
    /// add-hydration-tracking: mirrors the weight trio directly above.
    let hydrationOutbox: HydrationOutbox
    let hydrationLogCoordinator: HydrationLogCoordinator
    let hydrationLoader: HydrationLoader
    let gamificationEngine: GamificationEngine
    /// The day shown on the Today tab, meal by meal.
    let dayLog: DayLogLoader
    let preferences: AppPreferences
    let notificationPreferences: NotificationPreferencesStore
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
        self.mealPresetStore = services.mealPresetStore
        self.foodCache = services.foodCache
        self.fastingStore = services.fastingStore
        self.catalogSearch = FoodCatalogSearch(searcher: client, foodCache: services.foodCache)
        self.openFoodFactsClient = OpenFoodFactsClient()
        self.logEntryCoordinator = services.logEntryCoordinator
        self.weightOutbox = services.weightOutbox
        self.weightLogCoordinator = services.weightLogCoordinator
        self.weightLoader = WeightLoader(store: services.weightStore, outbox: services.weightOutbox)
        self.hydrationOutbox = services.hydrationOutbox
        self.hydrationLogCoordinator = services.hydrationLogCoordinator
        self.hydrationLoader = HydrationLoader(store: services.hydrationStore, outbox: services.hydrationOutbox)
        self.gamificationEngine = GamificationEngine(usageHistory: services.usageHistory, garminClient: client)
        self.dayLog = DayLogLoader(client: client, outbox: services.outbox, foodCache: services.foodCache)
        self.preferences = AppPreferences()
        self.notificationPreferences = NotificationPreferencesStore()
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
        async let weight: Void = weightLoader.refresh()
        async let hydration: Void = hydrationLoader.refresh()
        _ = await (day, gamification, goals, garminProfile, weight, hydration)
        await syncNotifications()
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
        await syncNotifications()
        Task { await self.drainAndReconcile() }
    }

    /// Right after logging a weigh-in (AddWeightSheet's own confirm
    /// action): the entry appears in the history list at once (local-first,
    /// `WeightLogCoordinator.logWeight` already committed it before this is
    /// called), and delivery starts without the sheet waiting for it.
    func weightLogged() async {
        await weightLoader.refresh()
        Task { await self.drainAndReconcile() }
    }

    /// Deletes a weigh-in shown on the Weight screen (WeightLogCoordinator.
    /// deleteWeight's own doc comment covers what this does and doesn't
    /// undo on Garmin's side).
    func deleteWeight(_ entry: WeightEntry) async throws {
        try await weightLogCoordinator.deleteWeight(entry)
        await weightLoader.refresh()
    }

    /// Right after logging a drink (AddHydrationSheet's own confirm
    /// action) -- same reasoning as `weightLogged()`.
    func hydrationLogged() async {
        await hydrationLoader.refresh()
        Task { await self.drainAndReconcile() }
    }

    /// Deletes a hydration entry shown on the Hydration screen
    /// (HydrationLogCoordinator.deleteHydration's own doc comment covers
    /// what this does and doesn't undo on Garmin's side).
    func deleteHydration(_ entry: HydrationEntry) async throws {
        try await hydrationLogCoordinator.deleteHydration(entry)
        await hydrationLoader.refresh()
    }

    /// Day navigation, routed through here rather than calling `dayLog`
    /// directly (as `TodayView` did until 2026-09-17) so goal status gets
    /// recomputed for whichever day is actually being looked at. Without
    /// this, `refreshGoalStatus` only ever ran for "today" (on foreground,
    /// after a delivery, or after a delete) -- viewing a past day and
    /// adding or removing something there left that day's `DailyGoalStatus`
    /// stale or missing, so a goal-hitting challenge or the Progress tab's
    /// goal history could silently never reflect it.
    func stepDay(byDays days: Int) async {
        await dayLog.step(byDays: days)
        await gamificationEngine.refreshGoalStatus(for: dayLog.selectedDate)
    }

    func goToToday() async {
        await dayLog.goToToday()
        await gamificationEngine.refreshGoalStatus(for: dayLog.selectedDate)
    }

    func drainAndReconcile() async {
        guard !isDraining else { return }
        isDraining = true
        defer { isDraining = false }

        // Weight has its own outbox (WeightSync.swift's header explains
        // why) but shares this same foreground/post-confirm drain trigger
        // -- no reconciliation step follows it (unlike the food outbox
        // below), since this app doesn't read weigh-ins back from Garmin to
        // merge against local state (WeightLogCoordinator.swift's header).
        let weightResult = await weightOutbox.drain(using: garminClient)
        if !weightResult.delivered.isEmpty || !weightResult.failed.isEmpty {
            await weightLoader.refresh()
        }

        // Same reasoning as the weight drain above -- its own outbox, no
        // reconciliation step (HydrationLogCoordinator.swift's header).
        let hydrationResult = await hydrationOutbox.drain(using: garminClient)
        if !hydrationResult.delivered.isEmpty || !hydrationResult.failed.isEmpty {
            await hydrationLoader.refresh()
        }

        let result = await outbox.drain(using: garminClient)

        // Reconciles every CURRENTLY `.sent` entry, not just what this
        // cycle's drain delivered. `Reconciliation.reconcile` can leave an
        // entry `.sent` and unreconciled if re-reading that day's log fails
        // right after a successful write (a network hiccup, not an error
        // `drain()` itself would retry -- `.sent` entries are invisible to
        // `drain()`, which only ever looks at `.pending` ones). Before this,
        // such an entry stayed `.sent` forever: never removed, never
        // retried. That used to be harmless -- the old Home screen only
        // ever showed Garmin's own read-back total. `MealDashboard` changed
        // that: it shows an unmatched `.sent` entry as a "syncing" row and
        // adds its calories on top of Garmin's total, specifically to cover
        // the brief legitimate window between a delivery and its re-read.
        // Left permanently unreconciled, that window never closes, so a
        // real Garmin total gets a phantom entry added on top of it forever.
        // Re-attempting every `.sent` entry on every drain is what actually
        // closes it: `result.delivered` (fresh from THIS drain) already
        // has `.sent` state by the time this line runs, so it's a subset.
        let sentEntries = await outbox.allEntries().filter { $0.state == .sent }
        if !sentEntries.isEmpty {
            _ = await reconciliation.reconcile(delivered: sentEntries, using: garminClient)
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

    /// 2026-09-21 bug fix: this used to swallow a write failure with `try?`
    /// and give the user no feedback at all -- the one screen whose entire
    /// job is "make a failed entry actionable again" was the one place a
    /// failed retry/delete went completely silent, unlike every other
    /// delete path in the app (e.g. `DayLogLoader.delete`), which surfaces
    /// its error. Now propagates so `SyncQueueView` can show it.
    func retryQueued(id: UUID) async throws {
        try await outbox.retry(id: id)
        await refreshQueueState()
        await drainAndReconcile()
    }

    func deleteQueued(_ entry: OutboxEntry) async throws {
        try await outbox.delete(id: entry.id)
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

    // MARK: - Notifications

    func requestNotificationPermissionIfNeeded() async {
        await NotificationScheduler.shared.requestAuthorizationIfNeeded()
    }

    func setBreakfastReminder(_ setting: ReminderSetting) {
        notificationPreferences.setBreakfastReminder(setting)
        Task { await syncNotifications() }
    }

    func setLunchReminder(_ setting: ReminderSetting) {
        notificationPreferences.setLunchReminder(setting)
        Task { await syncNotifications() }
    }

    func setDinnerReminder(_ setting: ReminderSetting) {
        notificationPreferences.setDinnerReminder(setting)
        Task { await syncNotifications() }
    }

    func setStreakReminder(_ setting: ReminderSetting) {
        notificationPreferences.setStreakReminder(setting)
        Task { await syncNotifications() }
    }

    func setDailyChallengeReminder(_ setting: ReminderSetting) {
        notificationPreferences.setDailyChallengeReminder(setting)
        Task { await syncNotifications() }
    }

    func setFastingReminder(_ setting: FastingReminderSetting) {
        notificationPreferences.setFastingReminder(setting)
        Task { await syncNotifications() }
    }

    /// Re-plans and re-syncs local reminders against current state -- see
    /// `NotificationScheduler`'s header for why this needs to re-run
    /// whenever something that could change the plan happens (foreground,
    /// a confirm, a setting change), rather than being scheduled once.
    /// The meal/streak/challenge half is skipped while a past day is being
    /// viewed: today's actual logged-meal state lives in `dayLog.dashboard`
    /// only while `dayLog.isToday`, and a stale/empty read would
    /// incorrectly re-arm an already-logged meal's reminder -- the next
    /// time the user is back on today, this runs again with the real
    /// state. The fasting half has no such day dependency (it's driven by
    /// wall-clock time against the active session, not by which day's food
    /// log is on screen), so it always runs.
    func syncNotifications() async {
        if dayLog.isToday {
            let mealsLoggedToday = Set(dayLog.dashboard.sections.filter { !$0.entries.isEmpty }.map(\.mealType))
            await NotificationScheduler.shared.sync(
                preferences: notificationPreferences.preferences,
                mealsLoggedToday: mealsLoggedToday,
                isStreakAtRiskToday: gamificationEngine.streakStatus.isAtRiskToday
            )
        }
        let activeSession = await fastingStore.active()
        await NotificationScheduler.shared.syncFastingReminder(
            setting: notificationPreferences.preferences.fastingReminder,
            activeSession: activeSession
        )
    }

    // MARK: - Fasting

    /// Thin wrappers around `fastingStore`, mirroring the entry/delete
    /// methods above: the store call itself, plus the one side effect every
    /// mutation needs (re-syncing the fasting reminder, since starting/
    /// ending a fast changes what -- if anything -- should be scheduled).
    /// Reads (`fastingStore.active()`/`.history()`) don't need a wrapper --
    /// views call those directly, same as `environment.mealPresetStore.all()`.
    @discardableResult
    func startFasting(protocolKind: FastingProtocol, at date: Date = Date()) async throws -> FastingSession {
        let session = try await fastingStore.start(FastingSession(protocolKind: protocolKind, startedAt: date))
        await syncNotifications()
        return session
    }

    func breakFast(at date: Date = Date()) async throws {
        try await fastingStore.endFastingPhase(at: date)
        await syncNotifications()
    }

    @discardableResult
    func endFastingSession(at date: Date = Date()) async throws -> FastingSession {
        let session = try await fastingStore.endActiveSession(at: date)
        await syncNotifications()
        return session
    }

    func cancelActiveFast() async throws {
        try await fastingStore.cancelActiveSession()
        await syncNotifications()
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
