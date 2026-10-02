// TrainingProgressModel.swift
//
// add-training-gamification-and-150-levels (design D10): what the Progress
// tab's training section shows, as a pure value with its text already
// localized, so the SwiftUI view only draws it and the content is
// unit-tested here (the app's views are not).
//
//   - `thisWeek`: check-ins, kept plan days and strength sessions of the
//     plan's current ISO week (empty without the plan's facts);
//   - `streaks`: the current check-in streak, the current habit streak and
//     the run of weeks kept within plan -- numbers of days or weeks, with
//     the unit in the title, so no plural form is needed;
//   - `ladders`: every listed ladder of TrainingProgressCatalog with its
//     count, its next step and how far along it is.
//
// The counts come from TrainingRewardsStore (so they cover the whole
// history, not just the weeks the plan file carries); "kept" is
// TrainingXPRules' verdict, the same one the XP uses.
//
// Depends on: TrainingProgressCatalog, TrainingRewardCounts,
// TrainingProgress, TrainingPlanSignals, TrainingXPRules.
// Depended on by: TrainingRewardsFeature.progressModel(), the app's
// TrainingProgressSlotView. Tests: TrainingProgressTests.

import Foundation

public struct TrainingProgressModel: Sendable, Equatable {
    /// One number with its label ("Check-ins this week", "5/7").
    public struct Stat: Sendable, Equatable, Identifiable {
        public let id: String
        public let title: String
        public let value: String
        /// An SF Symbol name.
        public let symbol: String
    }

    /// One ladder: its count and the way to its next badge.
    public struct LadderRow: Sendable, Equatable, Identifiable {
        public let id: String
        public let title: String
        public let symbol: String
        public let count: Int
        /// The next tier's threshold; `nil` when every tier is reached.
        public let nextThreshold: Int?
        /// 0...1 from the previous tier (or 0) to the next; 1 when complete.
        public let fraction: Double
        /// "31 · next: 100" or "100 · complete".
        public let detail: String
        /// Tiers reached / tiers in all.
        public let tiersReached: Int
        public let tierCount: Int

        public var isComplete: Bool { nextThreshold == nil }
    }

    public let thisWeek: [Stat]
    public let streaks: [Stat]
    public let ladders: [LadderRow]

    public static let empty = TrainingProgressModel(thisWeek: [], streaks: [], ladders: [])

    /// Training badges reached / all listed training badge tiers.
    public var tiersReached: Int { ladders.reduce(0) { $0 + $1.tiersReached } }
    public var tierCount: Int { ladders.reduce(0) { $0 + $1.tierCount } }

    /// The ladders closest to their next badge, for the compact card:
    /// unfinished ones, the furthest along first (ties in display order).
    public func highlights(limit: Int = 3) -> [LadderRow] {
        let open = ladders.enumerated().filter { !$0.element.isComplete }
        let sorted = open.sorted { lhs, rhs in
            if lhs.element.fraction != rhs.element.fraction { return lhs.element.fraction > rhs.element.fraction }
            return lhs.offset < rhs.offset
        }
        return sorted.prefix(max(0, limit)).map { $0.element }
    }

    public static func build(
        counts: TrainingRewardCounts,
        progress: TrainingProgress,
        plan: TrainingPlanSignals?
    ) -> TrainingProgressModel {
        TrainingProgressModel(
            thisWeek: plan.map(thisWeekStats) ?? [],
            streaks: streakStats(progress),
            ladders: TrainingProgressCatalog.ladders.filter(\.isListed).map { row($0, counts: counts, progress: progress) }
        )
    }

    static func thisWeekStats(_ plan: TrainingPlanSignals) -> [Stat] {
        guard let week = TrainingRewardsCatalog.isoWeek(ofDay: plan.today) else { return [] }
        let days = plan.days.filter { TrainingRewardsCatalog.isoWeek(ofDay: $0.day) == week }
        let checkIns = days.filter(\.isCheckedIn).count
        let kept = days.filter { TrainingXPRules.judge($0, today: plan.today) == .kept }.count
        let strength = days.reduce(0) { sum, day in
            sum + day.sessions.filter { $0.isDone && $0.isStrength }.count
        }
        let gym = min(strength, TrainingRewardsFeature.gymSessionsPerWeek)
        return [
            Stat(
                id: "checkins",
                title: String(localized: "Check-ins this week", bundle: .module, comment: "Progress tab, training section: label of the number of morning check-ins this week (shown as n/7)."),
                value: "\(checkIns)/7",
                symbol: "sunrise.fill"
            ),
            Stat(
                id: "kept",
                title: String(localized: "Plan days kept this week", bundle: .module, comment: "Progress tab, training section: label of the number of days this week on which the plan was followed, rest days included (shown as n/7)."),
                value: "\(kept)/7",
                symbol: "calendar"
            ),
            Stat(
                id: "gym",
                title: String(localized: "Strength sessions this week", bundle: .module, comment: "Progress tab, training section: label of the strength sessions done this week (shown as n/2)."),
                value: "\(gym)/\(TrainingRewardsFeature.gymSessionsPerWeek)",
                symbol: "dumbbell.fill"
            ),
        ]
    }

    static func streakStats(_ progress: TrainingProgress) -> [Stat] {
        [
            Stat(
                id: "checkin-streak",
                title: String(localized: "Check-in streak (days)", bundle: .module, comment: "Progress tab, training section: label of the number of days in a row with a morning check-in. The value is a bare number."),
                value: String(progress.checkInStreak),
                symbol: "sunrise.fill"
            ),
            Stat(
                id: "habit-streak",
                title: String(localized: "Habit streak (days)", bundle: .module, comment: "Progress tab, training section: label of the number of days in a row with the habits done. The value is a bare number."),
                value: String(progress.habitStreak.current),
                symbol: "flame.fill"
            ),
            Stat(
                id: "week-streak",
                title: String(localized: "Weeks kept in a row", bundle: .module, comment: "Progress tab, training section: label of the number of consecutive weeks closed within the plan. The value is a bare number."),
                value: String(progress.keptWeekStreak),
                symbol: "calendar.badge.checkmark"
            ),
        ]
    }

    static func row(_ ladder: TrainingLadder, counts: TrainingRewardCounts, progress: TrainingProgress) -> LadderRow {
        let count = ladder.count(counts: counts, progress: progress)
        let thresholds = ladder.tiers.map(\.threshold).sorted()
        let next = thresholds.first { count < $0 }
        let previous = thresholds.last { count >= $0 } ?? 0
        var fraction = 1.0
        let detail: String
        if let next {
            let span = next - previous
            fraction = span > 0 ? min(max(Double(count - previous) / Double(span), 0), 1) : 0
            detail = String(
                format: String(localized: "%lld · next: %lld", bundle: .module, comment: "Progress tab, a training ladder: first %lld = the count so far, second = the count the next badge needs."),
                count, next
            )
        } else {
            detail = String(
                format: String(localized: "%lld · complete", bundle: .module, comment: "Progress tab, a training ladder with every badge earned: %lld = the count so far."),
                count
            )
        }
        return LadderRow(
            id: ladder.id,
            title: ladder.title,
            symbol: ladder.symbol,
            count: count,
            nextThreshold: next,
            fraction: fraction,
            detail: detail,
            tiersReached: thresholds.filter { count >= $0 }.count,
            tierCount: thresholds.count
        )
    }
}
