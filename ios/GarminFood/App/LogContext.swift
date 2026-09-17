// LogContext.swift
//
// Where a log was started from (meal-dashboard spec: "Adding from a meal
// pre-selects that meal and day"). Set on the catalog when it is opened
// from a meal section; the confirm screen, pushed further down the same
// stack, inherits it through the environment, so no `LogTarget` call site
// has to carry it.

import SwiftUI
import GarminKit

struct LogContext: Hashable {
    var mealType: MealType?
    var date: Date?

    static let empty = LogContext(mealType: nil, date: nil)
}

private struct LogContextKey: EnvironmentKey {
    static let defaultValue = LogContext.empty
}

extension EnvironmentValues {
    var logContext: LogContext {
        get { self[LogContextKey.self] }
        set { self[LogContextKey.self] = newValue }
    }
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
