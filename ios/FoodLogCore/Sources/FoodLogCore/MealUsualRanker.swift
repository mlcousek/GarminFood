// MealUsualRanker.swift
//
// Ranks the "Usual for <meal>" shelf on the empty-query Log Food screen
// (improve-log-food-shelves task 1.2, food-catalog spec's "A per-meal shelf
// surfaces the foods usually eaten at that meal" requirement). Breakfast
// looks different from dinner, and Quick pick (`QuickPick.rank`, which
// ignores the meal) can't tell them apart -- this can, because
// `UsageEvent.mealType` records the meal every confirm was logged under.
//
// Pure function over `[UsageEvent]`, same shape and same recency-weighted
// frequency idea as `QuickPick.rank` (UsageHistory.swift), so it is unit-
// testable with hand-built arrays and no file I/O. Two deliberate
// differences from Quick pick:
//   - It groups by FOOD, not by (food, serving): the shelf answers "what do
//     I usually eat at breakfast", and the card re-logs with the serving
//     and quantity most recently used for that food at that meal.
//   - Its half-life is 14 days, not 7: a meal's staples are a slower,
//     steadier habit than "what I've been eating this week".
//
// Events recorded before `mealType` existed (nil) never count toward any
// meal -- guessing their meal from the clock would put a 10pm snack on the
// dinner shelf. Instead, `UsageMealBackfill` fills those events in once
// from Garmin's own day logs (ground truth for which meal a food was
// logged under), so the shelf isn't empty after the upgrade; anything it
// can't place unambiguously stays nil. `minimumMealEvents` keeps the shelf
// hidden until a meal has enough history to mean something.
//
// Depended on by: FoodCatalogView's `loadLocalData` (app target).

import Foundation
import GarminKit

public enum MealUsualRanker {
    /// The shelf stays hidden (the ranker returns `[]`) until the meal has
    /// at least this many logged events.
    public static let minimumMealEvents = 3

    /// Ranks foods logged under `mealType` by a recency-decayed frequency:
    /// each event contributes `0.5 ^ (ageInDays / halfLifeDays)` to its
    /// food's score. Returns `[]` when fewer than `minimumEvents` events
    /// carry that meal type. Each entry's `servingId`/`numberOfUnits` come
    /// from that food's MOST RECENT event at this meal.
    public static func rank(
        events: [UsageEvent],
        mealType: MealType,
        now: Date = Date(),
        halfLifeDays: Double = 14,
        minimumEvents: Int = MealUsualRanker.minimumMealEvents,
        limit: Int = 10
    ) -> [QuickPick.Entry] {
        let mealEvents = events.filter { $0.mealType == mealType }
        guard limit > 0, !mealEvents.isEmpty, mealEvents.count >= minimumEvents else { return [] }

        struct Accumulator {
            var score: Double = 0
            var lastUsedAt: Date = .distantPast
            var lastServingId: String = ""
            var lastNumberOfUnits: Double = 0
            var useCount: Int = 0
        }

        var byFood: [String: Accumulator] = [:]
        for event in mealEvents {
            let ageInDays = max(0, now.timeIntervalSince(event.timestamp) / 86_400)
            let weight = pow(0.5, ageInDays / max(halfLifeDays, 0.0001))

            var accumulator = byFood[event.foodId] ?? Accumulator()
            accumulator.score += weight
            accumulator.useCount += 1
            if event.timestamp >= accumulator.lastUsedAt {
                accumulator.lastUsedAt = event.timestamp
                accumulator.lastServingId = event.servingId
                accumulator.lastNumberOfUnits = event.numberOfUnits
            }
            byFood[event.foodId] = accumulator
        }

        return byFood
            .map { foodId, accumulator in
                QuickPick.Entry(
                    foodId: foodId,
                    servingId: accumulator.lastServingId,
                    numberOfUnits: accumulator.lastNumberOfUnits,
                    score: accumulator.score,
                    lastUsedAt: accumulator.lastUsedAt,
                    useCount: accumulator.useCount
                )
            }
            // Deterministic tie-break by food id, so ordering never depends
            // on `Dictionary`'s unordered iteration (same as QuickPick).
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                return $0.foodId < $1.foodId
            }
            .prefix(limit)
            .map { $0 }
    }
}
