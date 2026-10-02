// TrainingRewardFacts.swift
//
// add-winter-arc-nutrition-and-rewards (D1): the plain facts the training
// rewards are built on, read from the plan the phone already shows -- the
// projection with the phone's own check-ins, ticks and pending edits
// applied (`TrainingSnapshot`). Nothing is computed that the vault
// computes (adherence, matching, the done option): each fact is read
// straight off a day, a session or a week.
//
// Per day (only days up to `today`):
//   - `checkedIn`: the morning check-in exists (`light` from a check-in --
//     the vault's `lightSource: checkin`, or the phone's own check-in,
//     which the overlay applies the same way);
//   - `honestLightFollowed`: the check-in was amber or red AND a traffic-
//     light session that day was done with exactly that option (the
//     vault's `done.option`) -- being honest and then doing the easier
//     thing is what the plan wants rewarded;
//   - `strengthSessionsDone`: strength sessions (sport or type) done
//     (`status: done` or a `done` block);
//   - `habitTicks`: habits counted done that day (the phone's tick, else
//     the projection's count -- `TrainingSnapshot.habitDone`).
// Per week (written weeks only):
//   - `strengthSessionsDone`: the sum of its days;
//   - `keptWithinPlan`: only when the projection says the week is
//     `closed` and its `actual` shows no missed session and at least one
//     done, and the run volume didn't overshoot the target by more than
//     `volumeTolerance` (10 %) when both are known. An open week is never
//     judged.
//
// Gamification never imports TrainingCore (nor the reverse): the app's
// adapter copies these facts into Gamification's `TrainingSignals`.
//
// Pure. Depended on by: the app's TrainingRewardsAdapter. Tests:
// TrainingRewardFactsTests.

import Foundation

public struct TrainingDayFact: Equatable, Sendable {
    public let date: LocalDate
    public let checkedIn: Bool
    public let honestLightFollowed: Bool
    public let strengthSessionsDone: Int
    public let habitTicks: Int

    public init(date: LocalDate, checkedIn: Bool, honestLightFollowed: Bool, strengthSessionsDone: Int, habitTicks: Int) {
        self.date = date
        self.checkedIn = checkedIn
        self.honestLightFollowed = honestLightFollowed
        self.strengthSessionsDone = strengthSessionsDone
        self.habitTicks = habitTicks
    }
}

public struct TrainingWeekFact: Equatable, Sendable {
    public let week: ISOWeek
    public let isClosed: Bool
    public let keptWithinPlan: Bool
    public let strengthSessionsDone: Int

    public init(week: ISOWeek, isClosed: Bool, keptWithinPlan: Bool, strengthSessionsDone: Int) {
        self.week = week
        self.isClosed = isClosed
        self.keptWithinPlan = keptWithinPlan
        self.strengthSessionsDone = strengthSessionsDone
    }
}

public struct TrainingRewardFacts: Equatable, Sendable {
    /// A closed week may run this much over its run-km target and still be
    /// "within plan" (GPS noise, a warm-up jog).
    public static let volumeTolerance = 0.10

    public let today: LocalDate
    /// Oldest first.
    public let days: [TrainingDayFact]
    /// Oldest first.
    public let weeks: [TrainingWeekFact]

    public init(today: LocalDate, days: [TrainingDayFact], weeks: [TrainingWeekFact]) {
        self.today = today
        self.days = days
        self.weeks = weeks
    }

    public static func build(snapshot: TrainingSnapshot, today: LocalDate) -> TrainingRewardFacts {
        var days: [TrainingDayFact] = []
        var weeks: [TrainingWeekFact] = []
        // add-daily-checkin-and-pain-mode: a check-in or a habit tick on a
        // day outside every written week (a day skeleton) counts too, also
        // without a plan; weeks are still only the written ones.
        for day in snapshot.skeletonDays where day.date <= today {
            days.append(dayFact(day, snapshot: snapshot))
        }
        for week in (snapshot.plan?.weeks ?? []).sorted(by: { $0.week < $1.week }) {
            var weekStrength = 0
            for day in week.days where day.date <= today {
                let fact = dayFact(day, snapshot: snapshot)
                weekStrength += fact.strengthSessionsDone
                days.append(fact)
            }
            let isClosed = week.status?.known == .closed
            weeks.append(TrainingWeekFact(
                week: week.week,
                isClosed: isClosed,
                keptWithinPlan: isClosed && keptWithinPlan(week),
                strengthSessionsDone: weekStrength
            ))
        }
        return TrainingRewardFacts(today: today, days: days.sorted { $0.date < $1.date }, weeks: weeks)
    }

    static func dayFact(_ day: Day, snapshot: TrainingSnapshot) -> TrainingDayFact {
        let light = day.light?.known
        let checkedIn = light != nil && day.lightSource?.known == .checkin
        var honest = false
        if checkedIn, let light, light != .greenLight {
            honest = day.sessions.contains { session in
                session.trafficLight && session.done?.option?.known == light.option
            }
        }
        let strength = day.sessions.filter { session in
            let isStrength = session.sport?.known == .strength || session.type?.known == .strength
            let isDone = session.status?.known == .done || session.done != nil
            return isStrength && isDone
        }.count
        var habitIDs = Set(day.habitsExpected)
        if let counted = day.habitsDone {
            habitIDs.formUnion(counted.keys)
        }
        habitIDs.formUnion(snapshot.checkIns.habitTicks.keys.filter { $0.date == day.date }.map(\.habitId))
        let ticks = habitIDs.filter { snapshot.habitDone($0, on: day.date).done }.count
        return TrainingDayFact(
            date: day.date,
            checkedIn: checkedIn,
            honestLightFollowed: honest,
            strengthSessionsDone: strength,
            habitTicks: ticks
        )
    }

    static func keptWithinPlan(_ week: Week) -> Bool {
        guard let actual = week.actual,
              let done = actual.sessionsDone, done > 0,
              (actual.sessionsMissed ?? 0) == 0
        else { return false }
        if let target = week.targets.runKm, target > 0, let km = actual.runKm {
            return km <= target * (1 + volumeTolerance)
        }
        return true
    }
}
