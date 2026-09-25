// ShortcutLoggingRules.swift
//
// The mode rules for logging from outside the app's screens -- Siri "log X"
// (GarminFood/Shortcuts/LogNamedFoodIntent.swift) and the quick-pick
// intent/Controls (Shared/QuickPickLoggingIntents.swift) -- kept here so
// they are unit-tested (add-standalone-mode D5, task 3.6; spec "Meal
// presets, quick picks, Siri and Controls log through the current mode").
// Both already log through `FoodLogging` (`AppServices.logEntryCoordinator`,
// the mode-routing proxy), so a standalone log is a local commit. What
// differs per mode is only:
//   - what Siri searches: Garmin mode keeps `[.local, .garmin]`; standalone
//     searches `[.local, .offlineIndex]` -- her own foods and the offline
//     Czech index, never Garmin, and never live Open Food Facts, so Siri's
//     answer stays fast and works offline;
//   - what Siri may log: Garmin mode keeps today's rule (no custom foods,
//     no Open Food Facts products -- they need an in-app step); standalone
//     logs every origin as itself, custom foods included, but not a serving
//     without calories (NutritionCompleteness);
//   - whether to wait for Garmin delivery (`briefDelivery`): Garmin mode
//     only. Standalone has nothing to deliver, so a Control or Siri can't
//     report a Garmin sign-in problem there;
//   - a quick pick Garmin can't take (an Open Food Facts product or a
//     backing-less custom food, both only ever logged in standalone mode) is
//     refused in Garmin mode instead of sending an id Garmin doesn't know.
//
// Pure. Tested by ShortcutLoggingRulesTests.

import Foundation

public enum ShortcutLoggingRules {
    /// The search sources Siri "log X" asks in `mode`.
    public static func siriSearchOrigins(in mode: DataMode) -> Set<SearchOrigin> {
        switch mode {
        case .garminConnected: return [.local, .garmin]
        case .standalone: return [.local, .offlineIndex]
        }
    }

    /// Whether Siri may log `result` without the app in `mode`.
    public static func siriCanLog(_ result: SearchResult, in mode: DataMode) -> Bool {
        switch mode {
        case .garminConnected:
            return result.origin.isDirectlyLoggable && result.customDraft == nil && result.food.source != .custom
        case .standalone:
            if let draft = result.customDraft {
                return draft.asFood().servings.first?.completeness.isLoggable ?? false
            }
            guard result.food.source != .custom else { return false }
            return result.food.servings.contains { $0.completeness.isLoggable }
        }
    }

    /// Whether an intent should wait (briefly) for Garmin delivery after the
    /// local commit. Never in standalone mode.
    public static func waitsForGarminDelivery(in mode: DataMode) -> Bool {
        mode == .garminConnected
    }

    /// The amount Siri logs when the food has no remembered serving/amount:
    /// Garmin mode keeps today's rule (the serving's own declared quantity);
    /// standalone logs one serving -- an Open Food Facts "100 g" serving has
    /// `numberOfUnits == 100`, which as a multiplier would be 10 kg.
    public static func siriDefaultQuantity(for serving: Serving, in mode: DataMode) -> Double {
        switch mode {
        case .garminConnected: return serving.numberOfUnits
        case .standalone: return 1
        }
    }
}

extension QuickPickLogTarget {
    /// Garmin can't take this quick pick as it is (see ShortcutLoggingRules'
    /// header): an Open Food Facts product, or a custom food without a
    /// Garmin backing food.
    public var needsGarminMatch: Bool {
        switch self {
        case .catalog(let food, _, _):
            return food.source == .openFoodFacts
        case .custom(let draft, _):
            return !draft.hasGarminBacking
        }
    }
}
