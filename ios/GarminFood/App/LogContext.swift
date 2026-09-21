// LogContext.swift
//
// Where a log was started from (meal-dashboard spec: "Adding from a meal
// pre-selects that meal and day").
//
// 2026-09-21 bug fix: this used to be relayed to the confirm screen purely
// through `.environment(\.logContext, ...)`, inherited implicitly across
// up to three separate pushed views (TodayView/MealDetailView ->
// FoodCatalogView -> MatchConfirmationView -> LogEntryConfirmView)
// depending on which path a food was found through. The owner reported
// that tapping "Add food" under Lunch consistently preset Snacks instead
// -- with no test coverage on this relay and no way to verify the exact
// break on a device from here, the environment-based relay was replaced
// outright with explicit `presetMealType`/`presetDate` parameters threaded
// through every view's own `init`, so the compiler enforces that each hop
// actually passes the right value along instead of relying on ambient
// propagation holding up across three separate files.
import Foundation
import GarminKit

struct LogContext: Hashable {
    var mealType: MealType?
    var date: Date?

    static let empty = LogContext(mealType: nil, date: nil)
}

extension MealType {
    /// Garmin Connect's order; `allCases` puts snacks before dinner.
    static var dashboardOrder: [MealType] { [.breakfast, .lunch, .dinner, .snacks] }

    var displayName: String {
        switch self {
        case .breakfast: return "Breakfast"
        case .lunch: return "Lunch"
        case .dinner: return "Dinner"
        case .snacks: return "Snacks"
        }
    }

    var symbolName: String {
        switch self {
        case .breakfast: return "sunrise.fill"
        case .lunch: return "sun.max.fill"
        case .dinner: return "moon.stars.fill"
        case .snacks: return "carrot.fill"
        }
    }
}
