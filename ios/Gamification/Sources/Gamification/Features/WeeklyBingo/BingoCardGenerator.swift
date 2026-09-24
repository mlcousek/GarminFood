// BingoCardGenerator.swift
//
// add-weekly-bingo design D3: composes one week's 3x3 card -- a pure
// function of (week, eligible tasks, previous week's card), so the same
// inputs give the same card on every device and in tests. The feature calls
// it ONCE per week and persists the result (D1): later catalog edits or data
// changes never alter a card that already exists.
//
// Steps:
//   1. eligible = tasks whose DataRequirement one of the last 14 days meets
//      (`eligibleTasks`), minus last week's tasks (dropped first if that
//      leaves too few);
//   2. seeded shuffle per difficulty ("bingo-<week>");
//   3. pick 2 hard, 3 medium, 3 easy, skipping a family already on the
//      card; a difficulty that runs short is filled from the next easier
//      one; the family rule is relaxed last;
//   4. seeded layout around the FREE centre, re-permuted (up to 16 times)
//      until no line holds two hard tasks.
//
// Depends on: BingoTask, BingoTaskCatalog, BingoLine, DeterministicRandom,
// WeekKey, DataRequirement. Depended on by: WeeklyBingoFeature,
// WeeklyBingoGeneratorTests.

import Foundation
import FoodLogCore

public enum BingoCardGenerator {
    public static let cardSize = 9
    public static let centreIndex = 4
    /// Non-centre positions, in reading order.
    static let taskPositions = [0, 1, 2, 3, 5, 6, 7, 8]
    /// Hardest first, so a shortfall cascades to the next easier difficulty.
    static let quota: [(difficulty: BingoDifficulty, count: Int)] = [(.hard, 2), (.medium, 3), (.easy, 3)]
    static let maxLayoutAttempts = 16
    /// How far back a task's data requirement is checked (design D3).
    public static let eligibilityWindowDays = 14

    public static func seed(week: WeekKey) -> String {
        "bingo-" + week.rawValue
    }

    /// Catalog tasks whose data requirement at least one of `recentDays`
    /// meets (tasks needing only logged entries are always eligible).
    public static func eligibleTasks(
        from catalog: [BingoTask] = BingoTaskCatalog.all,
        recentDays: [DaySignals]
    ) -> [BingoTask] {
        catalog.filter { $0.requirement.isSatisfied(byAnyOf: recentDays) }
    }

    /// Nine task ids, `BingoTaskCatalog.freeId` at index 4. Padded with
    /// FREE squares only if the eligible pool is smaller than eight tasks
    /// (never happens with the shipped catalog).
    public static func generate(week: WeekKey, eligible: [BingoTask], previousCard: [String]?) -> [String] {
        let previous = Set(previousCard ?? [])
        let fresh = eligible.filter { !previous.contains($0.id) }
        let needed = taskPositions.count

        var picks = pick(from: fresh, week: week, relaxFamilies: false)
        if picks.count < needed {
            picks = pick(from: eligible, week: week, relaxFamilies: false)
        }
        if picks.count < needed {
            picks = pick(from: eligible, week: week, relaxFamilies: true)
        }

        let layout = layoutPositions(for: picks, week: week)
        var card = Array(repeating: BingoTaskCatalog.freeId, count: cardSize)
        for (offset, task) in picks.prefix(needed).enumerated() {
            card[layout[offset]] = task.id
        }
        return card
    }

    // MARK: - Steps

    static func pick(from candidates: [BingoTask], week: WeekKey, relaxFamilies: Bool) -> [BingoTask] {
        var rng = DeterministicRandom(seed: seed(week: week))
        var pools: [BingoDifficulty: [BingoTask]] = [:]
        for difficulty in BingoDifficulty.allCases {
            let sorted = candidates.filter { $0.difficulty == difficulty }.sorted { $0.id < $1.id }
            pools[difficulty] = rng.shuffled(sorted)
        }

        var chosen: [BingoTask] = []
        var chosenIds = Set<String>()
        var families = Set<String>()
        var carry = 0
        for slot in quota {
            var need = slot.count + carry
            for task in pools[slot.difficulty] ?? [] {
                guard need > 0 else { break }
                guard !families.contains(task.family), !chosenIds.contains(task.id) else { continue }
                chosen.append(task)
                chosenIds.insert(task.id)
                families.insert(task.family)
                need -= 1
            }
            carry = need
        }

        if relaxFamilies {
            for difficulty in [BingoDifficulty.easy, .medium, .hard] {
                for task in pools[difficulty] ?? [] {
                    guard chosen.count < taskPositions.count else { break }
                    guard !chosenIds.contains(task.id) else { continue }
                    chosen.append(task)
                    chosenIds.insert(task.id)
                }
            }
        }
        return chosen
    }

    /// A position for each pick (same order as `picks`).
    static func layoutPositions(for picks: [BingoTask], week: WeekKey) -> [Int] {
        var rng = DeterministicRandom(seed: seed(week: week) + "-layout")
        var layout = taskPositions
        for _ in 0..<maxLayoutAttempts {
            layout = rng.shuffled(taskPositions)
            if !hardTasksShareLine(picks: picks, layout: layout) { break }
        }
        return layout
    }

    static func hardTasksShareLine(picks: [BingoTask], layout: [Int]) -> Bool {
        var hardPositions = Set<Int>()
        for (offset, task) in picks.enumerated() where task.difficulty == .hard && offset < layout.count {
            hardPositions.insert(layout[offset])
        }
        return BingoLine.all.contains { line in
            line.indices.filter { hardPositions.contains($0) }.count >= 2
        }
    }
}
