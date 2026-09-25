// DayLogLoader.swift
//
// Loads any day for the Today tab and turns it into a `DayDashboard`
// (meal-dashboard spec). Replaces `TodaySummaryLoader`, which read today
// only and kept nothing but the calorie total.
//
// Garmin data per date is kept in memory, so a failed refresh keeps showing
// the last good copy (marked stale) instead of blanking the day. Queued
// entries come from the outbox on every rebuild, so a log appears in its
// meal immediately, before any network call.
//
// Also carries the selected day's active calories (`activeKilocalories`,
// fix-testing-feedback-quick-wins) for the summary card's informational
// "Active today" line -- one extra read per refresh, run concurrently with
// the food log and silently dropped on failure.
//
// add-standalone-mode 2.5: in standalone mode `reader` answers from the
// local food log, deletes go to the local coordinator, and `rebuild()`
// re-reads the (local, file-backed) day so a confirm shows immediately.

import Foundation
import Observation
import GarminKit
import FoodLogCore

@MainActor
@Observable
final class DayLogLoader {
    /// add-standalone-mode D3: the day log, meal windows and active
    /// calories. The app's GarminClient today.
    @ObservationIgnored private let reader: any NutritionLogReading
    @ObservationIgnored private let client: GarminClient
    @ObservationIgnored private let outbox: Outbox
    @ObservationIgnored private let foodCache: FoodCacheStore
    /// Deleting goes through it: a still-queued row by claim-guarded
    /// cancel, a synced one by `deleteCommitted` (add-standalone-mode D4).
    @ObservationIgnored private let coordinator: any FoodLogging
    @ObservationIgnored private var logsByDate: [String: DailyFoodLog] = [:]
    @ObservationIgnored private var mealsByDate: [String: [Meal]] = [:]
    @ObservationIgnored private var activeByDate: [String: Double] = [:]
    /// The data mode the three per-date caches above were filled under
    /// (code-review fix). Flipping the testing toggle changes `dataMode()`
    /// mid-session; without dropping the caches, local standalone rows
    /// would keep showing in Garmin mode as `.synced(logId: <local UUID>)`,
    /// and editing or deleting one would queue a Garmin write for an id
    /// Garmin never issued (and the reverse for Garmin rows in standalone).
    @ObservationIgnored private var cacheMode: DataMode?
    /// add-gamification-signals 7.2: the day log and active kcal this
    /// loader ALREADY reads are also cached for the gamification signals
    /// (no new request). `nil` in previews/tests.
    @ObservationIgnored private let digestStore: DayLogDigestStore?
    @ObservationIgnored private let activityCache: ActivityCacheStore?
    /// add-standalone-mode 2.5: the effective data mode, read per call.
    /// In standalone mode the day log is the LOCAL food log, so `rebuild()`
    /// re-reads it (a file read, no network) and a just-confirmed entry
    /// shows at once -- the job the outbox overlay does in Garmin mode.
    @ObservationIgnored private let dataMode: @Sendable () -> DataMode

    private(set) var selectedDate: Date
    private(set) var dashboard: DayDashboard
    /// The selected day's active (burned) calories, for the home screen's
    /// informational "Active today" line (fix-testing-feedback-quick-wins,
    /// today-dashboard spec). Read from GET /usersummary-service/usersummary/
    /// daily (calorie fields confirmed live 2026-09-23). `nil` whenever the
    /// last read for this day failed or had no value -- the spec says hide
    /// the line then, never show an error. Informational only: it never
    /// feeds the Target (owner decision 2026-09-23, no eat-back).
    private(set) var activeKilocalories: Double?
    /// 2026-09-21 bug fix: this used to be a single loader-wide `Bool`, so
    /// `refresh()`'s reentrancy guard (needed to stop two concurrent
    /// refreshes of the SAME day from clobbering each other) also blocked
    /// a refresh of a DIFFERENT day. Switching days while a refresh was
    /// still in flight silently dropped the new day's fetch entirely --
    /// `isLoading` ended up `false` and `isStale` stayed `false`, so the
    /// newly selected day looked like it had been freshly loaded and
    /// genuinely had nothing logged, when it was simply never fetched.
    /// Tracking the set of dates currently being fetched (rather than a
    /// single flag) lets different days load concurrently -- each only
    /// touches its own `logsByDate`/`mealsByDate` key -- while still
    /// preventing two overlapping refreshes of the SAME day.
    private var loadingDates: Set<String> = []
    var isLoading: Bool { loadingDates.contains(dateString) }
    /// The day shown is an older copy because the last refresh failed.
    private(set) var isStale = false
    /// The most recent meal windows seen for any day, for defaulting the
    /// meal when logging starts outside the dashboard.
    private(set) var latestWindows: [MealWindow] = []

    init(
        reader: any NutritionLogReading,
        client: GarminClient,
        outbox: Outbox,
        foodCache: FoodCacheStore,
        coordinator: any FoodLogging,
        digestStore: DayLogDigestStore? = nil,
        activityCache: ActivityCacheStore? = nil,
        dataMode: @escaping @Sendable () -> DataMode = { .garminConnected },
        now: Date = Date()
    ) {
        self.reader = reader
        self.client = client
        self.outbox = outbox
        self.foodCache = foodCache
        self.coordinator = coordinator
        self.digestStore = digestStore
        self.activityCache = activityCache
        self.dataMode = dataMode
        let day = Calendar.current.startOfDay(for: now)
        self.selectedDate = day
        self.dashboard = MealDashboard.build(
            date: NutritionDate.string(from: day),
            log: nil,
            outboxEntries: [],
            foods: [:]
        )
    }

    var dateString: String {
        NutritionDate.string(from: selectedDate)
    }

    var isToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }

    /// Every Garmin day log fetched so far this session, keyed by
    /// `yyyy-MM-dd`. Read-only, for `FastingHistoryView`
    /// (redesign-fasting-schedule 2.3), which judges past fasts from
    /// whatever is already cached here rather than fetching 30 days.
    var cachedFoodLogs: [String: DailyFoodLog] {
        logsByDate
    }

    // MARK: - Navigation

    func step(byDays days: Int) async {
        guard let date = Calendar.current.date(byAdding: .day, value: days, to: selectedDate) else { return }
        await select(date)
    }

    func goToToday() async {
        await select(Date())
    }

    func select(_ date: Date) async {
        let day = Calendar.current.startOfDay(for: date)
        guard day != selectedDate else { return }
        selectedDate = day
        isStale = false
        await rebuild()
        await refresh()
    }

    /// Keeps "today" meaning today after midnight passes while the app is
    /// open (`AppEnvironment.dayDidChange`) or in the background
    /// (`refreshOnForeground`). The rule is `NutritionDate.shouldRollOver`
    /// (FoodLogCore, unit-tested).
    func rollOverIfNeeded(previousToday: Date) async {
        guard NutritionDate.shouldRollOver(selectedDay: selectedDate, previousToday: previousToday) else { return }
        await goToToday()
    }

    // MARK: - Loading

    /// Fetches the selected day from Garmin. On failure the previous copy
    /// stays (stale); the meal windows are then fetched separately, so a day
    /// never loaded before still gets its meal layout.
    ///
    /// Reentrancy guard restored 2026-09-17, made per-date 2026-09-21 (see
    /// `loadingDates`' doc comment): `ContentView`'s `.task` and its
    /// `scenePhase == .active` handler can both call `refreshOnForeground()`
    /// -- and so this -- close together (e.g. a Control launches the app,
    /// firing both near-simultaneously), and `MealDetailView`'s own
    /// `.refreshable` can call `refresh()` directly while a foreground
    /// refresh is still in flight. Without a guard, two concurrent calls
    /// for the SAME date race on `logsByDate`/`isStale`: the FIRST call's
    /// `defer` can clear its loading state while the second is still
    /// awaiting the network, so the "Updating…" indicator disappears
    /// early, and whichever response resolves last silently wins. The
    /// guard is scoped per-date (not loader-wide) so refreshing a
    /// DIFFERENT date is never blocked by one already in flight.
    func refresh() async {
        let date = dateString
        guard !loadingDates.contains(date) else { return }
        loadingDates.insert(date)
        defer { loadingDates.remove(date) }

        // Fetched alongside the food log, not after it, so the extra read
        // never lengthens "Updating…"; its failure is swallowed inside.
        async let activeLoad: Void = loadActiveCalories(date: date)

        do {
            if let log = try await reader.dailyFoodLog(date: date) {
                logsByDate[date] = log
                if date == dateString { isStale = false }
                try? await digestStore?.save(DayLogDigest(log: log, day: date, fetchedAt: Date()))
            } else {
                logsByDate.removeValue(forKey: date)
                await loadMealsIfNeeded(date: date)
                if date == dateString { isStale = false }
            }
        } catch {
            if date == dateString { isStale = logsByDate[date] != nil }
            await loadMealsIfNeeded(date: date)
        }
        await activeLoad
        await rebuild()
    }

    /// Re-applies local state (the outbox, cached foods) without a network
    /// call, e.g. right after a log is confirmed.
    func rebuild() async {
        let date = dateString
        if dataMode() == .standalone,
           let local = try? await reader.dailyFoodLog(date: date) {
            // A failed local read (e.g. before first unlock) keeps the copy.
            logsByDate[date] = local
        }
        let entries = await outbox.allEntries()
        let foods = await foodCache.all()
        let built = MealDashboard.build(
            date: date,
            log: logsByDate[date],
            meals: mealsByDate[date] ?? [],
            outboxEntries: entries,
            foods: foods
        )
        guard date == dateString else { return }
        dashboard = built
        activeKilocalories = activeByDate[date]
        if !built.windows.isEmpty {
            latestWindows = built.windows
        }
    }

    private func loadMealsIfNeeded(date: String) async {
        guard mealsByDate[date] == nil,
              let meals = try? await reader.mealsForDate(date: date).meals else { return }
        mealsByDate[date] = meals
    }

    /// Any failure -- network, auth, decode, or simply no value for the
    /// day -- clears this day's figure so the line hides, per the spec's
    /// "Route unavailable" scenario. Never throws: this is an optional
    /// extra and must not affect the rest of the day's refresh.
    private func loadActiveCalories(date: String) async {
        if let summary = try? await reader.dailyUserSummary(date: date),
           let active = summary.activeKilocalories {
            activeByDate[date] = active
            try? await activityCache?.recordActiveKcal(active, day: date)
        } else {
            activeByDate.removeValue(forKey: date)
        }
    }

    // MARK: - Deleting

    enum DeleteError: LocalizedError {
        case missingIdentifier
        case garmin(String)

        var errorDescription: String? {
            switch self {
            case .missingIdentifier:
                return String(localized: "This entry has no Garmin identifier, so it can't be deleted from here. Delete it in Garmin Connect.")
            case .garmin(let detail):
                return String(localized: "Garmin didn't delete this entry: \(detail). You can also delete it in Garmin Connect.", comment: "%@ = short reason, e.g. 'HTTP 500' or 'not signed in'.")
            }
        }
    }

    /// A synced entry is deleted in Garmin (design D5), then the day is
    /// re-read. A queued entry never reached Garmin, so it is only removed
    /// from the queue.
    func delete(_ entry: MealEntry) async throws {
        switch entry.status {
        case .synced(let logId):
            guard !logId.isEmpty else { throw DeleteError.missingIdentifier }
            do {
                try await coordinator.deleteCommitted(logId: logId, date: dateString)
            } catch {
                // Standalone: a local delete, no Garmin involved -- its own
                // error (e.g. "changed in the meantime") says it best.
                if dataMode() == .standalone { throw error }
                throw DeleteError.garmin(Self.describe(error))
            }
            await refresh()
        case .syncing(let outboxId), .failed(let outboxId, _):
            // Claim-guarded (code-review fix): refuses while a drain is
            // sending it or Garmin already has it, and for an edit also
            // deletes the original Garmin entry the edit was replacing.
            let outcome = try await coordinator.deletePending(outboxId: outboxId)
            await rebuild()
            if case .deleteOriginal(let date, let logId) = outcome {
                // Stays a direct Garmin call: an outbox edit only ever
                // replaces a Garmin entry, whatever the data mode is now.
                do {
                    try await client.deleteFoodLogEntries(logIds: [logId], date: date)
                } catch GarminClientError.httpError(let statusCode, _) where statusCode == 404 {
                    // Already gone from Garmin: nothing left to remove.
                } catch {
                    // The edit is cancelled, so the original shows again at
                    // its old amount -- say so; deleting it once more works.
                    await refresh()
                    throw DeleteError.garmin(Self.describe(error))
                }
                await refresh()
            }
        }
    }

    private static func describe(_ error: Error) -> String {
        switch error {
        case GarminClientError.httpError(let statusCode, _):
            return "HTTP \(statusCode)"
        case GarminClientError.unauthorized:
            return String(localized: "not signed in", comment: "Short reason after 'Garmin didn't delete this entry: '.")
        case GarminClientError.rateLimited:
            return String(localized: "too many requests, try again shortly", comment: "Short reason after 'Garmin didn't delete this entry: '.")
        default:
            return error.localizedDescription
        }
    }
}
