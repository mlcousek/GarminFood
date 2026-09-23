// QuickPickResolution.swift
//
// Turns ranked quick-pick entries (`QuickPick.rank`, UsageHistory.swift) into
// things that can actually be logged to Garmin, for the paths that log a
// quick pick WITHOUT a screen: the four quick-pick Controls and the "Log
// usual food" Siri shortcut (Shared/QuickPickLoggingIntents.swift).
//
// Why it exists: a custom food records its usage under its own LOCAL UUID,
// with serving id `CustomFoodDraft.servingId` ("custom"), and its
// `asFood()` snapshot is also in the food cache under that UUID. The
// intent used to look the top entry up in the cache and hand it straight
// to `LogEntryCoordinator.confirm`, which queued foodId = <local UUID>,
// servingId = "custom" -- a 400 from Garmin, so the entry sat failed in
// the sync queue after the Control had already shown success. The in-app
// shelves never did this: they resolve a custom food through its draft and
// log it as its backing Garmin food (`confirmCustomFood`). This applies
// the same rule as `FoodCatalogView.shelfItem`:
//
//   - a custom food whose draft still exists -> `.custom(draft, quantity:)`,
//     to be logged with `LogEntryCoordinator.confirmCustomFood`;
//   - a custom food whose draft was deleted -> dropped (its id means
//     nothing to Garmin, so nothing can be logged for it);
//   - any other food with its exact serving in the cache -> `.catalog`;
//   - anything else (not cached, serving gone) -> dropped.
//
// Dropped entries are skipped, not failed, so rank N here is the same card
// as the Nth card on the app's own shelf. Pure; tested in
// QuickPickResolutionTests.

import Foundation

/// A ranked quick pick, resolved to something `LogEntryCoordinator` can
/// deliver.
public enum QuickPickLogTarget: Sendable, Equatable {
    /// Log with `LogEntryCoordinator.confirm(food:serving:numberOfUnits:...)`.
    case catalog(food: Food, serving: Serving, numberOfUnits: Double)
    /// Log with `LogEntryCoordinator.confirmCustomFood(_:quantity:...)`, which
    /// sends the draft's backing Garmin food.
    case custom(CustomFoodDraft, quantity: Double)

    /// The food as the app shows it (a custom food's own name, not its
    /// backing food's).
    public var displayFood: Food {
        switch self {
        case .catalog(let food, _, _):
            return food
        case .custom(let draft, _):
            return draft.asFood()
        }
    }
}

public enum QuickPickResolution {
    /// `ranked`, in order, resolved against the food cache and the current
    /// custom-food drafts, with every entry that can't be logged dropped
    /// (see the file header for the rules).
    public static func loggable(
        _ ranked: [QuickPick.Entry],
        cache: [String: Food],
        customFoods: [CustomFoodDraft]
    ) -> [QuickPickLogTarget] {
        let draftsById = Dictionary(customFoods.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { first, _ in first })
        return ranked.compactMap { entry in
            if let draft = draftsById[entry.foodId] {
                guard entry.servingId == CustomFoodDraft.servingId else { return nil }
                return .custom(draft, quantity: entry.numberOfUnits)
            }
            guard let food = cache[entry.foodId], food.source != .custom,
                  let serving = food.servings.first(where: { $0.id == entry.servingId })
            else { return nil }
            return .catalog(food: food, serving: serving, numberOfUnits: entry.numberOfUnits)
        }
    }
}
