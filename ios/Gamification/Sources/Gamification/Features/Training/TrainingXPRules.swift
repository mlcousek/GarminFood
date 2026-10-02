// TrainingXPRules.swift
//
// add-training-gamification-and-150-levels (design D7): what the plan's
// facts are WORTH. Pure functions over `TrainingPlanSignals` (and the food
// side's goal status, for carb-load days): the verdict on a session, a day
// and a week, then every reward as an idempotent `RewardGrant` with a stable
// key, plus the ids `TrainingRewardsStore` keeps so the badge ladders
// outlive the few weeks the plan file carries.
//
// THE PRINCIPLE: reward following the plan and honest self-monitoring,
// never doing more than the plan. The guards, each a test in
// TrainingXPRulesTests:
//   1. an unplanned run pays nothing (nothing here reads one, except to
//      break a day or a week);
//   2. unplanned km that take a week over its run target break "week kept"
//      (`isOverPlan`), however small; planned km get 10 % for GPS noise;
//   3. a session done HARDER than the morning's check-in allows (G on
//      amber, G or A on red) pays nothing and breaks its day;
//   4. a red morning done as R, or rested, is a KEPT day; a rest day
//      without an unplanned run is a kept day and pays what a training day
//      pays; a skipped session and a session not done on an amber morning
//      are excused -- they break nothing;
//   5. nothing counts consecutive training days: seven session days in a
//      row pay seven days' rewards, and rest days in between never lower
//      the total;
//   6. a race run on a red morning pays no finish XP; a race stopped by a
//      stop rule, or not started on a red morning, pays what a finish pays;
//   7. every key is stable, so evaluating the same plan twice adds nothing
//      (`RewardLedger`);
//   8. no reward depends on distance, duration, pace, elevation or weight.
//
// Only a CHECK-IN light counts (`Day.light`); the adapter leaves out a
// light the plan inferred from the executed option.
//
// Self-reported facts (check-in, pain answer, habit ticks) pay XP only
// inside the grace window -- today and the two days before -- so filling
// in two weeks at once earns nothing; they still count for streaks and
// badges. Measured facts (sessions, weeks, races) pay whenever the plan
// shows them, because activities can sync late.
//
// Depends on: TrainingPlanSignals, XPAward (+Training), RewardGrant,
// FoodLogCore (SignalsSnapshot, for the carb goal of a carb-load day),
// TrainingRewardsCatalog.isoWeek. Depended on by: TrainingRewardsFeature,
// the training variants of boss, bingo and journeys. Tests:
// TrainingXPRulesTests.

import Foundation
import FoodLogCore

/// `yyyy-MM-dd` and `YYYY-Www` arithmetic without a calendar or a time zone
/// (a plan day is a calendar day, not an instant).
enum TrainingDayKey {
    /// Days since 1970-01-01 (Howard Hinnant's days-from-civil); `nil` for
    /// anything that is not `yyyy-MM-dd`.
    static func dayNumber(_ key: String) -> Int? {
        let parts = key.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day)
        else { return nil }
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let monthFromMarch = (month + 9) % 12
        let dayOfYear = (153 * monthFromMarch + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    /// Whole days from `earlier` to `later`; negative when `later` is first.
    static func days(from earlier: String, to later: String) -> Int? {
        guard let start = dayNumber(earlier), let end = dayNumber(later) else { return nil }
        return end - start
    }

    /// A number that grows by one per ISO week, for "weeks in a row"; `nil`
    /// for anything that is not `YYYY-Www`.
    static func weekOrdinal(_ week: String) -> Int? {
        let parts = week.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2, let year = Int(parts[0]), parts[1].hasPrefix("W"),
              let number = Int(parts[1].dropFirst()), (1...53).contains(number),
              let januaryFourth = dayNumber(String(format: "%04d-01-04", year))
        else { return nil }
        // 1970-01-01 was a Thursday; Monday = 0.
        let weekday = ((januaryFourth % 7 + 7) % 7 + 3) % 7
        let firstMonday = januaryFourth - weekday
        // Mondays are 4 days after a multiple of 7 since 1970-01-01.
        return (firstMonday + 7 * (number - 1) - 4) / 7
    }
}

public enum TrainingSessionVerdict: Sendable, Equatable {
    /// Done within the plan and the morning light.
    case asPlanned
    /// Done with a harder option than the check-in's light allows.
    case overTheLight
    /// Skipped, or not done on an amber or red morning: breaks nothing.
    case excused
    /// Not done on a green morning or without a check-in.
    case missed
    /// Not done yet, and the plan has not judged it.
    case open
}

public struct TrainingSessionJudgement: Sendable, Equatable {
    public let verdict: TrainingSessionVerdict
    /// An amber or red morning followed by its option.
    public let isHonestCall: Bool

    public init(_ verdict: TrainingSessionVerdict, isHonestCall: Bool = false) {
        self.verdict = verdict
        self.isHonestCall = isHonestCall
    }
}

public enum TrainingDayVerdict: Sendable, Equatable {
    /// The plan was followed -- a rest day and resting on a red morning
    /// included.
    case kept
    /// Nothing earned, nothing broken.
    case neutral
    /// Over the light, a missed session, or an unplanned run on a red
    /// morning.
    case broken
    /// Not over yet.
    case open
}

public struct TrainingWeekJudgement: Sendable, Equatable {
    public let isKept: Bool
    /// A kept easy week at or under its run target.
    public let isEasyRespected: Bool

    public init(isKept: Bool, isEasyRespected: Bool) {
        self.isKept = isKept
        self.isEasyRespected = isEasyRespected
    }

    public static let notKept = TrainingWeekJudgement(isKept: false, isEasyRespected: false)
}

/// The counted ids behind the training badge ladders (`TrainingRewardsStore`
/// keeps them under these names).
public enum TrainingSetKey: String, Sendable, CaseIterable {
    case session
    case dayKept
    case easyWeek
    case rated
    case gateWeek
    case test
    case approvedWeek
    case ladderStep
    case phase
    case planEdit
    case racePrep
    case carbLoadDay
    case raceFinish
    case raceReport
    case raceGoal
    case racePR
    case wiseCall
    case season
}

public struct TrainingHabitStreak: Sendable, Equatable {
    /// Days in a row, ending today or yesterday.
    public let current: Int
    /// The longest run the phone has seen.
    public let best: Int

    public init(current: Int, best: Int) {
        self.current = current
        self.best = best
    }

    public static let none = TrainingHabitStreak(current: 0, best: 0)
}

public enum TrainingXPRules {
    /// Self-reported facts pay XP for today and this many days before.
    public static let graceDays = 2
    /// A week may run this much over its run target and still be kept, as
    /// long as no unplanned run caused it (GPS noise, a warm-up jog).
    public static let volumeTolerance = 0.10
    /// A gate test older than this pays nothing.
    public static let gateFreshDays = 14

    // Habit day states (`TrainingRewardsStore.habitDayStates`).
    /// The phone saw the day; nothing was expected.
    public static let habitDayNothingExpected = 0
    /// Habits were expected and the gate share was not reached.
    public static let habitDayNotMet = 1
    /// At least the gate share of the expected habits was done.
    public static let habitDayMet = 2

    // MARK: - Verdicts

    /// A session against the morning's check-in light (`nil` = no check-in).
    public static func judge(_ session: TrainingPlanSignals.Session, light: TrainingPlanSignals.Light?) -> TrainingSessionJudgement {
        if session.isDone {
            guard session.isTrafficLight, let light, light != .greenLight else {
                return TrainingSessionJudgement(.asPlanned)
            }
            switch (light, session.doneOption) {
            case (.amberLight, .some(.a)), (.amberLight, .some(.r)), (.redLight, .some(.r)):
                return TrainingSessionJudgement(.asPlanned, isHonestCall: true)
            case (.amberLight, .none):
                // G and A are both runs: the plan cannot tell. No bonus,
                // but the benefit of the doubt.
                return TrainingSessionJudgement(.asPlanned)
            default:
                // G on amber; G, A or an unknown option on red (the red
                // option is not a run, so an unknown one was a run).
                return TrainingSessionJudgement(.overTheLight)
            }
        }
        if session.isSkipped {
            return TrainingSessionJudgement(.excused)
        }
        guard session.isMissed else {
            return TrainingSessionJudgement(.open)
        }
        if let light, light != .greenLight {
            return TrainingSessionJudgement(.excused)
        }
        return TrainingSessionJudgement(.missed)
    }

    /// A day of the plan as of `today` (`yyyy-MM-dd`).
    public static func judge(_ day: TrainingPlanSignals.Day, today: String) -> TrainingDayVerdict {
        guard day.isInPlan else { return .neutral }
        guard day.day <= today else { return .open }
        let verdicts = day.sessions.map { judge($0, light: day.light).verdict }
        if verdicts.contains(.overTheLight) { return .broken }
        if day.light == .redLight && day.hasUnplannedRun { return .broken }
        if verdicts.contains(.missed) { return .broken }
        if verdicts.contains(.open) { return .open }
        if verdicts.isEmpty {
            // A rest day is judged when it is over.
            guard day.day < today else { return .open }
            return day.hasUnplannedRun ? .neutral : .kept
        }
        if verdicts.contains(.asPlanned) { return .kept }
        // Every session excused: resting on a red morning IS the plan.
        return day.light == .redLight ? .kept : .neutral
    }

    /// Run km over the target beyond GPS noise, or over it at all because of
    /// unplanned runs. `false` when the target or the distance is unknown.
    public static func isOverPlan(_ week: TrainingPlanSignals.Week) -> Bool {
        guard let target = week.runKmTarget, target > 0, let km = week.runKm else { return false }
        if km > target * (1 + volumeTolerance) { return true }
        let over = week.overPlanKm ?? max(0, km - target)
        return over > 0 && (week.unplannedRunKm ?? 0) > 0
    }

    /// A week of the plan: judged only once the plan has closed it.
    public static func judge(_ week: TrainingPlanSignals.Week, days: [TrainingPlanSignals.Day], today: String) -> TrainingWeekJudgement {
        guard week.isClosed else { return .notKept }
        let verdicts = days
            .filter { $0.isInPlan && TrainingRewardsCatalog.isoWeek(ofDay: $0.day) == week.week }
            .map { judge($0, today: today) }
        guard !verdicts.contains(.broken), verdicts.contains(.kept), !isOverPlan(week) else { return .notKept }
        var easyRespected = week.isEasy
        if easyRespected, let target = week.runKmTarget, target > 0, let km = week.runKm {
            easyRespected = km <= target
        }
        return TrainingWeekJudgement(isKept: true, isEasyRespected: easyRespected)
    }

    /// Whether `day` is today or one of the `graceDays` before it.
    public static func isWithinGrace(_ day: String, today: String) -> Bool {
        guard let age = TrainingDayKey.days(from: day, to: today) else { return false }
        return (0...graceDays).contains(age)
    }

    /// How a day counts for the habit streak.
    public static func habitDayState(expected: [String], done: [String], gatePercent: Int) -> Int {
        let expectedSet = Set(expected)
        guard !expectedSet.isEmpty else { return habitDayNothingExpected }
        let percent = min(max(gatePercent, 1), 100)
        let needed = (expectedSet.count * percent + 99) / 100
        let met = expectedSet.intersection(done).count
        return met >= needed ? habitDayMet : habitDayNotMet
    }

    /// The habit streak from the store's day states. A met day extends it; a
    /// day with nothing expected is skipped; a day not met breaks it --
    /// except today, which is not over; a day the phone never saw breaks it.
    public static func habitStreak(states: [String: Int], today: String) -> TrainingHabitStreak {
        var entries: [(number: Int, key: String, state: Int)] = []
        for (key, state) in states {
            if let number = TrainingDayKey.dayNumber(key) {
                entries.append((number: number, key: key, state: state))
            }
        }
        entries.sort { $0.number < $1.number }
        var best = 0
        var run = 0
        var previous: Int?
        for entry in entries {
            if let previous, entry.number != previous + 1 { run = 0 }
            previous = entry.number
            if entry.state == habitDayMet {
                run += 1
                best = max(best, run)
            } else if entry.state == habitDayNotMet, entry.key < today {
                run = 0
            }
        }
        var current = 0
        if let last = entries.last, let todayNumber = TrainingDayKey.dayNumber(today), todayNumber - last.number <= 1 {
            current = run
        }
        return TrainingHabitStreak(current: current, best: best)
    }

    /// Consecutive calendar days in `days` ending today or yesterday.
    public static func dayStreak(_ days: [String], today: String) -> Int {
        guard let todayNumber = TrainingDayKey.dayNumber(today) else { return 0 }
        let numbers = Set(days.compactMap { TrainingDayKey.dayNumber($0) })
        var cursor = numbers.contains(todayNumber) ? todayNumber : todayNumber - 1
        var length = 0
        while numbers.contains(cursor) {
            length += 1
            cursor -= 1
        }
        return length
    }

    /// Consecutive ISO weeks in `weeks` ending with the newest one, when
    /// that is `currentWeek` or one of the two weeks before it (a week is
    /// kept only after it closes); 0 otherwise.
    public static func weekStreak(_ weeks: [String], currentWeek: String?) -> Int {
        let ordinals = Set(weeks.compactMap { TrainingDayKey.weekOrdinal($0) })
        guard let newest = ordinals.max() else { return 0 }
        if let currentWeek, let current = TrainingDayKey.weekOrdinal(currentWeek), current - newest > 2 { return 0 }
        var cursor = newest
        var length = 0
        while ordinals.contains(cursor) {
            length += 1
            cursor -= 1
        }
        return length
    }

    // MARK: - Grants

    /// What one evaluation records in `TrainingRewardsStore`.
    public struct Facts: Sendable, Equatable {
        public var checkInDays: [String] = []
        public var honestDays: [String] = []
        public var gymWeeks: [String] = []
        public var keptWeeks: [String] = []
        /// Habits done per day (replaces the day's earlier count).
        public var habitTicksByDay: [String: Int] = [:]
        /// `habitDayNothingExpected` / `NotMet` / `Met` per day.
        public var habitDayStates: [String: Int] = [:]
        /// `TrainingSetKey.rawValue` -> ids to add.
        public var sets: [String: [String]] = [:]
        /// Season id -> the last day of its period.
        public var seasonEnds: [String: String] = [:]

        public init() {}

        mutating func insert(_ key: TrainingSetKey, _ id: String) {
            sets[key.rawValue, default: []].append(id)
        }

        public func ids(_ key: TrainingSetKey) -> [String] {
            sets[key.rawValue] ?? []
        }
    }

    public struct Evaluation: Sendable, Equatable {
        public let grants: [RewardGrant]
        public let facts: Facts

        public init(grants: [RewardGrant], facts: Facts) {
            self.grants = grants
            self.facts = facts
        }

        /// The XP of every grant (before the ledger drops the ones already
        /// paid).
        public var totalXP: Int {
            grants.reduce(0) { sum, grant in
                if case .xp(let amount) = grant.kind { return sum + amount }
                return sum
            }
        }

        public func xp(forKey key: String) -> Int? {
            for grant in grants where grant.key == key {
                if case .xp(let amount) = grant.kind { return amount }
            }
            return nil
        }
    }

    /// `training.<what>.<id>`, inside the feature's own key namespace.
    public static func key(_ what: String, _ id: String) -> String {
        "\(TrainingRewardsFeature.id).\(what).\(id)"
    }

    /// Every reward the plan's facts earn, with the ids to record.
    /// - Parameters:
    ///   - snapshot: the food side's days, for a carb-load day's carb goal.
    ///   - knownSeasonEnds: seasons the store remembers (id -> last day), so
    ///     a season that ended after the plan moved on is still completed.
    public static func evaluate(
        _ signals: TrainingPlanSignals,
        snapshot: SignalsSnapshot,
        knownSeasonEnds: [String: String] = [:]
    ) -> Evaluation {
        let today = signals.today
        var grants: [RewardGrant] = []
        var facts = Facts()
        func grant(_ what: String, _ id: String, _ xp: Int) {
            grants.append(RewardGrant(key: key(what, id), kind: .xp(xp)))
        }

        var strengthByWeek: [String: Int] = [:]
        var raceSessionsById: [String: [TrainingPlanSignals.Session]] = [:]
        var raceSessionsByDay: [String: [TrainingPlanSignals.Session]] = [:]

        for day in signals.days where day.day <= today {
            let inGrace = isWithinGrace(day.day, today: today)

            // Self-monitoring.
            if day.isCheckedIn {
                facts.checkInDays.append(day.day)
                if inGrace {
                    grant("checkin", day.day, XPAward.trainingCheckIn)
                    if day.painAnswered {
                        grant("pain-log", day.day, XPAward.trainingPainLogged)
                    }
                }
            }

            // Habits.
            let done = Set(day.habitsDone)
            facts.habitTicksByDay[day.day] = done.count
            facts.habitDayStates[day.day] = habitDayState(expected: day.habitsExpected, done: day.habitsDone, gatePercent: signals.habitGatePercent)
            if inGrace {
                for habit in done.sorted().prefix(XPAward.trainingHabitTickCapPerDay) {
                    grant("habit", "\(day.day).\(habit)", XPAward.trainingHabitTick)
                }
                let expected = Set(day.habitsExpected)
                if !expected.isEmpty, expected.isSubset(of: done) {
                    grant("habit-day", day.day, XPAward.trainingHabitFullDay)
                }
            }

            // Sessions.
            var honestCall = false
            for session in day.sessions {
                if session.isRace {
                    if let raceId = session.raceId {
                        raceSessionsById[raceId, default: []].append(session)
                    } else {
                        raceSessionsByDay[day.day, default: []].append(session)
                    }
                }
                if session.isDone, session.isStrength, let week = TrainingRewardsCatalog.isoWeek(ofDay: day.day) {
                    strengthByWeek[week, default: 0] += 1
                }
                let judgement = judge(session, light: day.light)
                if judgement.verdict == .asPlanned {
                    // A race pays through the race rewards below.
                    if !session.isRace {
                        grant("session", session.id, XPAward.trainingSession)
                        facts.insert(.session, session.id)
                    }
                    if judgement.isHonestCall { honestCall = true }
                }
                if session.isDone {
                    if session.hasRPE {
                        grant("rpe", session.id, XPAward.trainingSessionRPE)
                        facts.insert(.rated, session.id)
                    }
                    if session.hasNote {
                        grant("note", session.id, XPAward.trainingSessionNote)
                    }
                }
                if session.isTest, session.hasTestResult {
                    grant("test", session.id, XPAward.trainingTestRecorded)
                    facts.insert(.test, session.id)
                }
            }
            if honestCall {
                grant("honest", day.day, XPAward.trainingHonestCall)
                facts.honestDays.append(day.day)
            }
            if judge(day, today: today) == .kept {
                grant("day", day.day, XPAward.trainingDayKept)
                facts.insert(.dayKept, day.day)
            }
            if day.isCarbLoad, snapshot.day(day.day)?.goalStatus?.metCarbGoal == true {
                grant("carb-load", day.day, XPAward.trainingCarbLoadDay)
                facts.insert(.carbLoadDay, day.day)
            }
        }

        // Weeks.
        for week in signals.weeks {
            if week.isApproved {
                grant("week-approved", week.week, XPAward.trainingWeekApproved)
                facts.insert(.approvedWeek, week.week)
            }
            let judgement = judge(week, days: signals.days, today: today)
            if judgement.isKept {
                grant("week-kept", week.week, XPAward.trainingWeekKept)
                facts.keptWeeks.append(week.week)
            }
            if judgement.isEasyRespected {
                grant("easy-week", week.week, XPAward.trainingEasyWeek)
                facts.insert(.easyWeek, week.week)
            }
        }
        for week in strengthByWeek.keys.sorted() where (strengthByWeek[week] ?? 0) >= TrainingRewardsFeature.gymSessionsPerWeek {
            grant("gym-week", week, XPAward.trainingGymWeek)
            facts.gymWeeks.append(week)
        }

        // The weekly gate test.
        if let gateDay = signals.gateTestDay,
           let age = TrainingDayKey.days(from: gateDay, to: today), (0...gateFreshDays).contains(age),
           let week = TrainingRewardsCatalog.isoWeek(ofDay: gateDay) {
            grant("gate", week, XPAward.trainingGateTest)
            facts.insert(.gateWeek, week)
        }

        // The ladder, phases, the season.
        for habit in signals.activeHabitIds {
            grant("ladder-step", habit, XPAward.trainingLadderStep)
            facts.insert(.ladderStep, habit)
        }
        for phase in signals.phases where phase.isClosed && phase.hasRecap {
            grant("phase", phase.id, XPAward.trainingPhaseCompleted)
            facts.insert(.phase, phase.id)
        }
        var seasonEnds = knownSeasonEnds
        if let season = signals.season, let end = season.endDay {
            seasonEnds[season.id] = end
            facts.seasonEnds[season.id] = end
        }
        for id in seasonEnds.keys.sorted() {
            guard let end = seasonEnds[id], end < today else { continue }
            grant("season", id, XPAward.trainingSeasonCompleted)
            facts.insert(.season, id)
        }

        // Races: a fixed amount each -- never distance, pace or priority.
        for race in signals.races {
            if race.isPrepComplete, today <= race.day {
                grant("race-prep", race.id, XPAward.trainingRacePrep)
                facts.insert(.racePrep, race.id)
            }
            if race.hasReport {
                grant("race-report", race.id, XPAward.trainingRaceReport)
                facts.insert(.raceReport, race.id)
            }
            if race.fuelPlanFollowed == true {
                grant("race-fuel", race.id, XPAward.trainingRaceFuelPlan)
            }
            if race.goalReached == true { facts.insert(.raceGoal, race.id) }
            if race.isPersonalRecord == true { facts.insert(.racePR, race.id) }

            guard race.day <= today else { continue }
            let sessions = raceSessionsById[race.id] ?? raceSessionsByDay[race.day] ?? []
            let light = signals.day(race.day)?.light
            let sessionDone = sessions.contains { $0.isDone }
            let endedEarly = race.outcome == .dnf || race.outcome == .dns
            if (sessionDone || race.outcome == .finished) && !endedEarly {
                // Racing through a red morning is not rewarded.
                if light != .redLight {
                    grant("race-finish", race.id, XPAward.trainingRaceFinished)
                    facts.insert(.raceFinish, race.id)
                }
            } else {
                let restedOnRed = light == .redLight && sessions.contains { !$0.isDone && ($0.isMissed || $0.isSkipped) }
                if race.stoppedByRule == true || restedOnRed {
                    grant("wise-call", race.id, XPAward.trainingWiseCall)
                    facts.insert(.wiseCall, race.id)
                }
            }
        }

        // Plan edits: counted for one badge, never paid.
        for id in signals.appliedPlanEditIds {
            facts.insert(.planEdit, id)
        }
        return Evaluation(grants: grants, facts: facts)
    }

    /// The one-off habit-streak rewards a best streak has reached.
    public static func habitStreakGrants(best: Int) -> [RewardGrant] {
        XPAward.trainingHabitStreakMilestones.filter { best >= $0.days }.map { milestone in
            RewardGrant(key: key("habit-streak", String(milestone.days)), kind: .xp(milestone.xp))
        }
    }

    // MARK: - Shared with the weekly games

    /// The days of `signals` that are kept, as of its today.
    public static func keptDays(_ signals: TrainingPlanSignals) -> Set<String> {
        var kept = Set<String>()
        for day in signals.days where judge(day, today: signals.today) == .kept {
            kept.insert(day.day)
        }
        return kept
    }

    /// The days of `signals` that have a verdict (kept, neutral or broken).
    public static func judgedDays(_ signals: TrainingPlanSignals) -> Set<String> {
        var judged = Set<String>()
        for day in signals.days where day.isInPlan && judge(day, today: signals.today) != .open {
            judged.insert(day.day)
        }
        return judged
    }
}
