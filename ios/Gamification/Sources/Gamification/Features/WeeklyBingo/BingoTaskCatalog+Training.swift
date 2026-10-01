// BingoTaskCatalog+Training.swift
//
// add-training-gamification-and-150-levels (design D9): the eight bingo
// squares of the training experience, and how they are judged. They join
// the pool a NEW card is drawn from only in that experience and only with
// the plan's facts (`WeeklyBingoFeature.cardForWeek`); `BingoTaskCatalog.all`
// stays the 35 food tasks, so food-first cards never see one. A card already
// running keeps its squares.
//
// Every square is about following the plan or writing it down: check-ins,
// full habit days, kept plan days (rest days count), both strength
// sessions, a rated session. None asks for more training than planned, and
// none asks for an amber or red morning.
//
// They are judged from `TrainingPlanSignals` (`TrainingBingoRule`,
// `BingoEvaluator.trainingCompletionDay`), not from the food snapshot: a
// square is done on the first day of the card's week on which its count is
// reached. "Kept" is TrainingXPRules' verdict, the one the XP uses. The
// kept-day squares are `judgesCompletedDaysOnly`, so a Sunday rest day --
// which is only kept once it is over -- still ticks last week's card on
// Monday.
//
// The fuelling squares of this experience are the existing carbohydrate and
// protein goal squares: their goal status is already judged by the day's
// fuel band there.
//
// Ids ("t-…") are persisted in cards and never reused.
//
// Depends on: BingoTask, TrainingPlanSignals, TrainingXPRules.
// Depended on by: BingoTaskCatalog.task(id:), BingoEvaluator,
// WeeklyBingoFeature. Tests: TrainingVariantsTests.

import Foundation

/// A bingo rule over the plan's facts: a count reached within the card's
/// week so far.
public enum TrainingBingoRule: Sendable, Equatable {
    /// Days with a morning check-in.
    case checkInDays(Int)
    /// Days with every expected habit done.
    case fullHabitDays(Int)
    /// Kept plan days (rest days included).
    case keptDays(Int)
    /// Strength sessions done.
    case strengthSessions(Int)
    /// Done sessions with an effort rating.
    case ratedSessions(Int)

    var target: Int {
        switch self {
        case .checkInDays(let count), .fullHabitDays(let count), .keptDays(let count),
             .strengthSessions(let count), .ratedSessions(let count):
            return count
        }
    }

    /// What `day` adds to the count, as of the plan's today.
    func value(of day: TrainingPlanSignals.Day, today: String) -> Int {
        switch self {
        case .checkInDays:
            return day.isCheckedIn ? 1 : 0
        case .fullHabitDays:
            let expected = Set(day.habitsExpected)
            return !expected.isEmpty && expected.isSubset(of: day.habitsDone) ? 1 : 0
        case .keptDays:
            return TrainingXPRules.judge(day, today: today) == .kept ? 1 : 0
        case .strengthSessions:
            return day.sessions.filter { $0.isDone && $0.isStrength }.count
        case .ratedSessions:
            return day.sessions.filter { $0.isDone && $0.hasRPE }.count
        }
    }
}

extension BingoTaskCatalog {
    /// The training experience's squares: 3 easy, 3 medium, 2 hard.
    public static let training: [BingoTask] = [
        BingoTask(
            id: "t-habit-day",
            title: String(localized: "All Boxes Ticked", bundle: .module, comment: "Bingo task title (training experience): every habit of one day done."),
            detail: String(localized: "Do every habit of one day.", bundle: .module, comment: "Bingo task rule."),
            difficulty: .easy, family: "training-habits",
            scope: .training(.fullHabitDays(1)),
            symbol: "checklist"
        ),
        BingoTask(
            id: "t-day-kept",
            title: String(localized: "Just the Plan", bundle: .module, comment: "Bingo task title (training experience): one day on which the plan was followed."),
            detail: String(localized: "Keep the day's plan once this week. A rest day counts.", bundle: .module, comment: "Bingo task rule."),
            difficulty: .easy, family: "training-plan",
            scope: .training(.keptDays(1)),
            symbol: "calendar",
            judgesCompletedDaysOnly: true
        ),
        BingoTask(
            id: "t-rpe",
            title: String(localized: "How Did It Feel?", bundle: .module, comment: "Bingo task title (training experience): rate a session's effort after doing it."),
            detail: String(localized: "Rate a session after you do it.", bundle: .module, comment: "Bingo task rule."),
            difficulty: .easy, family: "training-feedback",
            scope: .training(.ratedSessions(1)),
            symbol: "gauge.medium"
        ),
        BingoTask(
            id: "t-checkin-5",
            title: String(localized: "Morning Roll Call", bundle: .module, comment: "Bingo task title (training experience): five morning check-ins in the week."),
            detail: String(localized: "Check in on 5 mornings this week.", bundle: .module, comment: "Bingo task rule."),
            difficulty: .medium, family: "training-checkin",
            scope: .training(.checkInDays(5)),
            symbol: "sunrise.fill"
        ),
        BingoTask(
            id: "t-habit-days-3",
            title: String(localized: "Three Tidy Days", bundle: .module, comment: "Bingo task title (training experience): every habit done on three days of the week."),
            detail: String(localized: "Do every habit on 3 days this week.", bundle: .module, comment: "Bingo task rule."),
            difficulty: .medium, family: "training-habits",
            scope: .training(.fullHabitDays(3)),
            symbol: "checklist"
        ),
        BingoTask(
            id: "t-gym-2",
            title: String(localized: "Both Gym Days", bundle: .module, comment: "Bingo task title (training experience): both strength sessions of the week done."),
            detail: String(localized: "Do both strength sessions this week.", bundle: .module, comment: "Bingo task rule."),
            difficulty: .medium, family: "training-gym",
            scope: .training(.strengthSessions(2)),
            symbol: "dumbbell.fill"
        ),
        BingoTask(
            id: "t-checkin-7",
            title: String(localized: "Every Single Morning", bundle: .module, comment: "Bingo task title (training experience): a morning check-in on all seven days."),
            detail: String(localized: "Check in on all 7 mornings this week.", bundle: .module, comment: "Bingo task rule."),
            difficulty: .hard, family: "training-checkin",
            scope: .training(.checkInDays(7)),
            symbol: "sun.max.fill"
        ),
        BingoTask(
            id: "t-days-kept-5",
            title: String(localized: "Five by the Plan", bundle: .module, comment: "Bingo task title (training experience): five days of the week on which the plan was followed."),
            detail: String(localized: "Keep the day's plan on 5 days this week. Rest days count.", bundle: .module, comment: "Bingo task rule."),
            difficulty: .hard, family: "training-plan",
            scope: .training(.keptDays(5)),
            symbol: "calendar.badge.checkmark",
            judgesCompletedDaysOnly: true
        ),
    ]
}

extension BingoEvaluator {
    /// The first of `dayKeys` (the card's week up to today, oldest first)
    /// on which `rule`'s count over the week so far reaches its target.
    public static func trainingCompletionDay(
        _ rule: TrainingBingoRule,
        dayKeys: [String],
        plan: TrainingPlanSignals
    ) -> String? {
        guard rule.target > 0 else { return nil }
        var count = 0
        for key in dayKeys {
            guard let day = plan.day(key) else { continue }
            count += rule.value(of: day, today: plan.today)
            if count >= rule.target { return key }
        }
        return nil
    }
}
