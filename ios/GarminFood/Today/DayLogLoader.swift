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

import Foundation
import Observation
import GarminKit
import FoodLogCore

@MainActor
@Observable
final class DayLogLoader {
    @ObservationIgnored private let client: GarminClient
    @ObservationIgnored private let outbox: Outbox
    @ObservationIgnored private let foodCache: FoodCacheStore
    @ObservationIgnored private var logsByDate: [String: DailyFoodLog] = [:]
    @ObservationIgnored private var mealsByDate: [String: [Meal]] = [:]

    private(set) var selectedDate: Date
    private(set) var dashboard: DayDashboard
    private(set) var isLoading = false
    /// The day shown is an older copy because the last refresh failed.
    private(set) var isStale = false
    /// The most recent meal windows seen for any day, for defaulting the
    /// meal when logging starts outside the dashboard.
    private(set) var latestWindows: [MealWindow] = []

    init(client: GarminClient, outbox: Outbox, foodCache: FoodCacheStore, now: Date = Date()) {
        self.client = client
        self.outbox = outbox
        self.foodCache = foodCache
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
    /// open or in the background.
    func rollOverIfNeeded(previousToday: Date) async {
        let calendar = Calendar.current
        guard calendar.isDate(selectedDate, inSameDayAs: previousToday),
              !calendar.isDateInToday(selectedDate) else { return }
        await goToToday()
    }

    // MARK: - Loading

    /// Fetches the selected day from Garmin. On failure the previous copy
    /// stays (stale); the meal windows are then fetched separately, so a day
    /// never loaded before still gets its meal layout.
    ///
    /// Reentrancy guard restored 2026-09-17: `ContentView`'s `.task` and its
    /// `scenePhase == .active` handler can both call `refreshOnForeground()`
    /// -- and so this -- close together (e.g. a Control launches the app,
    /// firing both near-simultaneously), and `MealDetailView`'s own
    /// `.refreshable` can call `refresh()` directly while a foreground
    /// refresh is still in flight. Without this guard, two concurrent calls
    /// race on `isLoading`/`logsByDate`/`isStale`: the FIRST call's `defer`
    /// can flip `isLoading` back to false while the second is still
    /// awaiting the network, so the "Updating…" indicator disappears
    /// early, and whichever response resolves last silently wins.
    func refresh() async {
        guard !isLoading else { return }
        let date = dateString
        isLoading = true
        defer { isLoading = false }

        do {
            if let log = try await client.dailyFoodLog(date: date) {
                logsByDate[date] = log
                if date == dateString { isStale = false }
            } else {
                logsByDate.removeValue(forKey: date)
                await loadMealsIfNeeded(date: date)
                if date == dateString { isStale = false }
            }
        } catch {
            if date == dateString { isStale = logsByDate[date] != nil }
            await loadMealsIfNeeded(date: date)
        }
        await rebuild()
    }

    /// Re-applies local state (the outbox, cached foods) without a network
    /// call, e.g. right after a log is confirmed.
    func rebuild() async {
        let date = dateString
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
        if !built.windows.isEmpty {
            latestWindows = built.windows
        }
    }

    private func loadMealsIfNeeded(date: String) async {
        guard mealsByDate[date] == nil,
              let meals = try? await client.mealsForDate(date: date).meals else { return }
        mealsByDate[date] = meals
    }

    // MARK: - Deleting

    enum DeleteError: LocalizedError {
        case missingIdentifier
        case garmin(String)

        var errorDescription: String? {
            switch self {
            case .missingIdentifier:
                return "This entry has no Garmin identifier, so it can't be deleted from here. Delete it in Garmin Connect."
            case .garmin(let detail):
                return "Garmin didn't delete this entry: \(detail). You can also delete it in Garmin Connect."
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
                try await client.deleteFoodLogEntries(logIds: [logId], date: dateString)
            } catch {
                throw DeleteError.garmin(Self.describe(error))
            }
            await refresh()
        case .syncing(let outboxId), .failed(let outboxId, _):
            try await outbox.delete(id: outboxId)
            await rebuild()
        }
    }

    private static func describe(_ error: Error) -> String {
        switch error {
        case GarminClientError.httpError(let statusCode, _):
            return "HTTP \(statusCode)"
        case GarminClientError.unauthorized:
            return "not signed in"
        case GarminClientError.rateLimited:
            return "too many requests, try again shortly"
        default:
            return error.localizedDescription
        }
    }
}
