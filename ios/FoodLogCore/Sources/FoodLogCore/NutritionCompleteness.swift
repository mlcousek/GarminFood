// NutritionCompleteness.swift
//
// Whether a serving's nutrition is complete enough to log in standalone
// mode (add-standalone-mode D5, standalone-food-catalog spec "Search and log
// foods without a Garmin food identity"). In Garmin mode Garmin/FatSecret
// supplies the numbers and an Open Food Facts product only reaches the log
// through a Garmin match, whose create step already refuses a product with
// no calories. In standalone mode an Open Food Facts / offline-index product
// is logged AS ITSELF, so its community data is all there is:
//   - no calories: refused -- a day total can't silently omit a food, so
//     the confirm screen offers "create a custom food" instead;
//   - calories but a missing carb/protein/fat value: logged, the missing
//     value stays unknown (counted as 0 in totals, never stored as 0), and
//     the screen says "some values missing".
// Vitamins/minerals are always partial on OFF and don't count here.
//
// Pure. Read by LogEntryConfirmView (standalone only) and enforced again in
// LocalLogEntryCoordinator, so Siri/Controls can't bypass it. Tested by
// NutritionCompletenessTests.

import Foundation

public enum NutritionCompleteness: Sendable, Equatable {
    /// Calories, carbs, protein and fat are all known.
    case complete
    /// Calories are known; at least one of carbs/protein/fat is not.
    case someValuesMissing
    /// No calorie value: can't be logged in standalone mode.
    case caloriesUnknown

    public init(serving: Serving) {
        guard let calories = serving.calories, calories.isFinite, calories >= 0 else {
            self = .caloriesUnknown
            return
        }
        let macros = [serving.carbs, serving.protein, serving.fat]
        self = macros.allSatisfy({ $0 != nil }) ? .complete : .someValuesMissing
    }

    /// Standalone mode logs everything except a serving without calories.
    public var isLoggable: Bool { self != .caloriesUnknown }
}

extension Serving {
    public var completeness: NutritionCompleteness { NutritionCompleteness(serving: self) }
}

/// Thrown by `LocalLogEntryCoordinator` (standalone mode only).
public enum StandaloneLoggingError: Error, Sendable, Equatable, LocalizedError {
    /// The serving has no calorie value (`NutritionCompleteness.caloriesUnknown`).
    case caloriesUnknown

    public var errorDescription: String? {
        switch self {
        case .caloriesUnknown:
            return String(
                localized: "This food has no calorie value, so it can't be logged. Create a custom food with its calories instead.",
                bundle: .module,
                comment: "Standalone mode: a food from Open Food Facts without calories can't be logged."
            )
        }
    }
}
