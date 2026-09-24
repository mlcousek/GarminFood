// SignalEvaluator.swift
//
// The ONLY interpreter of `DayPredicate`/`WeekPredicate` (design D6), so a
// bingo square, a boss rule and a creative challenge that say the same thing
// can never disagree about whether a day counted.
//
// Three-valued on purpose: `evaluate` returns `nil` when the day's data does
// not allow an answer (no water read, an entry with unknown fibre, too few
// entries for a "none of X" rule). `holds` maps unknown to `false` -- the
// day does not count -- but callers that show per-day results (boss, bingo)
// use `evaluate` so an unknown day is shown as "no data", never as failed
// (spec: "A day without macro data").
//
// Times of day are measured from the day's `date` (its start) in the given
// calendar, so an entry at 01:00 that belongs to the previous nutrition day
// (04:00 boundary) is "25:00" of that day, never "before 09:00".
//
// Depends on: DayPredicate, WeekPredicate, FoodLogCore (DaySignals,
// SignalsSnapshot, SearchText).
// Depended on by: ChallengeEngine (signal kinds), wave-2 features.

import Foundation
import FoodLogCore

public enum SignalEvaluator {
    // MARK: - Day

    /// `true` only when the predicate definitely holds on `day`.
    public static func holds(
        _ predicate: DayPredicate,
        on day: DaySignals,
        history: SignalsSnapshot,
        calendar: Calendar
    ) -> Bool {
        evaluate(predicate, on: day, history: history, calendar: calendar) == true
    }

    /// `true`/`false`, or `nil` when the day's data cannot answer.
    public static func evaluate(
        _ predicate: DayPredicate,
        on day: DaySignals,
        history: SignalsSnapshot,
        calendar: Calendar
    ) -> Bool? {
        switch predicate {
        case .hasTag(let tag):
            return day.entries.contains { $0.tags.contains(tag) }

        case .tagCountAtLeast(let tag, let count):
            return day.entries.filter { $0.tags.contains(tag) }.count >= count

        case .anyTagCountAtLeast(let tags, let count):
            let wanted = Set(tags)
            return day.entries.filter { !$0.tags.isDisjoint(with: wanted) }.count >= count

        case .distinctTagsAtLeast(let prefix, let count):
            return day.allTags.filter { $0.hasPrefix(prefix) }.count >= count

        case .noTag(let tag, let minEntries):
            guard day.entries.count >= max(minEntries, 1) else { return nil }
            return !day.entries.contains { $0.tags.contains(tag) }

        case .tagInMeal(let tag, let meal):
            return day.entries.contains { $0.meal == meal && $0.tags.contains(tag) }

        case .mealLogged(let meal):
            return day.entries.contains { $0.meal == meal }

        case .firstLogBefore(let hour, let minute):
            guard let first = day.firstLog,
                  let limit = timeOfDay(hour: hour, minute: minute, on: day, calendar: calendar)
            else { return day.hasEntries ? nil : false }
            return first < limit

        case .lastLogBefore(let hour, let minute):
            guard let last = day.lastLog,
                  let limit = timeOfDay(hour: hour, minute: minute, on: day, calendar: calendar)
            else { return day.hasEntries ? nil : false }
            return last < limit

        case .distinctFoodsAtLeast(let count):
            return Set(day.entries.map(\.foodId)).count >= count

        case .goalMet(let macro):
            guard let status = day.goalStatus else { return nil }
            return status.met(macro)

        case .macroAtLeast(let macro, let grams):
            guard day.hasEntries else { return false }
            guard let value = macro.value(in: day.totals) else { return nil }
            return value >= grams

        case .macroAtMost(let macro, let grams, let minEntries):
            guard day.entries.count >= max(minEntries, 1) else { return nil }
            guard let value = macro.value(in: day.totals) else { return nil }
            return value <= grams

        case .waterGoalMet:
            guard day.availability.hasWater, let water = day.waterML,
                  let goal = day.waterGoalML, goal > 0
            else { return nil }
            return water >= goal

        case .hasActivity(let minMinutes):
            guard day.availability.hasActivities else { return nil }
            return day.activities.contains { $0.durationMinutes >= Double(minMinutes) }

        case .proteinAfterActivity(let grams, let withinMinutes):
            guard day.availability.hasActivities else { return nil }
            var sawUnknown = false
            for activity in day.activities {
                let windowEnd = activity.end.addingTimeInterval(Double(withinMinutes) * 60)
                let after = day.entries.filter { $0.timestamp >= activity.end && $0.timestamp <= windowEnd }
                let known = after.compactMap(\.protein).reduce(0, +)
                if known >= grams { return true }
                if after.contains(where: { $0.protein == nil }) { sawUnknown = true }
            }
            return sawUnknown ? nil : false

        case .newFood:
            return day.entries.contains { history.firstSeenDayByFood[$0.foodId] == day.day }

        case .newCzechBrand:
            return day.entries.contains { entry in
                guard entry.tags.contains(.czechBrand), let key = czechBrandKey(entry) else { return false }
                return history.firstSeenDayByCzechBrand[key] == day.day
            }

        case .all(let predicates):
            var sawUnknown = false
            for inner in predicates {
                switch evaluate(inner, on: day, history: history, calendar: calendar) {
                case .some(false): return false
                case .none: sawUnknown = true
                case .some(true): break
                }
            }
            return sawUnknown ? nil : true

        case .any(let predicates):
            var sawUnknown = false
            for inner in predicates {
                switch evaluate(inner, on: day, history: history, calendar: calendar) {
                case .some(true): return true
                case .none: sawUnknown = true
                case .some(false): break
                }
            }
            return sawUnknown ? nil : false
        }
    }

    // MARK: - Span of days

    /// Progress of a week predicate over `days` (data-bearing days only;
    /// pass `snapshot.days(keys)`), capped at the target.
    public static func progress(
        _ predicate: WeekPredicate,
        over days: [DaySignals],
        history: SignalsSnapshot,
        calendar: Calendar
    ) -> Int {
        min(rawCount(predicate, over: days, history: history, calendar: calendar), predicate.target)
    }

    public static func holds(
        _ predicate: WeekPredicate,
        over days: [DaySignals],
        history: SignalsSnapshot,
        calendar: Calendar
    ) -> Bool {
        rawCount(predicate, over: days, history: history, calendar: calendar) >= predicate.target
    }

    /// Days among `days` on which `predicate` holds.
    public static func daysSatisfying(
        _ predicate: DayPredicate,
        in days: [DaySignals],
        history: SignalsSnapshot,
        calendar: Calendar
    ) -> [DaySignals] {
        days.filter { holds(predicate, on: $0, history: history, calendar: calendar) }
    }

    static func rawCount(
        _ predicate: WeekPredicate,
        over days: [DaySignals],
        history: SignalsSnapshot,
        calendar: Calendar
    ) -> Int {
        switch predicate {
        case .daysSatisfying(let dayPredicate, _):
            return daysSatisfying(dayPredicate, in: days, history: history, calendar: calendar).count

        case .distinctTagsAcrossWeek(let prefix, _):
            var tags = Set<FoodTag>()
            for day in days {
                for tag in day.allTags where tag.hasPrefix(prefix) { tags.insert(tag) }
            }
            return tags.count

        case .distinctCzechBrandsAtLeast:
            var brands = Set<String>()
            for day in days {
                for entry in day.entries where entry.tags.contains(.czechBrand) {
                    if let key = czechBrandKey(entry) { brands.insert(key) }
                }
            }
            return brands.count

        case .newFoodsAtLeast:
            var foods = Set<String>()
            for day in days {
                for entry in day.entries where history.firstSeenDayByFood[entry.foodId] == day.day {
                    foods.insert(entry.foodId)
                }
            }
            return foods.count
        }
    }

    // MARK: - Helpers

    /// The folded brand -- the same key `DaySignalsBuilder` uses for
    /// `firstSeenDayByCzechBrand`. `nil` for an entry without a brand.
    public static func czechBrandKey(_ entry: SignalEntry) -> String? {
        guard let brand = entry.brand, !brand.isEmpty else { return nil }
        let folded = SearchText.foldedPhrase(brand)
        return folded.isEmpty ? nil : folded
    }

    static func timeOfDay(hour: Int, minute: Int, on day: DaySignals, calendar: Calendar) -> Date? {
        calendar.date(byAdding: DateComponents(hour: hour, minute: minute), to: calendar.startOfDay(for: day.date))
    }
}

extension SignalGoalStatus {
    /// Mirrors `DailyGoalStatus.met(_:)`.
    public func met(_ macro: GoalMacro) -> Bool {
        switch macro {
        case .calories: return metCalorieGoal
        case .protein: return metProteinGoal
        case .carbs: return metCarbGoal
        case .fat: return metFatGoal
        }
    }
}
