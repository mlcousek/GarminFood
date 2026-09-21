import FoodLogCore
import Foundation

// DailyChallengeEngine.swift
//
// Evaluation (daily-challenges spec's "completion condition evaluable
// purely from that day's local log entries and locally cached goal
// status") and selection (the spec's "does not repeat within 30 days,"
// with a least-recently-shown fallback so a day is never left short).

public enum DailyChallengeEngine {
    public static func isComplete(
        kind: DailyChallengeKind,
        dayEvents: [UsageEvent],
        priorEvents: [UsageEvent],
        goalStatus: DailyGoalStatus?,
        calendar: Calendar = .current
    ) -> Bool {
        switch kind {
        case .logAtLeast(let count):
            return dayEvents.count >= count

        case .logDistinctFoods(let count):
            return Set(dayEvents.map(\.foodId)).count >= count

        case .logInMealSlot(let bucket):
            return dayEvents.contains { MealTimeBucket.bucket(for: $0.timestamp, calendar: calendar) == bucket }

        case .avoidMealSlot(let bucket):
            guard !dayEvents.isEmpty else { return false }
            return !dayEvents.contains { MealTimeBucket.bucket(for: $0.timestamp, calendar: calendar) == bucket }

        case .hitCalorieGoal:
            return goalStatus?.metCalorieGoal ?? false

        case .hitMacroGoal(let macro):
            return goalStatus?.met(macro) ?? false

        case .hitAllGoals:
            guard let goalStatus else { return false }
            return goalStatus.metCalorieGoal && goalStatus.metProteinGoal && goalStatus.metCarbGoal && goalStatus.metFatGoal

        case .tryNewFood:
            let priorFoodIds = Set(priorEvents.map(\.foodId))
            return dayEvents.contains { !priorFoodIds.contains($0.foodId) }

        case .logAllFourSlots:
            return Set(dayEvents.map { MealTimeBucket.bucket(for: $0.timestamp, calendar: calendar) }).count == MealTimeBucket.allCases.count

        case .earlyLog(let beforeHour):
            return dayEvents.contains { calendar.component(.hour, from: $0.timestamp) < beforeHour }

        case .lateLog(let afterHour):
            return dayEvents.contains { calendar.component(.hour, from: $0.timestamp) >= afterHour }
        }
    }
}

/// daily-challenges spec's selection rules, kept separate from
/// `DailyChallengeStore` so the picking logic itself is a pure, directly
/// testable function of (catalog, last-shown map, seed) -- the store's own
/// job is purely persistence.
public enum DailyChallengeSelection {
    /// Deterministic per `seed` (the nutrition-day string): the same seed
    /// always picks the same `count` templates from the same `catalog` +
    /// `lastShown` map, so reopening the app later the same day never
    /// re-rolls. Prefers templates not shown within `noRepeatDays`; if
    /// fewer than `count` qualify, fills the rest with the
    /// least-recently-shown remaining templates (never-shown treated as
    /// oldest) rather than leaving the day short.
    public static func pick(
        from catalog: [DailyChallengeTemplate],
        lastShown: [String: Date],
        seed: String,
        today: Date,
        noRepeatDays: Int,
        calendar: Calendar,
        count: Int
    ) -> [DailyChallengeTemplate] {
        guard !catalog.isEmpty else { return [] }

        let eligible = catalog.filter { template in
            guard let last = lastShown[template.id] else { return true }
            let days = calendar.dateComponents([.day], from: last, to: today).day ?? Int.max
            return days > noRepeatDays
        }
        let shuffledEligible = seededShuffle(eligible, seed: seed)
        guard shuffledEligible.count < count else {
            return Array(shuffledEligible.prefix(count))
        }

        let pickedIds = Set(shuffledEligible.map(\.id))
        let remainder = catalog
            .filter { !pickedIds.contains($0.id) }
            .sorted { (lastShown[$0.id] ?? .distantPast) < (lastShown[$1.id] ?? .distantPast) }
        return shuffledEligible + Array(remainder.prefix(count - shuffledEligible.count))
    }

    /// A small deterministic (non-cryptographic) hash-based shuffle, same
    /// rationale as `ChallengeRotation.pickNext`: the same seed always
    /// produces the same order, with no `Array.shuffled()` randomness.
    private static func seededShuffle(_ items: [DailyChallengeTemplate], seed: String) -> [DailyChallengeTemplate] {
        var pool = items.sorted { $0.id < $1.id }
        var hash = seed.unicodeScalars.reduce(UInt64(5381)) { ($0 &* 33) ^ UInt64($1.value) }
        var result: [DailyChallengeTemplate] = []
        result.reserveCapacity(pool.count)
        while !pool.isEmpty {
            hash = hash &* 6364136223846793005 &+ 1
            let index = Int(hash % UInt64(pool.count))
            result.append(pool.remove(at: index))
        }
        return result
    }
}
