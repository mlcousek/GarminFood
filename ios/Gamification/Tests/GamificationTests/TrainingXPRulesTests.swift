// TrainingXPRulesTests.swift
//
// add-training-gamification-and-150-levels (design D7): the rules behind the
// training XP -- every row of the session, day and week verdict tables, each
// reward with its key and amount, and the guards that keep the game on the
// plan's side:
//   1. an unplanned run pays nothing;
//   2. unplanned km over the target break "week kept" and "easy week";
//   3. a session over the morning light pays nothing and breaks its day;
//   4. a red morning done as R, or rested, is a kept day; so is a rest day;
//   5. nothing counts consecutive hard days;
//   6. a race run on a red morning pays no finish XP; a wise stop pays what
//      a finish pays;
//   7. the same plan evaluated twice adds nothing (RewardLedger);
//   8. no reward depends on distance, pace or weight.
// Everything is a literal, synthetic October 2030 (TrainingPlanTestSupport).

import XCTest
import FoodLogCore
@testable import Gamification

final class TrainingXPRulesTests: XCTestCase {
    private typealias S = TrainingPlanSignals
    private typealias R = TrainingXPRules

    private func evaluate(_ signals: S, snapshot: SignalsSnapshot = .empty, seasonEnds: [String: String] = [:]) -> R.Evaluation {
        R.evaluate(signals, snapshot: snapshot, knownSeasonEnds: seasonEnds)
    }

    private func xp(_ evaluation: R.Evaluation, _ what: String, _ id: String) -> Int? {
        evaluation.xp(forKey: "training.\(what).\(id)")
    }

    // MARK: - The session verdict table

    func testSessionVerdicts() {
        let run = TP.session("s")
        // Done, not a traffic-light session: as planned on any morning.
        for light in [nil, S.Light.greenLight, .amberLight, .redLight] {
            XCTAssertEqual(R.judge(TP.session("gym", trafficLight: false, strength: true), light: light), TrainingSessionJudgement(.asPlanned))
        }
        // Done, traffic-light: no check-in or a green morning -> any option.
        for option in [nil, S.Option.g, .a, .r] {
            XCTAssertEqual(R.judge(TP.session("s", option: option), light: nil), TrainingSessionJudgement(.asPlanned))
            XCTAssertEqual(R.judge(TP.session("s", option: option), light: .greenLight), TrainingSessionJudgement(.asPlanned), "an easier option on a green morning is fine")
        }
        // Amber.
        XCTAssertEqual(R.judge(TP.session("s", option: .a), light: .amberLight), TrainingSessionJudgement(.asPlanned, isHonestCall: true))
        XCTAssertEqual(R.judge(TP.session("s", option: .r), light: .amberLight), TrainingSessionJudgement(.asPlanned, isHonestCall: true))
        XCTAssertEqual(R.judge(run, light: .amberLight), TrainingSessionJudgement(.asPlanned), "option unknown on amber: the benefit of the doubt, no bonus")
        XCTAssertEqual(R.judge(TP.session("s", option: .g), light: .amberLight), TrainingSessionJudgement(.overTheLight))
        // Red.
        XCTAssertEqual(R.judge(TP.session("s", option: .r), light: .redLight), TrainingSessionJudgement(.asPlanned, isHonestCall: true))
        XCTAssertEqual(R.judge(TP.session("s", option: .g), light: .redLight), TrainingSessionJudgement(.overTheLight))
        XCTAssertEqual(R.judge(TP.session("s", option: .a), light: .redLight), TrainingSessionJudgement(.overTheLight))
        XCTAssertEqual(R.judge(run, light: .redLight), TrainingSessionJudgement(.overTheLight), "an unknown option on red was a run")
        // Not done.
        XCTAssertEqual(R.judge(TP.session("s", done: false, skipped: true), light: .greenLight), TrainingSessionJudgement(.excused))
        XCTAssertEqual(R.judge(TP.session("s", done: false, missed: true), light: .amberLight), TrainingSessionJudgement(.excused))
        XCTAssertEqual(R.judge(TP.session("s", done: false, missed: true), light: .redLight), TrainingSessionJudgement(.excused))
        XCTAssertEqual(R.judge(TP.session("s", done: false, missed: true), light: .greenLight), TrainingSessionJudgement(.missed))
        XCTAssertEqual(R.judge(TP.session("s", done: false, missed: true), light: nil), TrainingSessionJudgement(.missed))
        XCTAssertEqual(R.judge(TP.session("s", done: false), light: .greenLight), TrainingSessionJudgement(.open), "the plan has not judged it yet")
    }

    // MARK: - The day verdict table

    func testDayVerdicts() {
        let today = TP.key(23)
        func verdict(_ day: S.Day) -> TrainingDayVerdict { R.judge(day, today: today) }

        XCTAssertEqual(verdict(TP.day(24, sessions: [TP.session("s")])), .open, "a later day")
        XCTAssertEqual(verdict(TP.day(22, sessions: [TP.session("s")])), .kept)
        XCTAssertEqual(verdict(TP.day(22, light: .amberLight, sessions: [TP.session("s", option: .a)])), .kept)
        XCTAssertEqual(verdict(TP.day(22, light: .amberLight, sessions: [TP.session("s", option: .g)])), .broken, "over the light")
        XCTAssertEqual(verdict(TP.day(22, sessions: [TP.session("s", done: false, missed: true)])), .broken, "a missed session")
        XCTAssertEqual(verdict(TP.day(22, sessions: [TP.session("a"), TP.session("b", done: false, missed: true)])), .broken)
        XCTAssertEqual(verdict(TP.day(23, sessions: [TP.session("a"), TP.session("b", done: false)])), .open, "today, one session still to do")
        XCTAssertEqual(verdict(TP.day(23, sessions: [TP.session("a", option: .g), TP.session("b", done: false)])), .open)
        XCTAssertEqual(verdict(TP.day(23, light: .redLight, sessions: [TP.session("a", option: .g), TP.session("b", done: false)])), .broken, "broken already, whatever comes")

        // Rest and stopping.
        XCTAssertEqual(verdict(TP.day(22)), .kept, "a rest day")
        XCTAssertEqual(verdict(TP.day(23)), .open, "today's rest day is judged when it is over")
        XCTAssertEqual(verdict(TP.day(22, unplannedRun: true)), .neutral, "a run on a rest day: no reward, nothing broken")
        XCTAssertEqual(verdict(TP.day(22, light: .redLight, sessions: [TP.session("s", done: false, missed: true)])), .kept, "resting on a red morning is the plan")
        XCTAssertEqual(verdict(TP.day(22, light: .redLight, sessions: [TP.session("s", option: .r)])), .kept)
        XCTAssertEqual(verdict(TP.day(22, light: .redLight, sessions: [TP.session("s", done: false, skipped: true)])), .kept)
        XCTAssertEqual(verdict(TP.day(22, light: .redLight, sessions: [TP.session("s", option: .r)], unplannedRun: true)), .broken, "an unplanned run on a red morning")
        XCTAssertEqual(verdict(TP.day(22, light: .amberLight, sessions: [TP.session("s", done: false, missed: true)])), .neutral, "resting on amber is excused, not rewarded")
        XCTAssertEqual(verdict(TP.day(22, sessions: [TP.session("s", done: false, skipped: true)])), .neutral, "a skipped session earns nothing and breaks nothing")
        XCTAssertEqual(verdict(TP.day(22, sessions: [TP.session("a"), TP.session("b", done: false, skipped: true)])), .kept)

        // A date only the phone knows is not a plan day.
        XCTAssertEqual(verdict(TP.day(22, inPlan: false)), .neutral)
    }

    // MARK: - The week verdict

    func testAWeekIsJudgedOnlyWhenClosed() {
        let days = TP.cleanWeekDays()
        let open = S.Week(week: "2030-W43", isClosed: false, isApproved: true, runKmTarget: 50, runKm: 48)
        XCTAssertEqual(R.judge(open, days: days, today: TP.key(28)), .notKept)
        XCTAssertEqual(R.judge(TP.closedWeek("2030-W43"), days: days, today: TP.key(28)), TrainingWeekJudgement(isKept: true, isEasyRespected: false))
    }

    func testAWeekNeedsAKeptDayAndNoBrokenOne() {
        let today = TP.key(28)
        let week = TP.closedWeek("2030-W43")
        var days = TP.cleanWeekDays()
        days[2] = TP.day(23, sessions: [TP.session("s23", done: false, missed: true)])
        XCTAssertEqual(R.judge(week, days: days, today: today), .notKept, "a missed session on a green morning")

        days[2] = TP.day(23, light: .redLight, sessions: [TP.session("s23", done: false, missed: true)])
        XCTAssertTrue(R.judge(week, days: days, today: today).isKept, "the same miss on a red morning is rest")

        days[2] = TP.day(23, light: .amberLight, sessions: [TP.session("s23", done: false, missed: true)])
        XCTAssertTrue(R.judge(week, days: days, today: today).isKept, "excused: it does not break the week")

        days[2] = TP.day(23, sessions: [TP.session("s23", done: false, skipped: true)])
        XCTAssertTrue(R.judge(week, days: days, today: today).isKept, "a skipped session does not break the week")

        let neutralOnly = (21...27).map { TP.day($0, sessions: [TP.session("s\($0)", done: false, skipped: true)]) }
        XCTAssertEqual(R.judge(week, days: neutralOnly, today: today), .notKept, "nothing was kept")

        // Days of another week are not this week's.
        let other = (14...20).map { TP.day($0, sessions: [TP.session("x\($0)", done: false, missed: true)]) }
        XCTAssertTrue(R.judge(week, days: other + TP.cleanWeekDays(), today: today).isKept)
    }

    /// Guard 2: the plan is the ceiling.
    func testUnplannedKmOverTheTargetBreakTheWeek() {
        let today = TP.key(28)
        let days = TP.cleanWeekDays()
        func kept(_ week: S.Week) -> Bool { R.judge(week, days: days, today: today).isKept }

        XCTAssertTrue(kept(TP.closedWeek("2030-W43", target: 50, km: 50, unplanned: 0)))
        XCTAssertTrue(kept(TP.closedWeek("2030-W43", target: 50, km: 54.9, unplanned: 0)), "planned runs a little long: GPS noise")
        XCTAssertTrue(kept(TP.closedWeek("2030-W43", target: 50, km: 55, unplanned: 0)), "exactly 10 % over")
        XCTAssertFalse(kept(TP.closedWeek("2030-W43", target: 50, km: 55.1, unplanned: 0)), "more than 10 % over")
        XCTAssertFalse(kept(TP.closedWeek("2030-W43", target: 50, km: 51, unplanned: 3)), "an unplanned run took it over the target")
        XCTAssertFalse(kept(TP.closedWeek("2030-W43", target: 50, km: 51, unplanned: 3, over: 1)), "the plan's own over-plan number")
        XCTAssertTrue(kept(TP.closedWeek("2030-W43", target: 50, km: 47, unplanned: 3)), "unplanned km under the target break nothing")
        XCTAssertTrue(kept(TP.closedWeek("2030-W43", target: nil, km: 80, unplanned: 9)), "no target: nothing to be over")
        XCTAssertTrue(kept(TP.closedWeek("2030-W43", target: 50, km: nil, unplanned: nil)), "unknown distance is not an overshoot")
        XCTAssertFalse(R.isOverPlan(S.Week(week: "2030-W43")))
    }

    func testAnEasyWeekIsRespectedAtOrUnderItsTarget() {
        let today = TP.key(28)
        let days = TP.cleanWeekDays()
        XCTAssertEqual(
            R.judge(TP.closedWeek("2030-W43", easy: true, target: 40, km: 40), days: days, today: today),
            TrainingWeekJudgement(isKept: true, isEasyRespected: true)
        )
        XCTAssertEqual(
            R.judge(TP.closedWeek("2030-W43", easy: true, target: 40, km: 42), days: days, today: today),
            TrainingWeekJudgement(isKept: true, isEasyRespected: false),
            "kept (within GPS noise) but an easy week means at or under"
        )
        XCTAssertEqual(
            R.judge(TP.closedWeek("2030-W43", easy: true, target: 40, km: 41, unplanned: 2), days: days, today: today),
            .notKept
        )
        XCTAssertTrue(R.judge(TP.closedWeek("2030-W43", easy: true, target: nil, km: nil), days: days, today: today).isEasyRespected)
    }

    // MARK: - Self-monitoring and the grace window

    func testCheckInAndPainAnswerPayOncePerDayInsideTheGraceWindow() {
        let signals = TP.signals(today: 23, days: [
            TP.day(16, light: .greenLight, pain: true),
            TP.day(20, light: .greenLight),
            TP.day(21, light: .amberLight, pain: true),
            TP.day(22),
            TP.day(23, light: .redLight, pain: true),
        ])
        let result = evaluate(signals)
        XCTAssertEqual(xp(result, "checkin", TP.key(23)), XPAward.trainingCheckIn)
        XCTAssertEqual(xp(result, "checkin", TP.key(21)), XPAward.trainingCheckIn, "two days back is still inside")
        XCTAssertNil(xp(result, "checkin", TP.key(20)), "three days back pays nothing")
        XCTAssertNil(xp(result, "checkin", TP.key(16)))
        XCTAssertNil(xp(result, "checkin", TP.key(22)), "no check-in that day")
        XCTAssertEqual(xp(result, "pain-log", TP.key(23)), XPAward.trainingPainLogged)
        XCTAssertEqual(xp(result, "pain-log", TP.key(21)), XPAward.trainingPainLogged)
        XCTAssertNil(xp(result, "pain-log", TP.key(16)))
        // Late check-ins still count for the badge ladder.
        XCTAssertEqual(result.facts.checkInDays, [TP.key(16), TP.key(20), TP.key(21), TP.key(23)])

        XCTAssertTrue(R.isWithinGrace(TP.key(21), today: TP.key(23)))
        XCTAssertFalse(R.isWithinGrace(TP.key(20), today: TP.key(23)))
        XCTAssertFalse(R.isWithinGrace(TP.key(24), today: TP.key(23)), "never a later day")
        XCTAssertTrue(R.isWithinGrace("2030-10-31", today: "2030-11-02"), "across a month end")
    }

    func testRatingsNotesTestsAndTheGateTest() {
        let signals = TP.signals(
            today: 23,
            days: [
                TP.day(10, sessions: [TP.session("old", rpe: true, note: true)]),
                TP.day(22, sessions: [
                    TP.session("a", rpe: true),
                    TP.session("b", done: false, missed: true, rpe: true, note: true),
                    TP.session("t", trafficLight: false, test: true, result: true),
                    TP.session("t2", done: false, trafficLight: false, test: true),
                ]),
            ],
            gateTestDay: TP.key(20)
        )
        let result = evaluate(signals)
        XCTAssertEqual(xp(result, "rpe", "a"), XPAward.trainingSessionRPE)
        XCTAssertNil(xp(result, "note", "a"))
        XCTAssertEqual(xp(result, "rpe", "old"), XPAward.trainingSessionRPE, "a rating pays whenever the plan shows it")
        XCTAssertEqual(xp(result, "note", "old"), XPAward.trainingSessionNote)
        XCTAssertNil(xp(result, "rpe", "b"), "a session that was not done has nothing to rate")
        XCTAssertEqual(xp(result, "test", "t"), XPAward.trainingTestRecorded)
        XCTAssertNil(xp(result, "test", "t2"), "no result yet")
        XCTAssertEqual(xp(result, "gate", "2030-W42"), XPAward.trainingGateTest, "keyed by the test's ISO week (20 Oct is a Sunday)")
        XCTAssertEqual(result.facts.ids(.rated), ["old", "a"])
        XCTAssertEqual(result.facts.ids(.test), ["t"])
        XCTAssertEqual(result.facts.ids(.gateWeek), ["2030-W42"])

        let stale = evaluate(TP.signals(today: 23, gateTestDay: TP.key(8)))
        XCTAssertNil(xp(stale, "gate", "2030-W41"), "a test more than 14 days old pays nothing")
        let future = evaluate(TP.signals(today: 23, gateTestDay: TP.key(25)))
        XCTAssertTrue(future.grants.isEmpty)
    }

    // MARK: - Habits

    func testHabitTicksFullDaysAndBackFill() {
        let signals = TP.signals(today: 23, days: [
            TP.day(12, expected: ["h1", "h2"], done: ["h1", "h2"]),
            TP.day(22, expected: ["h1", "h2", "h3"], done: ["h1", "h3", "extra"]),
            TP.day(23, expected: ["h1", "h2"], done: ["h2", "h1"]),
        ])
        let result = evaluate(signals)
        XCTAssertEqual(xp(result, "habit", "\(TP.key(23)).h1"), XPAward.trainingHabitTick)
        XCTAssertEqual(xp(result, "habit", "\(TP.key(23)).h2"), XPAward.trainingHabitTick)
        XCTAssertEqual(xp(result, "habit-day", TP.key(23)), XPAward.trainingHabitFullDay)
        XCTAssertEqual(xp(result, "habit", "\(TP.key(22)).extra"), XPAward.trainingHabitTick, "a habit not expected that day still counts as a tick")
        XCTAssertNil(xp(result, "habit-day", TP.key(22)), "h2 is missing")
        // Back-fill: eleven days ago pays nothing...
        XCTAssertNil(xp(result, "habit", "\(TP.key(12)).h1"))
        XCTAssertNil(xp(result, "habit-day", TP.key(12)))
        // ...but it is recorded, for the streak and the ladder.
        XCTAssertEqual(result.facts.habitTicksByDay, [TP.key(12): 2, TP.key(22): 3, TP.key(23): 2])
        XCTAssertEqual(result.facts.habitDayStates, [
            TP.key(12): R.habitDayMet, TP.key(22): R.habitDayNotMet, TP.key(23): R.habitDayMet,
        ])
    }

    func testAtMostEightTicksADayPay() {
        let many = (1...12).map { String(format: "h%02d", $0) }
        let result = evaluate(TP.signals(today: 23, days: [TP.day(23, expected: many, done: many)]))
        let ticks = result.grants.filter { $0.key.hasPrefix("training.habit.\(TP.key(23)).") }
        XCTAssertEqual(ticks.count, XPAward.trainingHabitTickCapPerDay)
        XCTAssertEqual(xp(result, "habit-day", TP.key(23)), XPAward.trainingHabitFullDay)
    }

    func testTheHabitDayStateFollowsTheLaddersGate() {
        XCTAssertEqual(R.habitDayState(expected: [], done: ["x"], gatePercent: 80), R.habitDayNothingExpected)
        XCTAssertEqual(R.habitDayState(expected: ["a"], done: [], gatePercent: 80), R.habitDayNotMet)
        XCTAssertEqual(R.habitDayState(expected: ["a"], done: ["a"], gatePercent: 80), R.habitDayMet)
        XCTAssertEqual(R.habitDayState(expected: ["a", "b", "c"], done: ["a", "b"], gatePercent: 80), R.habitDayNotMet, "80 % of three is all three")
        XCTAssertEqual(R.habitDayState(expected: ["a", "b", "c", "d", "e"], done: ["a", "b", "c", "d"], gatePercent: 80), R.habitDayMet, "four of five")
        XCTAssertEqual(R.habitDayState(expected: ["a", "b"], done: ["a", "z"], gatePercent: 50), R.habitDayMet, "a lower gate")
        XCTAssertEqual(R.habitDayState(expected: ["a", "b"], done: ["z", "y"], gatePercent: 50), R.habitDayNotMet, "only expected habits count")
    }

    func testTheHabitStreak() {
        let met = R.habitDayMet
        let notMet = R.habitDayNotMet
        let nothing = R.habitDayNothingExpected
        func streak(_ states: [Int: Int], today: Int = 23) -> TrainingHabitStreak {
            var byKey: [String: Int] = [:]
            for (day, state) in states { byKey[TP.key(day)] = state }
            return R.habitStreak(states: byKey, today: TP.key(today))
        }

        XCTAssertEqual(streak([:]), .none)
        XCTAssertEqual(streak([21: met, 22: met, 23: met]), TrainingHabitStreak(current: 3, best: 3))
        XCTAssertEqual(streak([21: met, 22: met, 23: notMet]), TrainingHabitStreak(current: 2, best: 2), "today is not over: it does not break the streak")
        XCTAssertEqual(streak([20: met, 21: notMet, 22: met, 23: met]), TrainingHabitStreak(current: 2, best: 2), "a missed day breaks it")
        XCTAssertEqual(streak([20: met, 21: nothing, 22: met]), TrainingHabitStreak(current: 2, best: 2), "a day with nothing expected is skipped")
        XCTAssertEqual(streak([18: met, 19: met, 21: met, 22: met, 23: met]), TrainingHabitStreak(current: 3, best: 3), "a day the phone never saw breaks it")
        XCTAssertEqual(streak([10: met, 11: met, 12: met, 13: met, 22: met]), TrainingHabitStreak(current: 1, best: 4))
        XCTAssertEqual(streak([10: met, 11: met, 12: met]), TrainingHabitStreak(current: 0, best: 3), "the run ended long ago")
        XCTAssertEqual(R.habitStreak(states: ["2030-10-30": met, "2030-10-31": met, "2030-11-01": met], today: "2030-11-01"), TrainingHabitStreak(current: 3, best: 3), "across a month end")

        XCTAssertEqual(R.habitStreakGrants(best: 6), [])
        XCTAssertEqual(R.habitStreakGrants(best: 30), [
            RewardGrant(key: "training.habit-streak.7", kind: .xp(20)),
            RewardGrant(key: "training.habit-streak.30", kind: .xp(40)),
        ])
        XCTAssertEqual(R.habitStreakGrants(best: 400).count, 4)
    }

    func testDayAndWeekStreaks() {
        XCTAssertEqual(R.dayStreak([TP.key(21), TP.key(22), TP.key(23)], today: TP.key(23)), 3)
        XCTAssertEqual(R.dayStreak([TP.key(21), TP.key(22)], today: TP.key(23)), 2, "today not yet: yesterday's run still stands")
        XCTAssertEqual(R.dayStreak([TP.key(20), TP.key(21)], today: TP.key(23)), 0)
        XCTAssertEqual(R.dayStreak([TP.key(19), TP.key(21), TP.key(22)], today: TP.key(22)), 2)

        XCTAssertEqual(R.weekStreak(["2030-W41", "2030-W42"], currentWeek: "2030-W43"), 2)
        XCTAssertEqual(R.weekStreak(["2030-W40", "2030-W42"], currentWeek: "2030-W43"), 1)
        XCTAssertEqual(R.weekStreak(["2030-W38", "2030-W39"], currentWeek: "2030-W43"), 0, "the run ended weeks ago")
        XCTAssertEqual(R.weekStreak(["2030-W52", "2031-W01"], currentWeek: "2031-W02"), 2, "across the year end")
        XCTAssertEqual(R.weekStreak([], currentWeek: "2030-W43"), 0)
        XCTAssertEqual(TrainingDayKey.days(from: "2030-12-31", to: "2031-01-01"), 1)
        XCTAssertEqual(TrainingDayKey.days(from: "2028-02-28", to: "2028-03-01"), 2, "a leap day")
        XCTAssertNil(TrainingDayKey.dayNumber("yesterday"))
    }

    // MARK: - Sessions, honest calls, kept days

    func testSessionsPayWithinThePlanAndTheLight() {
        let signals = TP.signals(today: 23, days: [
            TP.day(20, light: .amberLight, sessions: [TP.session("amber-a", option: .a)]),
            TP.day(21, light: .redLight, sessions: [TP.session("red-g", option: .g)]),
            TP.day(22, light: .greenLight, sessions: [TP.session("green-a", option: .a), TP.session("gym", trafficLight: false, strength: true)]),
            TP.day(23, light: .redLight, sessions: [TP.session("red-r", option: .r)]),
        ])
        let result = evaluate(signals)
        XCTAssertEqual(xp(result, "session", "amber-a"), XPAward.trainingSession)
        XCTAssertEqual(xp(result, "honest", TP.key(20)), XPAward.trainingHonestCall)
        XCTAssertEqual(xp(result, "day", TP.key(20)), XPAward.trainingDayKept)

        // Guard 3: over the light pays nothing and breaks the day.
        XCTAssertNil(xp(result, "session", "red-g"))
        XCTAssertNil(xp(result, "honest", TP.key(21)))
        XCTAssertNil(xp(result, "day", TP.key(21)))

        XCTAssertEqual(xp(result, "session", "green-a"), XPAward.trainingSession, "the easier option on a green morning pays in full")
        XCTAssertNil(xp(result, "honest", TP.key(22)), "green is never an honest call")
        XCTAssertEqual(xp(result, "session", "gym"), XPAward.trainingSession)

        // Guard 4: red done as R is a kept day with an honest call.
        XCTAssertEqual(xp(result, "session", "red-r"), XPAward.trainingSession)
        XCTAssertEqual(xp(result, "honest", TP.key(23)), XPAward.trainingHonestCall)
        XCTAssertEqual(xp(result, "day", TP.key(23)), XPAward.trainingDayKept)

        XCTAssertEqual(result.facts.ids(.session), ["amber-a", "green-a", "gym", "red-r"])
        XCTAssertEqual(result.facts.honestDays, [TP.key(20), TP.key(23)])
        XCTAssertEqual(result.facts.ids(.dayKept), [TP.key(20), TP.key(22), TP.key(23)])
    }

    /// Guard 4: rest is the plan.
    func testRestDaysAndRedRestArePaidLikeTrainingDays() {
        let signals = TP.signals(today: 24, days: [
            TP.day(21),
            TP.day(22, light: .redLight, sessions: [TP.session("s22", done: false, missed: true)]),
            TP.day(23, sessions: [TP.session("s23")]),
            TP.day(24),
        ])
        let result = evaluate(signals)
        XCTAssertEqual(xp(result, "day", TP.key(21)), XPAward.trainingDayKept, "a rest day")
        XCTAssertEqual(xp(result, "day", TP.key(22)), XPAward.trainingDayKept, "resting on a red morning")
        XCTAssertEqual(xp(result, "day", TP.key(23)), XPAward.trainingDayKept, "a training day pays the same")
        XCTAssertNil(xp(result, "day", TP.key(24)), "today's rest day is not over yet")
        XCTAssertNil(xp(result, "session", "s22"), "nothing was done, so no session XP")
    }

    /// Guard 1: an unplanned run earns nothing, anywhere.
    func testAnUnplannedRunPaysNothing() {
        let rest = evaluate(TP.signals(today: 23, days: [TP.day(22)]))
        let ranAnyway = evaluate(TP.signals(today: 23, days: [TP.day(22, unplannedRun: true)]))
        XCTAssertEqual(rest.totalXP, XPAward.trainingDayKept)
        XCTAssertEqual(ranAnyway.totalXP, 0, "the extra run costs the rest day's reward and earns none")

        let planned = TP.signals(today: 23, days: [TP.day(22, sessions: [TP.session("s")])])
        let plannedPlusExtra = TP.signals(today: 23, days: [TP.day(22, sessions: [TP.session("s")], unplannedRun: true)])
        XCTAssertEqual(evaluate(plannedPlusExtra).totalXP, evaluate(planned).totalXP, "a second, unplanned run adds nothing")
    }

    /// Guard 5: nothing counts consecutive hard days.
    func testConsecutiveSessionDaysPayNoBonusAndRestNeverLowersTheTotal() {
        let sevenInARow = TP.signals(today: 28, days: TP.cleanWeekDays())
        let perDay = XPAward.trainingSession + XPAward.trainingDayKept
        XCTAssertEqual(evaluate(sevenInARow).totalXP, 7 * perDay, "seven days pay seven days' rewards, nothing for the run")

        // The same four sessions with rest days between them.
        let withRest = TP.signals(today: 28, days: [
            TP.day(21, sessions: [TP.session("a", trafficLight: false)]),
            TP.day(22),
            TP.day(23, sessions: [TP.session("b", trafficLight: false)]),
            TP.day(24),
            TP.day(25, sessions: [TP.session("c", trafficLight: false)]),
            TP.day(26),
            TP.day(27, sessions: [TP.session("d", trafficLight: false)]),
        ])
        let backToBack = TP.signals(today: 28, days: [
            TP.day(21, sessions: [TP.session("a", trafficLight: false)]),
            TP.day(22, sessions: [TP.session("b", trafficLight: false)]),
            TP.day(23, sessions: [TP.session("c", trafficLight: false)]),
            TP.day(24, sessions: [TP.session("d", trafficLight: false)]),
        ])
        XCTAssertGreaterThanOrEqual(evaluate(withRest).totalXP, evaluate(backToBack).totalXP)
        XCTAssertEqual(evaluate(withRest).totalXP, 4 * XPAward.trainingSession + 7 * XPAward.trainingDayKept)
    }

    // MARK: - Weeks, the ladder, phases, the season

    func testWeekRewards() {
        let signals = TP.signals(
            today: 28,
            days: TP.cleanWeekDays(),
            weeks: [
                TP.closedWeek("2030-W43", easy: true, target: 40, km: 39),
                S.Week(week: "2030-W44", isClosed: false, isApproved: true),
                S.Week(week: "2030-W45", isClosed: false, isApproved: false),
            ]
        )
        let result = evaluate(signals)
        XCTAssertEqual(xp(result, "week-kept", "2030-W43"), XPAward.trainingWeekKept)
        XCTAssertEqual(xp(result, "easy-week", "2030-W43"), XPAward.trainingEasyWeek)
        XCTAssertEqual(xp(result, "week-approved", "2030-W43"), XPAward.trainingWeekApproved, "a closed week was approved")
        XCTAssertEqual(xp(result, "week-approved", "2030-W44"), XPAward.trainingWeekApproved)
        XCTAssertNil(xp(result, "week-approved", "2030-W45"), "only proposed")
        XCTAssertNil(xp(result, "week-kept", "2030-W44"), "an open week is never judged")
        XCTAssertEqual(result.facts.keptWeeks, ["2030-W43"])
        XCTAssertEqual(result.facts.ids(.easyWeek), ["2030-W43"])
        XCTAssertEqual(result.facts.ids(.approvedWeek), ["2030-W43", "2030-W44"])

        // Guard 2 through the grants: unplanned km over the target.
        let overshot = TP.signals(today: 28, days: TP.cleanWeekDays(), weeks: [TP.closedWeek("2030-W43", easy: true, target: 40, km: 41, unplanned: 4)])
        let broken = evaluate(overshot)
        XCTAssertNil(xp(broken, "week-kept", "2030-W43"))
        XCTAssertNil(xp(broken, "easy-week", "2030-W43"))
        XCTAssertTrue(broken.facts.keptWeeks.isEmpty)
    }

    func testAGymWeekNeedsTwoStrengthSessionsDone() {
        func gym(_ id: String, done: Bool = true) -> S.Session { TP.session(id, done: done, trafficLight: false, strength: true) }
        let two = evaluate(TP.signals(today: 25, days: [
            TP.day(21, sessions: [gym("g1")]),
            TP.day(24, sessions: [gym("g2")]),
            TP.day(25, sessions: [gym("g3", done: false)]),
        ]))
        XCTAssertEqual(xp(two, "gym-week", "2030-W43"), XPAward.trainingGymWeek)
        XCTAssertEqual(two.facts.gymWeeks, ["2030-W43"])

        let split = evaluate(TP.signals(today: 25, days: [
            TP.day(20, sessions: [gym("g0")]),
            TP.day(21, sessions: [gym("g1")]),
        ]))
        XCTAssertTrue(split.facts.gymWeeks.isEmpty, "one in each week is not two in a week")
    }

    func testLadderStepsPhasesAndTheSeason() {
        let signals = TP.signals(
            today: 23,
            activeHabits: ["h1", "h2"],
            phases: [
                S.Phase(id: "base", isClosed: true, hasRecap: true),
                S.Phase(id: "build", isClosed: true, hasRecap: false),
                S.Phase(id: "peak", isClosed: false, hasRecap: true),
            ],
            season: S.Season(id: "season-2030", endDay: "2031-09-30")
        )
        let result = evaluate(signals, seasonEnds: ["season-2029": "2030-09-30", "season-2030": "2031-08-31"])
        XCTAssertEqual(xp(result, "ladder-step", "h1"), XPAward.trainingLadderStep)
        XCTAssertEqual(xp(result, "ladder-step", "h2"), XPAward.trainingLadderStep)
        XCTAssertEqual(xp(result, "phase", "base"), XPAward.trainingPhaseCompleted)
        XCTAssertNil(xp(result, "phase", "build"), "closed without a recap")
        XCTAssertNil(xp(result, "phase", "peak"), "a recap on a phase still open")
        XCTAssertEqual(xp(result, "season", "season-2029"), XPAward.trainingSeasonCompleted, "a remembered season whose period has ended")
        XCTAssertNil(xp(result, "season", "season-2030"), "still running")
        XCTAssertEqual(result.facts.seasonEnds, ["season-2030": "2031-09-30"], "the plan's own end replaces the remembered one")
        XCTAssertEqual(result.facts.ids(.season), ["season-2029"])

        let ended = evaluate(TP.signals(today: 23, season: S.Season(id: "s", endDay: TP.key(22))))
        XCTAssertEqual(xp(ended, "season", "s"), XPAward.trainingSeasonCompleted)
        let lastDay = evaluate(TP.signals(today: 23, season: S.Season(id: "s", endDay: TP.key(23))))
        XCTAssertNil(xp(lastDay, "season", "s"), "its last day is not over")
    }

    func testPlanEditsPayNothing() {
        let result = evaluate(TP.signals(today: 23, planEdits: ["ev-1", "ev-2", "ev-3"]))
        XCTAssertTrue(result.grants.isEmpty, "an edit is never XP")
        XCTAssertEqual(result.facts.ids(.planEdit), ["ev-1", "ev-2", "ev-3"], "counted for the one-off badge only")
    }

    // MARK: - Races

    func testRacePrepReportAndFinishPayAFixedAmount() {
        let signals = TP.signals(
            today: 27,
            days: [
                TP.day(20, sessions: [TP.session("short", trafficLight: false, race: "race-10k")]),
                TP.day(27, sessions: [TP.session("long", trafficLight: false, race: "race-100k")]),
            ],
            races: [
                S.Race(id: "race-10k", day: TP.key(20), isPrepComplete: true, hasReport: true),
                S.Race(id: "race-100k", day: TP.key(27), isPrepComplete: true, hasReport: false),
                S.Race(id: "race-later", day: "2030-11-10", isPrepComplete: true),
            ]
        )
        let result = evaluate(signals)
        // Guard 8: the same amount whatever the race.
        XCTAssertEqual(xp(result, "race-finish", "race-10k"), XPAward.trainingRaceFinished)
        XCTAssertEqual(xp(result, "race-finish", "race-100k"), XPAward.trainingRaceFinished)
        XCTAssertNil(xp(result, "session", "short"), "a race pays through the race reward, not twice")
        XCTAssertEqual(xp(result, "day", TP.key(27)), XPAward.trainingDayKept)

        XCTAssertEqual(xp(result, "race-report", "race-10k"), XPAward.trainingRaceReport)
        XCTAssertNil(xp(result, "race-report", "race-100k"))
        XCTAssertNil(xp(result, "race-prep", "race-10k"), "prep seen only after race day is not preparation")
        XCTAssertEqual(xp(result, "race-prep", "race-100k"), XPAward.trainingRacePrep, "on race day is in time")
        XCTAssertEqual(xp(result, "race-prep", "race-later"), XPAward.trainingRacePrep)
        XCTAssertNil(xp(result, "race-finish", "race-later"), "not run yet")
        XCTAssertNil(xp(result, "race-fuel", "race-10k"), "dormant until the plan says so")
        XCTAssertEqual(result.facts.ids(.raceFinish), ["race-10k", "race-100k"])
    }

    /// Guard 6.
    func testARaceOnARedMorningPaysNoFinishAndAWiseStopPaysLikeAFinish() {
        let signals = TP.signals(
            today: 27,
            days: [
                TP.day(20, light: .redLight, sessions: [TP.session("pushed", trafficLight: false, race: "race-pushed")]),
                TP.day(21, light: .redLight, sessions: [TP.session("stayed", done: false, trafficLight: false, missed: true, race: "race-stayed")]),
                TP.day(22, light: .greenLight, sessions: [TP.session("missed", done: false, trafficLight: false, missed: true, race: "race-missed")]),
                TP.day(23, sessions: [TP.session("stopped", trafficLight: false, race: "race-stopped")]),
                TP.day(24, sessions: [TP.session("quit", trafficLight: false, race: "race-quit")]),
                TP.day(25, sessions: [TP.session("nameless", trafficLight: false, isRace: true)]),
            ],
            races: [
                S.Race(id: "race-pushed", day: TP.key(20)),
                S.Race(id: "race-stayed", day: TP.key(21)),
                S.Race(id: "race-missed", day: TP.key(22)),
                S.Race(id: "race-stopped", day: TP.key(23), outcome: .dnf, stoppedByRule: true),
                S.Race(id: "race-quit", day: TP.key(24), outcome: .dnf),
                S.Race(id: "race-nameless", day: TP.key(25), goalReached: true, isPersonalRecord: true, fuelPlanFollowed: true),
            ]
        )
        let result = evaluate(signals)
        XCTAssertNil(xp(result, "race-finish", "race-pushed"), "racing through a red morning is not rewarded")
        XCTAssertNil(xp(result, "wise-call", "race-pushed"))

        XCTAssertEqual(xp(result, "wise-call", "race-stayed"), XPAward.trainingWiseCall, "not starting on a red morning")
        XCTAssertEqual(XPAward.trainingWiseCall, XPAward.trainingRaceFinished, "so there is never a reason to push through")
        XCTAssertEqual(xp(result, "day", TP.key(21)), XPAward.trainingDayKept, "and the day is kept")

        XCTAssertNil(xp(result, "wise-call", "race-missed"), "just missed, on a green morning")
        XCTAssertNil(xp(result, "race-finish", "race-missed"))

        XCTAssertEqual(xp(result, "wise-call", "race-stopped"), XPAward.trainingWiseCall, "a stop rule ended it")
        XCTAssertNil(xp(result, "race-finish", "race-stopped"), "an activity was recorded, but it was not a finish")
        XCTAssertNil(xp(result, "wise-call", "race-quit"), "a DNF without a stop rule")
        XCTAssertNil(xp(result, "race-finish", "race-quit"))

        XCTAssertEqual(xp(result, "race-finish", "race-nameless"), XPAward.trainingRaceFinished, "a race session without an id is matched by its day")
        XCTAssertEqual(xp(result, "race-fuel", "race-nameless"), XPAward.trainingRaceFuelPlan)
        XCTAssertEqual(result.facts.ids(.raceGoal), ["race-nameless"])
        XCTAssertEqual(result.facts.ids(.racePR), ["race-nameless"])
        XCTAssertEqual(result.facts.ids(.wiseCall), ["race-stayed", "race-stopped"])
        XCTAssertNil(result.grants.first { $0.key.contains(".race-goal.") || $0.key.contains(".race-pr.") }, "goal and PR are badges, not XP")
    }

    func testACarbLoadDayPaysWhenTheFoodSideMetItsCarbGoal() {
        let signals = TP.signals(today: 23, days: [
            TP.day(20, carbLoad: true),
            TP.day(21, carbLoad: true),
            TP.day(22),
        ])
        let snapshot = TP.snapshot(carbGoalMetOn: [TP.key(20), TP.key(22)], today: TP.key(23))
        let result = evaluate(signals, snapshot: snapshot)
        XCTAssertEqual(xp(result, "carb-load", TP.key(20)), XPAward.trainingCarbLoadDay)
        XCTAssertNil(xp(result, "carb-load", TP.key(21)), "a carb-load day without the carbs")
        XCTAssertNil(xp(result, "carb-load", TP.key(22)), "not a carb-load day")
        XCTAssertEqual(result.facts.ids(.carbLoadDay), [TP.key(20)])
    }

    // MARK: - Idempotency and keys

    /// Guard 7: re-reading the plan adds nothing.
    func testTheSamePlanTwicePaysOnce() async throws {
        let signals = TP.signals(
            today: 28,
            days: TP.cleanWeekDays().map { day in
                S.Day(day: day.day, light: .greenLight, habitsExpected: ["h1"], habitsDone: ["h1"], sessions: day.sessions)
            },
            weeks: [TP.closedWeek("2030-W43")],
            activeHabits: ["h1"]
        )
        let first = evaluate(signals)
        XCTAssertEqual(first, evaluate(signals), "pure: the same facts give the same grants")
        XCTAssertEqual(Set(first.grants.map(\.key)).count, first.grants.count, "no key twice")
        XCTAssertTrue(first.grants.allSatisfy { $0.key.hasPrefix("training.") }, "inside the feature's own namespace")

        let directory = TP.tempDirectory("training-ledger")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = XPStore(fileURL: directory.appendingPathComponent("xp.json"))
        let ledger = RewardLedger(fileURL: directory.appendingPathComponent("ledger.json"))
        let now = TestClock.date(2030, 10, 28)
        let paid = try await ledger.apply(first.grants, day: TP.key(28), now: now, xpStore: store)
        XCTAssertEqual(paid.xpAwarded, first.totalXP)
        let again = try await ledger.apply(evaluate(signals).grants, day: TP.key(28), now: now, xpStore: store)
        XCTAssertEqual(again, .empty)
        let total = await store.currentTotal()
        XCTAssertEqual(total, first.totalXP)
    }

    /// Guard 8: the signals carry no pace, no time, no elevation and no
    /// weight at all, and the only distances (a week's run km) can only
    /// take a reward away.
    func testMoreKilometresNeverPayMore() {
        let days = TP.cleanWeekDays()
        func total(_ km: Double) -> Int {
            evaluate(TP.signals(today: 28, days: days, weeks: [TP.closedWeek("2030-W43", target: 50, km: km)])).totalXP
        }
        XCTAssertEqual(total(30), total(50), "under the target pays the same as on it")
        XCTAssertLessThan(total(70), total(50), "over it pays less")
    }
}
