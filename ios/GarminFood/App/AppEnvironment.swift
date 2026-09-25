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
    /// add-standalone-mode D3: every nutrition READ the day log, Trends,
    /// gamification and copy-meal make. `AppServices.nutritionReader`: the
    /// very same `garminClient` in Garmin mode, the local food log while
    /// the effective data mode is standalone (wave 2).
    let nutritionReader: any NutritionLogReading
    let authState: GarminAuthState
    let outbox: Outbox
    let reconciliation: Reconciliation
    let usageHistory: UsageHistoryStore
    let servingDefaults: ServingDefaultStore
    let customFoodStore: CustomFoodStore
    let mealPresetStore: MealPresetStore
    let foodCache: FoodCacheStore
    /// Retired manual-fasting sessions (redesign-fasting-schedule) -- read
    /// once by `migrateLegacyFastingIfNeeded()`, never written.
    let fastingStore: FastingSessionStore
    /// add-favorite-foods: purely local, see FavoriteFood.swift's header.
    let favoriteFoodStore: FavoriteFoodStore
    /// add-day-notes: purely local, see DayNote.swift's header. Written by
    /// `DayNoteCard` (Today), read by `TrendsView` for its chart markers.
    let dayNoteStore: DayNoteStore
    /// rebuild-food-search: the one food search -- the user's own foods,
    /// Garmin and Open Food Facts, ranked together (FoodSearchEngine.swift).
    /// One instance per app process, so its remote term cache is shared by
    /// every catalog screen and the OFF -> Garmin match flow.
    let foodSearchEngine: FoodSearchEngine
    /// add-standalone-mode D5: the catalog without Garmin -- your own foods
    /// (including Open Food Facts products you've logged), the offline
    /// Czech index and live Open Food Facts (`FoodSearchEngine.standard(
    /// garmin: nil)`). Built once like `foodSearchEngine`; screens ask for
    /// `catalogSearchEngine`, which picks one per the current mode.
    let standaloneFoodSearchEngine: FoodSearchEngine
    /// add-offline-czech-food-index: the in-memory Czech offline index that
    /// `foodSearchEngine` and the barcode fallback read (never waiting on
    /// it), and the loader that keeps it downloaded and shows its status in
    /// Settings (OfflineIndexLoader.swift).
    let offlineIndex: OfflineFoodIndexHolder
    let offlineIndexLoader: OfflineIndexLoader
    let logEntryCoordinator: ModeRoutingFoodLogging
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
    /// sync-weight-hydration-with-garmin: the Garmin READS behind both
    /// loaders above (weigh-ins, water total, weight goal), cached in
    /// `AppServices.garminHealthCache`. Run by `refreshGarminHealth(force:)`
    /// only -- never on a confirm/save path.
    let garminHealthSync: GarminHealthSync
    /// add-trends-and-insights: the Trends screen's macro-trend data. Unlike
    /// every loader above, this has no local store/outbox of its own to
    /// mirror -- `calorieSummaryDaily` is a single stateless Garmin read
    /// over a date range, so there is nothing to persist. Deliberately NOT
    /// refreshed in `refreshOnForeground()` below -- see `MacroTrendLoader`'s
    /// own header for why it loads only when the Trends screen is open.
    let trendsLoader: MacroTrendLoader
    let gamificationEngine: GamificationEngine
    /// add-gamification-signals D4: local caches behind the gamification
    /// signals (`AppServices`), and the foreground-only Garmin reads that
    /// fill the activity cache / first name (`GamificationSignalsSync`).
    let dayLogDigestStore: DayLogDigestStore
    let activityCacheStore: ActivityCacheStore
    let foodProvenanceStore: FoodProvenanceStore
    let gamificationSignalsSync: GamificationSignalsSync
    /// The day shown on the Today tab, meal by meal.
    let dayLog: DayLogLoader
    let preferences: AppPreferences
    /// add-themes-and-layout: the look (theme, style, custom accent) and
    /// the root that pushes it into `ThemeRuntime` (ThemeStore.swift).
    let themeStore: ThemeStore
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
    /// sync-weight-hydration-with-garmin: weigh-in adds/deletes and drinks/
    /// corrections Garmin hasn't accepted, shown in the sync queue next to
    /// food entries (spec: a failed delete "is visible in the sync queue").
    private(set) var undeliveredWeightEntries: [WeightOutboxEntry] = []
    private(set) var undeliveredHydrationEntries: [HydrationOutboxEntry] = []

    /// "Today" as of the last foreground or day-change check -- what
    /// `DayLogLoader.rollOverIfNeeded` compares against, so the Today tab
    /// only follows the calendar when it was showing the day that just
    /// ended (a past day picked on purpose stays put).
    @ObservationIgnored private var lastForegroundDay = Date()
    /// One Garmin health read at a time (foreground, screen appear, and a
    /// post-delivery refresh can all ask at once).
    @ObservationIgnored private var isRefreshingGarminHealth = false
    @ObservationIgnored private var isBackfillingUsageMeals = false
    @ObservationIgnored private var garminHealthRefreshQueued = false
    @ObservationIgnored private var garminHealthRefreshQueuedForce = false

    init() {
        let services = AppServices.shared
        let client = services.garminClient
        let preferences = AppPreferences()

        self.garminClient = client
        let reader: any NutritionLogReading = services.nutritionReader
        self.nutritionReader = reader
        self.authState = GarminAuthState()
        self.outbox = services.outbox
        self.reconciliation = services.reconciliation
        self.usageHistory = services.usageHistory
        self.servingDefaults = services.servingDefaults
        self.customFoodStore = services.customFoodStore
        self.mealPresetStore = services.mealPresetStore
        self.foodCache = services.foodCache
        self.fastingStore = services.fastingStore
        self.favoriteFoodStore = services.favoriteFoodStore
        self.dayNoteStore = services.dayNoteStore
        self.foodSearchEngine = FoodSearchEngine.standard(
            garmin: client,
            customFoods: services.customFoodStore,
            favorites: services.favoriteFoodStore,
            foodCache: services.foodCache,
            usageHistory: services.usageHistory,
            offlineIndex: services.offlineIndex
        )
        self.standaloneFoodSearchEngine = FoodSearchEngine.standard(
            garmin: nil,
            customFoods: services.customFoodStore,
            favorites: services.favoriteFoodStore,
            foodCache: services.foodCache,
            usageHistory: services.usageHistory,
            offlineIndex: services.offlineIndex
        )
        self.offlineIndex = services.offlineIndex
        self.offlineIndexLoader = OfflineIndexLoader(store: services.offlineIndexStore, preferences: preferences)
        self.logEntryCoordinator = services.logEntryCoordinator
        self.weightOutbox = services.weightOutbox
        self.weightLogCoordinator = services.weightLogCoordinator
        self.weightLoader = WeightLoader(store: services.weightStore, outbox: services.weightOutbox, cache: services.garminHealthCache, preferences: preferences)
        self.hydrationOutbox = services.hydrationOutbox
        self.hydrationLogCoordinator = services.hydrationLogCoordinator
        self.hydrationLoader = HydrationLoader(store: services.hydrationStore, outbox: services.hydrationOutbox, cache: services.garminHealthCache, preferences: preferences)
        self.garminHealthSync = services.garminHealthSync
        self.trendsLoader = MacroTrendLoader(client: reader)
        self.dayLogDigestStore = services.dayLogDigestStore
        self.activityCacheStore = services.activityCacheStore
        self.foodProvenanceStore = services.foodProvenanceStore
        self.gamificationSignalsSync = GamificationSignalsSync(client: client, activityCache: services.activityCacheStore)
        let featureHost = FeatureHost(sources: FeatureHost.Sources(
            usageHistory: services.usageHistory,
            foodCache: services.foodCache,
            dayLogDigests: services.dayLogDigestStore,
            activityCache: services.activityCacheStore,
            provenance: services.foodProvenanceStore,
            hydration: services.hydrationStore,
            garminHealthCache: services.garminHealthCache,
            dayNotes: services.dayNoteStore,
            preferences: preferences
        ))
        self.gamificationEngine = GamificationEngine(
            usageHistory: services.usageHistory,
            garminClient: reader,
            featureHost: featureHost,
            dayLogDigestStore: services.dayLogDigestStore
        )
        self.dayLog = DayLogLoader(
            reader: reader,
            client: client,
            outbox: services.outbox,
            foodCache: services.foodCache,
            coordinator: services.logEntryCoordinator,
            digestStore: services.dayLogDigestStore,
            activityCache: services.activityCacheStore,
            dataMode: AppServices.currentDataMode
        )
        self.preferences = preferences
        self.themeStore = ThemeStore()
        self.notificationPreferences = NotificationPreferencesStore()
        self.profile = ProfileLoader(client: client)
        self.donations = LogDonations()
        self.router = AppRouter()

        services.logObserver = donations
        Haptics.isEnabled = preferences.hapticsEnabled
    }

    /// Launch and every return to the foreground.
    func refreshOnForeground() async {
        // Unstructured on purpose: loading the Czech offline index and its
        // at-most-daily update check must never hold up anything below or
        // any search (add-offline-czech-food-index D3).
        let offlineIndexLoader = self.offlineIndexLoader
        Task { await offlineIndexLoader.loadAndCheckIfDue() }
        await classifyDataModeIfNeeded()
        await migrateLegacyFastingIfNeeded()
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
        // Weight + water: Garmin is the source of truth
        // (sync-weight-hydration-with-garmin); this reads Garmin into the
        // cache and then reloads both loaders from it.
        async let weightAndWater: Void = refreshGarminHealth()
        async let signalReads: Void = refreshGamificationSignals()
        _ = await (day, gamification, goals, garminProfile, weightAndWater, signalReads)
        await syncNotifications()
        // Low priority and never awaited by anything the user sees.
        Task(priority: .background) { await self.backfillUsageMealsIfNeeded() }
    }

    /// The calendar day changed while the app stayed open (midnight, or a
    /// clock/time-zone change -- `ContentView` observes both). Foreground
    /// is the only other place the day rolls over, so without this, after
    /// 00:00 the Today tab kept showing yesterday: "Add food" pre-filled
    /// yesterday's date and the today-only "Log again"/"Log a meal"
    /// shelves disappeared. Deliberately light -- just what depends on
    /// "today": the rollover (which reloads the new day), the streak/
    /// challenge state, and the today-based reminders. Same
    /// `lastForegroundDay` bookkeeping as `refreshOnForeground`; a second
    /// signal for the same midnight (both notifications, or a foreground
    /// arriving at once) finds nothing left to roll over.
    func dayDidChange() async {
        await dayLog.rollOverIfNeeded(previousToday: lastForegroundDay)
        lastForegroundDay = Date()
        await gamificationEngine.refresh()
        await syncNotifications()
    }

    /// add-gamification-signals 7.3: the read-only activities / first-name
    /// reads, throttled inside `GamificationSignalsSync` (30 min / daily).
    /// Foreground only -- never a confirm path. An auth failure goes to the
    /// loud banner; anything else was already logged quietly.
    private func refreshGamificationSignals() async {
        if let authError = await gamificationSignalsSync.refreshIfDue() {
            authState.report(authError)
        }
    }

    /// One-time (until it completes): fills in the meal of usage events
    /// recorded before `UsageEvent.mealType` existed, from Garmin's day logs
    /// for the last few weeks, so "Usual for <meal>" isn't empty after the
    /// upgrade (`UsageMealBackfill`). Read-only against Garmin (the same
    /// confirmed day-log route the Today tab uses). Any read failure --
    /// offline, expired sign-in -- just stops it quietly; the next
    /// foreground tries again, and the regular refresh already surfaces an
    /// auth problem loudly.
    private func backfillUsageMealsIfNeeded() async {
        let doneKey = "usageMealBackfill.v1.done"
        guard !UserDefaults.standard.bool(forKey: doneKey), !isBackfillingUsageMeals else { return }
        isBackfillingUsageMeals = true
        defer { isBackfillingUsageMeals = false }

        let days = UsageMealBackfill.daysNeedingBackfill(await usageHistory.all())
        var logs: [String: DailyFoodLog] = [:]
        for day in days {
            if let cached = dayLog.cachedFoodLogs[day] {
                logs[day] = cached
                continue
            }
            do {
                if let log = try await garminClient.dailyFoodLog(date: day) {
                    logs[day] = log
                }
            } catch {
                DiagnosticsLog.log(.info, category: "UsageMealBackfill", "Stopped after \(logs.count)/\(days.count) days, will retry next foreground: \(error)")
                return
            }
        }
        do {
            let filled = try await usageHistory.applyMealBackfill(logs)
            DiagnosticsLog.log(.info, category: "UsageMealBackfill", "Filled the meal of \(filled) older usage events from \(logs.count) Garmin day logs.")
            UserDefaults.standard.set(true, forKey: doneKey)
        } catch {
            DiagnosticsLog.log(.warning, category: "UsageMealBackfill", "Couldn't save the backfill, will retry: \(error)")
        }
    }

    /// Reads weigh-ins, today's water and the weight goal from Garmin into
    /// the cache, then reloads both loaders (sync-weight-hydration-with-
    /// garmin task 3.1). Called on foreground (which covers the Today card),
    /// when the Weight/Water screens appear, on pull-to-refresh there
    /// (`force`: re-reads the whole 90-day history and the goal), and after
    /// a weight/water delivery. Never from a confirm/save path. The loaders
    /// render from the cache first, so nothing waits on this; a failure
    /// only sets their quiet "couldn't refresh" flag, except an expired
    /// sign-in, which goes to the loud auth banner.
    ///
    /// One read at a time. A request arriving while one runs is not
    /// dropped: it queues exactly one more pass (keeping `force` if any
    /// queued request had it). That matters after a delivery -- a read that
    /// started before the POST landed can't contain it, so the follow-up
    /// read must still happen.
    func refreshGarminHealth(force: Bool = false) async {
        guard !isRefreshingGarminHealth else {
            garminHealthRefreshQueued = true
            garminHealthRefreshQueuedForce = garminHealthRefreshQueuedForce || force
            return
        }
        isRefreshingGarminHealth = true
        defer { isRefreshingGarminHealth = false }
        garminHealthRefreshQueued = false
        garminHealthRefreshQueuedForce = false

        var passForce = force
        while true {
            await performGarminHealthRefresh(force: passForce)
            guard garminHealthRefreshQueued else { break }
            passForce = garminHealthRefreshQueuedForce
            garminHealthRefreshQueued = false
            garminHealthRefreshQueuedForce = false
        }
    }

    private func performGarminHealthRefresh(force: Bool) async {
        // Render whatever is cached right away.
        async let weightCached: Void = weightLoader.refresh()
        async let hydrationCached: Void = hydrationLoader.refresh()
        _ = await (weightCached, hydrationCached)

        let outcome = await garminHealthSync.refresh(force: force)
        if let authError = outcome.authError {
            authState.report(authError)
        }
        weightLoader.lastGarminRefreshFailed = outcome.weightFailed
        hydrationLoader.lastGarminRefreshFailed = outcome.hydrationFailed

        async let weight: Void = weightLoader.refresh()
        async let hydration: Void = hydrationLoader.refresh()
        _ = await (weight, hydration)
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

    /// Deletes one row of the merged weigh-in history (sync-weight-
    /// hydration-with-garmin D3): a Garmin weigh-in gets a queued Garmin
    /// delete and disappears at once; an undelivered local one is simply
    /// cancelled. Local writes only -- delivery starts in the background.
    @discardableResult
    func deleteWeighIn(_ row: WeighInDisplayEntry) async throws -> WeighInDeletion {
        let result = try await weightLogCoordinator.delete(row)
        await weightLoader.refresh()
        await refreshQueueState()
        if result == .garminDeleteQueued {
            Task { await self.drainAndReconcile() }
        }
        return result
    }

    /// Retries a failed weigh-in add or delete (a history row or the sync
    /// queue).
    func retryWeightQueued(id: UUID) async throws {
        try await weightOutbox.retry(id: id)
        await weightLoader.refresh()
        await refreshQueueState()
        await drainAndReconcile()
    }

    /// Gives up on a queued Garmin DELETE (sync queue only): the weigh-in
    /// stays in Garmin and reappears in the history. Adds aren't cancelled
    /// here -- deleting the weigh-in from the Weight screen does that and
    /// keeps the local record consistent. Refused with
    /// `OutboxEditError.entryInFlight` while a drain is sending that very
    /// DELETE (a sample can't be un-deleted) -- 2026-09-23 race fix.
    func cancelWeightDelete(_ entry: WeightOutboxEntry) async throws {
        guard entry.kind == .delete, entry.state != .sent else { return }
        try await weightOutbox.cancelQueued(id: entry.id)
        await weightLoader.refresh()
        await refreshQueueState()
    }

    /// Right after logging a drink (AddHydrationSheet's own confirm
    /// action) -- same reasoning as `weightLogged()`.
    func hydrationLogged() async {
        await hydrationLoader.refresh()
        Task { await self.drainAndReconcile() }
    }

    /// Removes a drink shown on the Water screen (sync-weight-hydration-
    /// with-garmin D4): an undelivered drink is cancelled; a delivered one
    /// gets a queued negative correction so Garmin's total drops too, and
    /// the shown total drops at once. Local writes only.
    @discardableResult
    func removeHydration(_ entry: HydrationEntry) async throws -> HydrationRemoval {
        let result = try await hydrationLogCoordinator.removeHydration(entry)
        await hydrationLoader.refresh()
        await refreshQueueState()
        if result == .correctionQueued {
            Task { await self.drainAndReconcile() }
        }
        return result
    }

    /// Retries a failed drink or correction (a history row or the sync
    /// queue).
    func retryHydrationQueued(id: UUID) async throws {
        try await hydrationOutbox.retry(id: id)
        await hydrationLoader.refresh()
        await refreshQueueState()
        await drainAndReconcile()
    }

    /// Gives up on a failed drink or correction (sync queue only), leaving
    /// the local list matching Garmin: a dropped correction lists its drink
    /// again; a dropped drink disappears (`HydrationLogCoordinator.
    /// discardQueued`). Without this a correction Garmin keeps rejecting
    /// could never leave the queue or clear the failure banner.
    func discardHydrationQueued(_ entry: HydrationOutboxEntry) async throws {
        guard entry.state != .sent else { return }
        try await hydrationLogCoordinator.discardQueued(entry)
        await hydrationLoader.refresh()
        await refreshQueueState()
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
        // why) but shares this same foreground/post-confirm drain trigger.
        // No food-style reconciliation step follows it: since
        // sync-weight-hydration-with-garmin the "read back" is the Garmin
        // health refresh kicked off below, and `WeightHistoryMerge` does
        // the matching.
        let weightResult = await weightOutbox.drain(using: garminClient)
        if !weightResult.delivered.isEmpty || !weightResult.failed.isEmpty {
            await weightLoader.refresh()
        }

        // Same for water (HydrationDayTotal does the matching).
        let hydrationResult = await hydrationOutbox.drain(using: garminClient)
        if !hydrationResult.delivered.isEmpty || !hydrationResult.failed.isEmpty {
            await hydrationLoader.refresh()
        }

        // Something reached Garmin: re-read it so a just-delivered weigh-in
        // picks up its `samplePk` (needed to delete it) and the water total
        // includes the drink. In the background -- the drain itself never
        // waits on a read. If a read is already running, this queues one
        // more pass after it (see `refreshGarminHealth`).
        if !weightResult.delivered.isEmpty || !hydrationResult.delivered.isEmpty {
            Task { await self.refreshGarminHealth() }
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

        // The weight/hydration drains above can ALSO hit an auth failure
        // (WeightOutbox/HydrationOutbox.drain detect it exactly like the
        // food outbox does) -- fixed 2026-09-22, a code-review finding: this
        // used to check only `result.authOutcome` (the food outbox), so a
        // day where the user only logged weight/water while the token was
        // expired never showed the auth banner at all. Every entry just
        // queued forever with no visible signal, the exact "silent auth
        // failure" this app is built to avoid (CLAUDE.md: "Auth failures
        // are loud"). Checking all three, any non-`.none` wins.
        let authOutcome = [result.authOutcome, weightResult.authOutcome, hydrationResult.authOutcome]
            .first { $0 != .none } ?? .none

        var authFailed = true
        switch authOutcome {
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

    /// Sync queue "Delete". Claim-guarded (code-review fix): refuses while
    /// a drain is sending the entry, and never drops an edit whose
    /// corrected entry Garmin already has (`.createdAwaitingDelete`) --
    /// that would leave both the old and the corrected entry in Garmin,
    /// untracked. The sync queue offers only Retry for those.
    func deleteQueued(_ entry: OutboxEntry) async throws {
        do {
            try await outbox.cancelQueued(id: entry.id)
        } catch OutboxEditError.entryNotFound {
            // Already delivered and confirmed, or removed: nothing to do.
        } catch OutboxEditError.entryInFlight {
            throw LogEntryEditError.stillSyncing
        } catch OutboxEditError.alreadyDelivered {
            throw LogEntryEditError.stillSyncing
        }
        await donations.entryDeleted(foodId: entry.foodId, date: entry.date)
        await refreshQueueState()
        await dayLog.rebuild()
    }

    // MARK: - Editing entries (add-log-entry-editing)

    /// Changes a logged entry's amount and/or meal on the day being viewed.
    /// Returns as soon as the change is durably queued: the day view shows
    /// it at once (design D3) and delivery -- create the corrected entry,
    /// then delete the old one (D1) -- happens in the background. Not a new
    /// thing eaten, so no XP; the day's goal status is re-checked.
    func editEntry(_ entry: MealEntry, newQuantity: Double, newMeal: MealType) async throws {
        let date = dayLog.dateString
        _ = try await logEntryCoordinator.edit(
            entry,
            date: date,
            newQuantity: newQuantity,
            newMeal: newMeal,
            regionCode: profile.settings?.regionCode,
            languageCode: profile.settings?.languageCode
        )
        await refreshQueueState()
        await dayLog.rebuild()
        await gamificationEngine.refreshGoalStatus(for: dayLog.selectedDate)
        Task { await self.drainAndReconcile() }
    }

    /// Logs the same food and amount again into the same meal ("second
    /// coffee"): an ordinary add, so it counts like any other log.
    func duplicateEntry(_ entry: MealEntry) async throws {
        let date = dayLog.dateString
        _ = try await logEntryCoordinator.duplicate(
            entry,
            date: date,
            regionCode: profile.settings?.regionCode,
            languageCode: profile.settings?.languageCode
        )
        await gamificationEngine.handleLogConfirmed(calories: entry.calories)
        await logConfirmed(food: nil, date: date)
    }

    /// What "Copy from…" can re-log out of `mealType` on `sourceDate`
    /// (design D4). A read of that day's Garmin log -- the same confirmed
    /// route the Today tab uses -- reusing the day loader's cache when it
    /// already has that day. Not a confirm path, so a network wait is fine.
    func copyMealPlan(from sourceDate: Date, mealType: MealType) async throws -> CopyMealPlan {
        let dateString = NutritionDate.string(from: sourceDate)
        let log: DailyFoodLog?
        if let cached = dayLog.cachedFoodLogs[dateString] {
            log = cached
        } else {
            log = try await nutritionReader.dailyFoodLog(date: dateString)
        }
        return CopyMealPlanner.plan(log: log, mealType: mealType)
    }

    /// Logs the checked items into `mealType` on the day being viewed, each
    /// as an ordinary add (durable before this returns; delivery follows).
    func copyMeal(_ items: [CopyableMealItem], to mealType: MealType) async throws {
        guard !items.isEmpty else { return }
        let date = dayLog.dateString
        _ = try await logEntryCoordinator.copyMeal(
            items,
            to: mealType,
            date: date,
            regionCode: profile.settings?.regionCode,
            languageCode: profile.settings?.languageCode
        )
        let calories = items.compactMap(\.calories).reduce(0, +)
        await gamificationEngine.handleLogConfirmed(calories: calories)
        await logConfirmed(food: nil, date: date)
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

    func setFastingStartReminder(_ setting: FastingReminderSetting) {
        notificationPreferences.setFastingStartReminder(setting)
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
    /// the daily fasting schedule, not by which day's food log is on
    /// screen), so it always runs.
    func syncNotifications() async {
        if dayLog.isToday {
            let mealsLoggedToday = Set(dayLog.dashboard.sections.filter { !$0.entries.isEmpty }.map(\.mealType))
            await NotificationScheduler.shared.sync(
                preferences: notificationPreferences.preferences,
                mealsLoggedToday: mealsLoggedToday,
                isStreakAtRiskToday: gamificationEngine.streakStatus.isAtRiskToday
            )
        }
        await NotificationScheduler.shared.syncFastingReminders(
            schedule: preferences.activeFastingSchedule,
            endsSoon: notificationPreferences.preferences.fastingReminder,
            startsSoon: notificationPreferences.preferences.fastingStartReminder
        )
    }

    // MARK: - Fasting (redesign-fasting-schedule)

    /// The daily fasting window changed in Settings (on/off or a time):
    /// the fasting reminders are anchored to its exact clock times, so
    /// re-plan them. Everything else fasting-related (home card, confirm
    /// note, history) derives from `preferences` on its next render.
    func fastingScheduleChanged() {
        Task { await syncNotifications() }
    }

    /// Task 1.3: reads the retired `fasting-sessions.json` ONCE and seeds
    /// the daily schedule from the last protocol used (see
    /// `FastingScheduleMigration`). The file is left on disk untouched.
    /// Skipped for good once it has run -- or once the user has set
    /// fasting up themselves, since every fasting setter marks it done.
    func migrateLegacyFastingIfNeeded() async {
        guard !preferences.fastingLegacyMigrated else { return }
        let active = await fastingStore.active()
        let history = await fastingStore.history()
        // Re-checked after the reads: the user may have changed fasting
        // settings while they were in flight, and their choice wins.
        guard !preferences.fastingLegacyMigrated else { return }
        let seed = FastingScheduleMigration.seed(active: active, history: history, calendar: .current)
        preferences.applyFastingMigration(seed)
        DiagnosticsLog.log(
            .info,
            category: "Fasting",
            "migrated \(history.count + (active == nil ? 0 : 1)) legacy session(s) to a daily window \(seed.schedule.startMinute)-\(seed.schedule.endMinute) min, enabled: \(seed.isEnabled)"
        )
    }

    // MARK: - Data mode (add-standalone-mode D1)

    /// The effective data mode (observable -- see
    /// `AppPreferences.effectiveDataMode`).
    var dataMode: DataMode { preferences.effectiveDataMode }

    /// The food search the catalog runs (add-standalone-mode D5): the
    /// Garmin-wired `foodSearchEngine` in Garmin mode, exactly as before;
    /// `standaloneFoodSearchEngine` (no Garmin source) in standalone mode.
    /// The OFF -> Garmin match flow keeps using `foodSearchEngine` directly.
    var catalogSearchEngine: FoodSearchEngine {
        dataMode == .standalone ? standaloneFoodSearchEngine : foodSearchEngine
    }

    /// Once per install: an install that predates `dataMode.v1` and has a
    /// Garmin token or any local history is the owner's phone, so it is
    /// stored as `.garminConnected` silently (`DataModeMigration`). A fresh
    /// install stays unset (onboarding, wave 5). A Keychain read that
    /// throws (e.g. before first unlock) skips classification until the
    /// next foreground rather than guessing "no token". Nothing reads the
    /// mode to change behaviour in wave 1.
    func classifyDataModeIfNeeded() async {
        guard preferences.dataMode == nil else { return }
        let hasGarminToken: Bool
        do {
            hasGarminToken = try await TokenProvider.shared.loadOAuth1Token() != nil
        } catch {
            DiagnosticsLog.log(.warning, category: "DataMode", "Couldn't read the Garmin token, will classify next foreground: \(error)")
            return
        }
        let services = AppServices.shared
        let outboxEntries = await outbox.allEntries()
        let usageEvents = await usageHistory.all()
        let weightEntries = await services.weightStore.all()
        let hydrationEntries = await services.hydrationStore.all()
        let hasLocalHistory = !outboxEntries.isEmpty || !usageEvents.isEmpty
            || !weightEntries.isEmpty || !hydrationEntries.isEmpty
        // Re-checked after the reads, like the fasting migration below.
        guard preferences.dataMode == nil else { return }
        guard let decided = DataModeMigration.decide(
            storedMode: nil,
            hasGarminToken: hasGarminToken,
            hasLocalHistory: hasLocalHistory
        ) else { return }
        preferences.dataMode = decided
        DiagnosticsLog.log(.info, category: "DataMode", "Classified as \(decided.rawValue) (token: \(hasGarminToken), local history: \(hasLocalHistory)).")
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
        let undeliveredWeight = await weightOutbox.allEntries().filter { $0.state != .sent }
        let undeliveredHydration = await hydrationOutbox.allEntries().filter { $0.state != .sent }
        undeliveredEntries = undelivered
        undeliveredWeightEntries = undeliveredWeight
        undeliveredHydrationEntries = undeliveredHydration
        undeliveredCount = undelivered.count + undeliveredWeight.count + undeliveredHydration.count

        // Auth failures have their own banner. Newest first, since that's
        // the attempt the user just made. Food first, then weight/water
        // (included since sync-weight-hydration-with-garmin; before that a
        // failed weigh-in or drink only showed on its own screen's row).
        var failure: String?
        if !authFailed {
            let errors: [String?] = undelivered.reversed().map(\.lastError)
                + undeliveredWeight.reversed().map(\.lastError)
                + undeliveredHydration.reversed().map(\.lastError)
            for case let error? in errors where !error.hasPrefix("auth:") {
                failure = error
                break
            }
        }
        lastDeliveryFailure = failure
    }
}
