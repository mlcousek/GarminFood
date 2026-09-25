// BingoEvaluator.swift
//
// add-weekly-bingo design D4 + D5: which squares of a card are done and
// which lines that makes. Pure, over `SignalsSnapshot`, so every rule is
// testable with literal `DaySignals`.
//
// - Only the card's own ISO week counts, and only up to `today`: fish
//   logged the Sunday before a card's Monday never ticks that card.
// - A day-scoped square records the FIRST day of the week its rule held; a
//   week-scoped one the first day the week-so-far satisfied it.
// - Sticky: completions are merged into the stored ones, never removed, so
//   deleting the entry that ticked a square leaves it done (and rewards are
//   never taken back).
// - A stored id that is no longer in the catalog is treated as FREE
//   (defensive -- ids are never removed on purpose).
//
// Depends on: BingoTaskCatalog, SignalEvaluator, WeekKey, FoodLogCore.
// Depended on by: WeeklyBingoFeature, BingoCardGenerator (lines),
// WeeklyBingoEvaluatorTests.

import Foundation
import FoodLogCore

/// One of the eight bingo lines. The free centre counts as complete.
public struct BingoLine: Sendable, Equatable, Hashable, Identifiable {
    public enum Kind: String, Sendable, Equatable, Hashable {
        case row, column, diagonal
    }

    public let kind: Kind
    /// 1-based within its kind (row 1 is the top row; diagonal 1 runs from
    /// the top-left corner, diagonal 2 from the top-right).
    public let number: Int
    /// Square indices 0...8, reading order.
    public let indices: [Int]

    /// Persisted id and reward-key component: "row0", "col2", "diag1".
    public var id: String {
        switch kind {
        case .row: return "row\(number - 1)"
        case .column: return "col\(number - 1)"
        case .diagonal: return "diag\(number - 1)"
        }
    }

    public var displayName: String {
        switch kind {
        case .row:
            return String(format: String(localized: "Row %lld", bundle: .module, comment: "Bingo line name. %lld = 1, 2 or 3 (top to bottom)."), number)
        case .column:
            return String(format: String(localized: "Column %lld", bundle: .module, comment: "Bingo line name. %lld = 1, 2 or 3 (left to right)."), number)
        case .diagonal:
            return String(format: String(localized: "Diagonal %lld", bundle: .module, comment: "Bingo line name. %lld = 1 (from top-left) or 2 (from top-right)."), number)
        }
    }

    public static let all: [BingoLine] = [
        BingoLine(kind: .row, number: 1, indices: [0, 1, 2]),
        BingoLine(kind: .row, number: 2, indices: [3, 4, 5]),
        BingoLine(kind: .row, number: 3, indices: [6, 7, 8]),
        BingoLine(kind: .column, number: 1, indices: [0, 3, 6]),
        BingoLine(kind: .column, number: 2, indices: [1, 4, 7]),
        BingoLine(kind: .column, number: 3, indices: [2, 5, 8]),
        BingoLine(kind: .diagonal, number: 1, indices: [0, 4, 8]),
        BingoLine(kind: .diagonal, number: 2, indices: [2, 4, 6]),
    ]

    public static func line(id: String) -> BingoLine? {
        all.first { $0.id == id }
    }
}

public enum BingoEvaluator {
    public static let cornerIndices: Set<Int> = [0, 2, 6, 8]

    /// FREE centre, or an id no longer in the catalog.
    public static func isFree(_ taskId: String) -> Bool {
        taskId == BingoTaskCatalog.freeId || BingoTaskCatalog.task(id: taskId) == nil
    }

    /// The stored completions plus any square that newly holds on a day of
    /// `week` up to `today` (a `yyyy-MM-dd` key). Index -> completion day.
    ///
    /// A task that `judgesCompletedDaysOnly` sees only days BEFORE `today`
    /// (a later entry today could still break it). `onlyCompletedDayTasks`
    /// restricts the pass to those squares -- `WeeklyBingoFeature` uses it to
    /// settle last week's Sunday, leaving every other square as it was.
    public static func completions(
        taskIds: [String],
        week: WeekKey,
        today: String,
        snapshot: SignalsSnapshot,
        calendar: Calendar,
        stored: [Int: String],
        onlyCompletedDayTasks: Bool = false
    ) -> [Int: String] {
        var result = stored
        let keys = week.dayKeys(calendar: calendar).filter { $0 <= today }
        let days = snapshot.days(keys)
        let completedDays = days.filter { $0.day < today }
        for (index, taskId) in taskIds.enumerated() where result[index] == nil {
            guard let task = BingoTaskCatalog.task(id: taskId) else { continue }
            if onlyCompletedDayTasks && !task.judgesCompletedDaysOnly { continue }
            let candidates = task.judgesCompletedDaysOnly ? completedDays : days
            guard !candidates.isEmpty else { continue }
            if let day = completionDay(of: task, days: candidates, history: snapshot, calendar: calendar) {
                result[index] = day
            }
        }
        return result
    }

    /// The first of `days` (oldest first) on which `task` became done.
    public static func completionDay(
        of task: BingoTask,
        days: [DaySignals],
        history: SignalsSnapshot,
        calendar: Calendar
    ) -> String? {
        switch task.scope {
        case .day(let predicate):
            return days.first { SignalEvaluator.holds(predicate, on: $0, history: history, calendar: calendar) }?.day
        case .week(let predicate):
            for end in days.indices where SignalEvaluator.holds(predicate, over: Array(days[...end]), history: history, calendar: calendar) {
                return days[end].day
            }
            return nil
        }
    }

    /// Indices counted as done: FREE squares plus recorded completions.
    public static func doneIndices(taskIds: [String], completed: [Int: String]) -> Set<Int> {
        var done = Set<Int>()
        for (index, taskId) in taskIds.enumerated() where isFree(taskId) || completed[index] != nil {
            done.insert(index)
        }
        return done
    }

    public static func completedLines(taskIds: [String], completed: [Int: String]) -> [BingoLine] {
        let done = doneIndices(taskIds: taskIds, completed: completed)
        return BingoLine.all.filter { line in line.indices.allSatisfy { done.contains($0) } }
    }

    public static func isFull(taskIds: [String], completed: [Int: String]) -> Bool {
        taskIds.count == BingoCardGenerator.cardSize
            && doneIndices(taskIds: taskIds, completed: completed).count == BingoCardGenerator.cardSize
    }

    public static func hasFourCorners(taskIds: [String], completed: [Int: String]) -> Bool {
        cornerIndices.isSubset(of: doneIndices(taskIds: taskIds, completed: completed))
    }

    // MARK: - Reward keys (RewardLedger namespace "bingo.")

    public static func lineGrantKey(week: WeekKey, line: BingoLine) -> String {
        "\(WeeklyBingoFeature.id).line.\(week.rawValue).\(line.id)"
    }

    public static func fullCardGrantKey(week: WeekKey) -> String {
        "\(WeeklyBingoFeature.id).full.\(week.rawValue)"
    }

    public static func freezeGrantKey(week: WeekKey) -> String {
        "\(WeeklyBingoFeature.id).freeze.\(week.rawValue)"
    }
}
