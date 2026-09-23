// RecentRanker.swift
//
// Orders the "Recent" shelf on the empty-query Log Food screen
// (improve-log-food-shelves task 1.3, food-catalog spec's "A Recent shelf
// lists the last foods logged" requirement): "what did I just have", with
// no frequency blending at all. Quick pick (`QuickPick.rank`) answers a
// different question -- a food logged once a minute ago can sit below a
// staple there, which is exactly what this shelf exists to avoid.
//
// Pure function over `[UsageEvent]` (UsageHistory.swift), so it is unit-
// testable with hand-built arrays and no file I/O. Uses `timestamp` (when
// the confirm was pressed), not `nutritionDay` (the day it was logged
// FOR): back-filling yesterday's lunch still counts as "just logged".
//
// Depended on by: FoodCatalogView's `loadLocalData` (app target).

import Foundation

public enum RecentRanker {
    public struct Entry: Sendable, Equatable {
        public let foodId: String
        /// The serving and quantity from this food's most recent event --
        /// what a one-tap re-log should default to.
        public let servingId: String
        public let numberOfUnits: Double
        public let loggedAt: Date

        public init(foodId: String, servingId: String, numberOfUnits: Double, loggedAt: Date) {
            self.foodId = foodId
            self.servingId = servingId
            self.numberOfUnits = numberOfUnits
            self.loggedAt = loggedAt
        }
    }

    /// The last `limit` DISTINCT foods (by `foodId`), newest first. Two
    /// events with the same timestamp (a meal preset logs every ingredient
    /// with one shared `now`) are ordered by their position in `events`,
    /// later first -- `UsageHistoryStore` appends, so later in the array
    /// means recorded later.
    public static func rank(events: [UsageEvent], limit: Int = 10) -> [Entry] {
        guard limit > 0, !events.isEmpty else { return [] }

        let newestFirst = events.enumerated().sorted { lhs, rhs in
            if lhs.element.timestamp != rhs.element.timestamp {
                return lhs.element.timestamp > rhs.element.timestamp
            }
            return lhs.offset > rhs.offset
        }

        var seenFoodIds = Set<String>()
        var result: [Entry] = []
        for indexed in newestFirst {
            if result.count >= limit { break }
            let event = indexed.element
            guard seenFoodIds.insert(event.foodId).inserted else { continue }
            result.append(Entry(
                foodId: event.foodId,
                servingId: event.servingId,
                numberOfUnits: event.numberOfUnits,
                loggedAt: event.timestamp
            ))
        }
        return result
    }
}
