// MacroTrendLoader.swift
//
// The macro-trend data the Trends screen's calorie/protein/carbs/fat charts
// need (add-trends-and-insights) -- mirrors `Weight/WeightLoader.swift`'s
// shape (an `@Observable` holding the last-fetched snapshot, a `refresh()`
// nothing else waits on), but over a single Garmin READ instead of a local
// store: `GarminClient.calorieSummaryDaily` returns a whole date range in
// one call, so there is nothing to persist locally and nothing an outbox
// needs to own -- a fresh in-memory fetch each time the Trends screen
// appears is the whole story, per this change's proposal.md ("pure local
// computation over data already fetched, ... minimal new Garmin reads").
//
// Deliberately NOT wired into `AppEnvironment.refreshOnForeground()`'s
// batch the way `weightLoader`/`hydrationLoader`/`profile` are: a 30-day
// macro history is only useful while the Trends screen itself is open, so
// it loads on that screen's own `.task`/pull-to-refresh instead of on every
// app foreground.

import Foundation
import Observation
import GarminKit
import Gamification

@MainActor
@Observable
final class MacroTrendLoader {
    @ObservationIgnored private let client: GarminClient

    /// Oldest first, ready for Swift Charts to draw left-to-right.
    private(set) var days: [MacroTrendDay] = []
    private(set) var isLoading = false
    /// `true` only when the most recent `refresh()` failed outright (a
    /// network/auth/decoding error) -- NOT when the range legitimately has
    /// no logged days, which is a normal, non-error `days.isEmpty`.
    private(set) var loadFailed = false

    init(client: GarminClient) {
        self.client = client
    }

    /// Fetches the last `daysBack` nutrition days (inclusive of today's
    /// nutrition day) in one call. Uses `NutritionDayBoundary` -- the same
    /// day-boundary helper `GamificationEngine`'s goal/streak logic already
    /// uses -- so "today" here means the same nutrition day the rest of the
    /// app means by it, not local midnight.
    func refresh(daysBack: Int = 30, now: Date = Date(), calendar: Calendar = .current) async {
        isLoading = true
        defer { isLoading = false }

        let endDay = NutritionDayBoundary.nutritionDay(for: now, boundaryHour: NutritionDayBoundary.loggedDateBoundaryHour, calendar: calendar)
        guard daysBack > 0, let startDay = calendar.date(byAdding: .day, value: -(daysBack - 1), to: endDay) else {
            loadFailed = true
            return
        }
        let startDate = NutritionDayBoundary.string(forNutritionDay: startDay, calendar: calendar)
        let endDate = NutritionDayBoundary.string(forNutritionDay: endDay, calendar: calendar)

        do {
            let response = try await client.calorieSummaryDaily(startDate: startDate, endDate: endDate)
            days = MacroTrendDay.make(from: response, calendar: calendar)
            loadFailed = false
        } catch {
            loadFailed = true
        }
    }
}

/// One nutrition day's actual-vs-goal macros, ready for the Trends charts.
///
/// A field is `nil` when Garmin's response omitted it -- per
/// `CalorieSummaryDay`'s doc comment (GarminModels.swift), that means
/// "nothing logged that day" (for the actual fields) or "no goal recorded"
/// (for the goal fields), never a fabricated zero. Chart views must skip
/// `nil` points rather than plot them as 0.
struct MacroTrendDay: Identifiable {
    let date: Date
    let calories: Double?
    let proteinG: Double?
    let carbsG: Double?
    let fatG: Double?
    let calorieGoal: Double?
    let proteinGoalG: Double?
    let carbsGoalG: Double?
    let fatGoalG: Double?

    var id: Date { date }

    /// Builds the chart-ready, oldest-first day list from the raw wire
    /// response. Goal fields prefer `adjusted*` over the base goal, the
    /// exact same "burned calories add to the target" convention
    /// `GamificationEngine.dailyGoalStatus` and `MealDashboard` already use
    /// for the identical `NutritionGoals` type (`goals.adjustedX ?? goals.X`).
    static func make(from response: CalorieSummaryDailyResponse, calendar: Calendar) -> [MacroTrendDay] {
        (response.dailyNutritionContents ?? [])
            .compactMap { day -> MacroTrendDay? in
                guard let mealDate = day.mealDate,
                      let date = NutritionDayBoundary.date(fromDayString: mealDate, calendar: calendar) else { return nil }
                let content = day.nutritionContent
                let goals = day.nutritionGoals
                return MacroTrendDay(
                    date: date,
                    calories: content?.calories,
                    proteinG: content?.protein,
                    carbsG: content?.carbs,
                    fatG: content?.fat,
                    calorieGoal: goals?.adjustedCalories ?? goals?.calories,
                    proteinGoalG: goals?.adjustedProtein ?? goals?.protein,
                    carbsGoalG: goals?.adjustedCarbs ?? goals?.carbs,
                    fatGoalG: goals?.adjustedFat ?? goals?.fat
                )
            }
            .sorted { $0.date < $1.date }
    }
}
