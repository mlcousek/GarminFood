// TrainingPlanTestSupport.swift
//
// add-training-gamification-and-150-levels: literal `TrainingPlanSignals`
// for the training tests (rules, progress, the boss / bingo / journeys
// variants). Everything is a synthetic October 2030: the 21st is a Monday,
// so 2030-W43 is 21-27 Oct, W42 is 14-20 Oct and W44 starts on the 28th.
// Nothing here is real.

import Foundation
import FoodLogCore
@testable import Gamification

enum TP {
    typealias S = TrainingPlanSignals

    /// `2030-MM-DD` (October by default).
    static func key(_ day: Int, month: Int = 10) -> String {
        String(format: "2030-%02d-%02d", month, day)
    }

    /// A session; done and traffic-light by default.
    static func session(
        _ id: String,
        done: Bool = true,
        option: S.Option? = nil,
        trafficLight: Bool = true,
        skipped: Bool = false,
        missed: Bool = false,
        strength: Bool = false,
        race: String? = nil,
        isRace: Bool = false,
        test: Bool = false,
        result: Bool = false,
        rpe: Bool = false,
        note: Bool = false
    ) -> S.Session {
        S.Session(
            id: id,
            isDone: done,
            isSkipped: skipped,
            isMissed: missed,
            isTrafficLight: trafficLight,
            doneOption: option,
            isStrength: strength,
            isRace: isRace || race != nil,
            raceId: race,
            isTest: test,
            hasTestResult: result,
            hasRPE: rpe,
            hasNote: note
        )
    }

    static func day(
        _ day: Int,
        month: Int = 10,
        light: S.Light? = nil,
        pain: Bool = false,
        expected: [String] = [],
        done: [String] = [],
        sessions: [S.Session] = [],
        unplannedRun: Bool = false,
        carbLoad: Bool = false,
        inPlan: Bool = true
    ) -> S.Day {
        S.Day(
            day: key(day, month: month),
            isInPlan: inPlan,
            light: light,
            painAnswered: pain,
            habitsExpected: expected,
            habitsDone: done,
            sessions: sessions,
            hasUnplannedRun: unplannedRun,
            isCarbLoad: carbLoad
        )
    }

    static func signals(
        today: Int,
        month: Int = 10,
        days: [S.Day] = [],
        weeks: [S.Week] = [],
        activeHabits: [String] = [],
        gate: Int = 80,
        races: [S.Race] = [],
        phases: [S.Phase] = [],
        season: S.Season? = nil,
        gateTestDay: String? = nil,
        planEdits: [String] = []
    ) -> S {
        S(
            today: key(today, month: month),
            days: days,
            weeks: weeks,
            activeHabitIds: activeHabits,
            habitGatePercent: gate,
            races: races,
            phases: phases,
            season: season,
            gateTestDay: gateTestDay,
            appliedPlanEditIds: planEdits
        )
    }

    /// A closed, approved week.
    static func closedWeek(
        _ week: String,
        easy: Bool = false,
        target: Double? = 50,
        km: Double? = 48,
        unplanned: Double? = 0,
        over: Double? = nil
    ) -> S.Week {
        S.Week(
            week: week,
            isClosed: true,
            isApproved: true,
            isEasy: easy,
            runKmTarget: target,
            runKm: km,
            unplannedRunKm: unplanned,
            overPlanKm: over
        )
    }

    /// The seven days of W43 (21-27 Oct), each with one session done as
    /// planned -- a week with nothing wrong in it.
    static func cleanWeekDays() -> [S.Day] {
        (21...27).map { day($0, sessions: [session("s\($0)", trafficLight: false)]) }
    }

    static func context(
        plan: S?,
        training: TrainingSignals? = nil,
        snapshot: SignalsSnapshot = .empty,
        isTraining: Bool = true,
        unlocked: Set<String> = [],
        now: Date = TestClock.date(2030, 10, 23)
    ) -> FeatureContext {
        FeatureContext(
            snapshot: snapshot,
            now: now,
            calendar: TestClock.calendar,
            streak: StreakEngine.Status(length: 0, hasLoggedToday: false, isAtRiskToday: false, lastLoggedDay: nil),
            level: 1,
            unlockedBadgeIds: unlocked,
            isConfirmPath: false,
            isTrainingExperience: isTraining,
            training: training,
            trainingPlan: plan
        )
    }

    static func tempDirectory(_ name: String = "training-plan") -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
    }

    /// A food-side snapshot in which `days` met their carb goal.
    static func snapshot(carbGoalMetOn days: [String], today: String) -> SignalsSnapshot {
        var signals: [String: DaySignals] = [:]
        for day in days {
            signals[day] = DaySignals(
                day: day,
                date: TestClock.date(2030, 10, 1),
                goalStatus: SignalGoalStatus(metCalorieGoal: true, metProteinGoal: false, metCarbGoal: true, metFatGoal: false)
            )
        }
        return SignalsSnapshot(days: signals, today: today, windowDays: days.sorted())
    }
}
