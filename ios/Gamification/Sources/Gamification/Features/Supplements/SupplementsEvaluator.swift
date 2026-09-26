// SupplementsEvaluator.swift
//
// add-supplements D9, task 6.3: one pure pass over the supplement digest
// and the feature's stored state, producing the new state, the badges that
// qualify, the journey milestones and collection entries reached for the
// first time, and what the Supplements screen shows (`SupplementsProgress`).
//
// Lifetime creatine totals outlive the 365-day digest through
// `SupplementsState.creatineByDay`: every digest day overwrites its entry
// (so an edit or a backfill anywhere in the window counts, and a day
// emptied again drops out), days older than the digest keep what they had.
// However long the app goes unopened, no day is lost as long as a run
// happens within a year of it.
//
// Everything counts history, including late entries (D14: late ticks count
// for badges and statistics, only the stack-complete XP grant ignores
// them). Badge rules (thresholds in SupplementsCatalog):
//   - First stack / Stack week / Full stack month: the longest supplement
//     streak ever (stored) reaches 1 / 7 / 30;
//   - Creatine 30 / 100: days with creatine (`creatineByDay`);
//   - Sunshine: vitamin D on 60 days of ONE October-March season;
//   - Omega month: omega-3 on 30 calendar days in a row;
//   - Never ran out: `refillsBeforeEmpty` >= 3;
//   - Alphabet 5 / 10: entries in the vitamin-alphabet collection.
//
// Depends on: FoodLogCore (SupplementSignals, SupplementDate),
// SupplementStreak, SupplementsCatalog,
// SupplementsState. Depended on by: SupplementsFeature.
// Tests: SupplementsGamificationTests.

import Foundation
import FoodLogCore

/// One vitamin-alphabet entry and the day it was first taken (`nil` =
/// not yet).
public struct SupplementCollectionEntry: Sendable, Equatable, Identifiable {
    public let ingredient: IngredientID
    public let firstDay: String?

    public var id: String { ingredient.rawValue }
    public var isCollected: Bool { firstDay != nil }
}

/// What the Supplements screen shows for the feature.
public struct SupplementsProgress: Sendable, Equatable {
    public let streak: SupplementStreak.Status
    /// The longest supplement streak ever (stored, beyond the digest).
    public let longestStreak: Int
    public let creatineGrams: Double
    public let creatineDays: Int
    /// Vitamin alphabet: every entry, with the day it was first taken.
    public let collection: [SupplementCollectionEntry]
    public let lastMilestone: SupplementJourneyMilestone?
    public let nextMilestone: SupplementJourneyMilestone?

    public var collectedCount: Int { collection.filter(\.isCollected).count }

    /// 0...1 from the last milestone (or 0 g) to the next; 1 when done.
    public var fractionToNext: Double {
        guard let nextMilestone else { return 1 }
        let start = lastMilestone?.grams ?? 0
        let span = nextMilestone.grams - start
        guard span > 0 else { return 1 }
        return min(1, max(0, (creatineGrams - start) / span))
    }
}

enum SupplementsEvaluator {
    struct Result: Equatable {
        var state: SupplementsState
        var badgeIds: [String]
        var newlyReached: [SupplementJourneyMilestone]
        var newlyCollected: [IngredientID]
        var progress: SupplementsProgress
    }

    static func evaluate(state old: SupplementsState, signals: SupplementSignals) -> Result {
        var state = old
        let days = signals.days.sorted { $0.day < $1.day }.filter { $0.day <= signals.today }

        // 1. Creatine per day: the digest is authoritative for its days.
        var creatine = state.creatineByDay ?? [:]
        for day in days {
            let grams = day.ingredients[.creatine] ?? 0
            creatine[day.day] = grams > 0 ? grams : nil
        }
        state.creatineByDay = creatine
        let creatineGrams = creatine.values.reduce(0, +)
        let creatineDays = creatine.count

        // 2. The vitamin alphabet (only grows; the earliest day wins).
        var collected = state.collected ?? [:]
        var newlyCollected: [IngredientID] = []
        for day in days {
            for ingredient in SupplementsCatalog.alphabet where day.took(ingredient) {
                if let known = collected[ingredient.rawValue] {
                    if day.day < known { collected[ingredient.rawValue] = day.day }
                } else {
                    collected[ingredient.rawValue] = day.day
                    newlyCollected.append(ingredient)
                }
            }
        }
        state.collected = collected

        // 3. The streak; the longest one is kept beyond the digest.
        let streak = SupplementStreak.status(signals)
        let longest = max(state.longestStreak ?? 0, streak.longest)
        state.longestStreak = longest

        // 4. The creatine journey.
        let reachedBefore = Set(state.reachedMilestones ?? [])
        let reached = SupplementsCatalog.journey.filter { creatineGrams >= $0.grams }
        let newlyReached = reached.filter { !reachedBefore.contains($0.id) }
        state.reachedMilestones = SupplementsCatalog.journey
            .map(\.id)
            .filter { reachedBefore.contains($0) || reached.map(\.id).contains($0) }

        // 5. Badges.
        var badges: [String] = []
        if longest >= 1 { badges.append(SupplementsCatalog.firstStackBadge) }
        if longest >= SupplementsCatalog.stackWeekDays { badges.append(SupplementsCatalog.stackWeekBadge) }
        if longest >= SupplementsCatalog.fullStackMonthDays { badges.append(SupplementsCatalog.fullStackMonthBadge) }
        if creatineDays >= SupplementsCatalog.creatineDayThresholds[0] { badges.append(SupplementsCatalog.creatine30Badge) }
        if creatineDays >= SupplementsCatalog.creatineDayThresholds[1] { badges.append(SupplementsCatalog.creatine100Badge) }
        if bestSeasonDays(days, ingredient: .vitaminD) >= SupplementsCatalog.sunshineDays { badges.append(SupplementsCatalog.sunshineBadge) }
        if longestRun(days, ingredient: .omega3EPA_DHA) >= SupplementsCatalog.omegaRunDays { badges.append(SupplementsCatalog.omegaMonthBadge) }
        if signals.refillsBeforeEmpty >= SupplementsCatalog.neverRanOutRefills { badges.append(SupplementsCatalog.neverRanOutBadge) }
        if collected.count >= SupplementsCatalog.alphabetThresholds[0] { badges.append(SupplementsCatalog.alphabet5Badge) }
        if collected.count >= SupplementsCatalog.alphabetThresholds[1] { badges.append(SupplementsCatalog.alphabet10Badge) }

        let progress = SupplementsProgress(
            streak: streak,
            longestStreak: longest,
            creatineGrams: creatineGrams,
            creatineDays: creatineDays,
            collection: SupplementsCatalog.alphabet.map { SupplementCollectionEntry(ingredient: $0, firstDay: collected[$0.rawValue]) },
            lastMilestone: reached.last,
            nextMilestone: SupplementsCatalog.journey.first { creatineGrams < $0.grams }
        )
        return Result(state: state, badgeIds: badges, newlyReached: newlyReached, newlyCollected: newlyCollected, progress: progress)
    }

    /// The October-March season a day belongs to (the year its October
    /// falls in), or `nil` for April-September.
    static func season(of day: String) -> Int? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        let (year, month) = (parts[0], parts[1])
        if month >= 10 { return year }
        if month <= 3 { return year - 1 }
        return nil
    }

    /// The most days with `ingredient` in any one October-March season.
    static func bestSeasonDays(_ days: [SupplementDaySignal], ingredient: IngredientID) -> Int {
        var perSeason: [Int: Int] = [:]
        for day in days where day.took(ingredient) {
            guard let season = season(of: day.day) else { continue }
            perSeason[season, default: 0] += 1
        }
        return perSeason.values.max() ?? 0
    }

    /// The longest run of consecutive calendar days with `ingredient`.
    static func longestRun(_ days: [SupplementDaySignal], ingredient: IngredientID) -> Int {
        var longest = 0
        var running = 0
        var previous: String?
        for day in days where day.took(ingredient) {
            if let previous, SupplementDate.adding(1, to: previous) == day.day {
                running += 1
            } else {
                running = 1
            }
            longest = max(longest, running)
            previous = day.day
        }
        return longest
    }
}
