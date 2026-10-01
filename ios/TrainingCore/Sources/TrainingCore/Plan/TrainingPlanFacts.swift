// TrainingPlanFacts.swift
//
// add-training-gamification-and-150-levels (design D6): WHAT HAPPENED in the
// plan, as plain facts the training XP is built on. Read from the plan the
// phone already shows -- the projection with the phone's own check-ins,
// ticks, ratings and pending edits applied (`TrainingSnapshot`) -- plus the
// few fields `ProjectionRewardExtras` reads from the raw bytes.
//
// This file only READS. It never judges: whether a session was "within the
// light", a day "kept" or a week "kept within plan" is decided by
// Gamification's `TrainingXPRules`, where every guard is tested in one
// place. And it never computes what the vault computes (matching, `actual`,
// adherence, streaks): each fact is copied off a day, a session, a week, a
// habit, a race or a phase.
//
// Per day (only days up to `today`):
//   - `checkInLight`: the light of a morning CHECK-IN -- the vault's
//     `lightSource: checkin`, or the phone's own check-in (the overlay
//     applies it the same way). A light the vault inferred from the executed
//     option is not a self-report: it reads as `nil`;
//   - `painAnswered`: that check-in carried a pain answer (`pains` non-nil;
//     `[]`, "nothing hurts", is an answer);
//   - `habitsExpected` / `habitsDone`: habit ids (a habit is done by the
//     phone's tick, else the projection's count -- `habitDone`);
//   - `sessions`: status, the executed option, and what kind of session it
//     is (traffic-light, strength, race, test), with whether it has a test
//     result, an RPE and a note (the phone's own rating counts at once);
//   - `unplannedRunKm` / `hasUnplannedRun`: activities no session matched,
//     runs only;
//   - `carbLoadRaceId`: set on a carb-load day.
// A date that only the phone knows (a check-in or a tick on a day no week
// note holds) becomes a day with `isInPlan == false`: it can earn the
// self-monitoring rewards, never the plan-day ones.
//
// Per written week: closed / approved, an easy week (outline kind deload,
// taper, recovery or transition), the run target and the vault's `actual`
// run km, unplanned km and km over plan (the last two from the extras, with
// the unplanned km of the days as a fallback).
//
// Also: the active habits and the ladder's gate share, the season's races
// (prep complete, report, the not-yet-published result), every phase
// (closed, recap), the season's end, the last gate test and the plan edits
// the vault applied.
//
// Gamification never imports TrainingCore (nor the reverse): the app's
// adapter (TrainingPlanSignalsBridge.swift) copies these facts into
// Gamification's `TrainingPlanSignals`.
//
// Pure. Depended on by: the app's adapter. Tests: TrainingPlanFactsTests.

import Foundation

public struct PlanSessionFact: Equatable, Sendable {
    public let id: String
    public let isDone: Bool
    public let isSkipped: Bool
    /// The vault marked it missed (its day is over, nothing matched).
    public let isMissed: Bool
    public let isTrafficLight: Bool
    /// The option actually executed, when the vault can tell.
    public let doneOption: OptionCode?
    public let isStrength: Bool
    /// The race it belongs to; also set for a `type: race` session without
    /// an id of its own.
    public let isRace: Bool
    public let raceId: String?
    public let isTest: Bool
    public let hasTestResult: Bool
    public let hasRPE: Bool
    public let hasNote: Bool

    public init(
        id: String,
        isDone: Bool,
        isSkipped: Bool = false,
        isMissed: Bool = false,
        isTrafficLight: Bool = false,
        doneOption: OptionCode? = nil,
        isStrength: Bool = false,
        isRace: Bool = false,
        raceId: String? = nil,
        isTest: Bool = false,
        hasTestResult: Bool = false,
        hasRPE: Bool = false,
        hasNote: Bool = false
    ) {
        self.id = id
        self.isDone = isDone
        self.isSkipped = isSkipped
        self.isMissed = isMissed
        self.isTrafficLight = isTrafficLight
        self.doneOption = doneOption
        self.isStrength = isStrength
        self.isRace = isRace
        self.raceId = raceId
        self.isTest = isTest
        self.hasTestResult = hasTestResult
        self.hasRPE = hasRPE
        self.hasNote = hasNote
    }
}

public struct PlanDayFact: Equatable, Sendable {
    public let date: LocalDate
    /// The day belongs to a written week (a rest day of the plan is one).
    public let isInPlan: Bool
    public let checkInLight: MorningLight?
    public let painAnswered: Bool
    public let habitsExpected: [String]
    public let habitsDone: [String]
    public let sessions: [PlanSessionFact]
    public let unplannedRunKm: Double
    public let hasUnplannedRun: Bool
    public let carbLoadRaceId: String?
    public let isCarbLoad: Bool

    public init(
        date: LocalDate,
        isInPlan: Bool,
        checkInLight: MorningLight?,
        painAnswered: Bool,
        habitsExpected: [String],
        habitsDone: [String],
        sessions: [PlanSessionFact],
        unplannedRunKm: Double,
        hasUnplannedRun: Bool,
        carbLoadRaceId: String?,
        isCarbLoad: Bool
    ) {
        self.date = date
        self.isInPlan = isInPlan
        self.checkInLight = checkInLight
        self.painAnswered = painAnswered
        self.habitsExpected = habitsExpected
        self.habitsDone = habitsDone
        self.sessions = sessions
        self.unplannedRunKm = unplannedRunKm
        self.hasUnplannedRun = hasUnplannedRun
        self.carbLoadRaceId = carbLoadRaceId
        self.isCarbLoad = isCarbLoad
    }
}

public struct PlanWeekFact: Equatable, Sendable {
    public let week: ISOWeek
    public let isClosed: Bool
    /// Approved or already closed.
    public let isApproved: Bool
    /// Its outline row is a deload, taper, recovery or transition week.
    public let isEasy: Bool
    public let runKmTarget: Double?
    public let runKm: Double?
    public let unplannedRunKm: Double?
    public let overPlanKm: Double?

    public init(
        week: ISOWeek,
        isClosed: Bool,
        isApproved: Bool,
        isEasy: Bool,
        runKmTarget: Double?,
        runKm: Double?,
        unplannedRunKm: Double?,
        overPlanKm: Double?
    ) {
        self.week = week
        self.isClosed = isClosed
        self.isApproved = isApproved
        self.isEasy = isEasy
        self.runKmTarget = runKmTarget
        self.runKm = runKm
        self.unplannedRunKm = unplannedRunKm
        self.overPlanKm = overPlanKm
    }
}

public struct PlanRaceFact: Equatable, Sendable {
    public let id: String
    public let date: LocalDate
    /// A start time, a carbohydrate-per-hour figure and at least one
    /// checkpoint or gear item.
    public let isPrepComplete: Bool
    public let hasReport: Bool
    /// `nil` until the vault publishes a result.
    public let outcome: RaceOutcome?
    public let goalReached: Bool?
    public let isPersonalRecord: Bool?
    public let stoppedByRule: Bool?
    public let fuelPlanFollowed: Bool?

    public init(
        id: String,
        date: LocalDate,
        isPrepComplete: Bool,
        hasReport: Bool,
        outcome: RaceOutcome? = nil,
        goalReached: Bool? = nil,
        isPersonalRecord: Bool? = nil,
        stoppedByRule: Bool? = nil,
        fuelPlanFollowed: Bool? = nil
    ) {
        self.id = id
        self.date = date
        self.isPrepComplete = isPrepComplete
        self.hasReport = hasReport
        self.outcome = outcome
        self.goalReached = goalReached
        self.isPersonalRecord = isPersonalRecord
        self.stoppedByRule = stoppedByRule
        self.fuelPlanFollowed = fuelPlanFollowed
    }
}

public struct PlanPhaseFact: Equatable, Sendable {
    public let id: String
    public let isClosed: Bool
    public let hasRecap: Bool

    public init(id: String, isClosed: Bool, hasRecap: Bool) {
        self.id = id
        self.isClosed = isClosed
        self.hasRecap = hasRecap
    }
}

public struct PlanSeasonFact: Equatable, Sendable {
    public let id: String
    /// The last day of the season's period.
    public let end: LocalDate?

    public init(id: String, end: LocalDate?) {
        self.id = id
        self.end = end
    }
}

public struct TrainingPlanFacts: Equatable, Sendable {
    /// The ladder's gate share when the file names none.
    public static let defaultGatePercent = 80
    /// Outline kinds that mean "do less on purpose".
    public static let easyWeekKinds: Set<OutlineKind> = [.deload, .taper, .recovery, .transition]

    public let today: LocalDate
    /// Oldest first, up to `today`.
    public let days: [PlanDayFact]
    /// Oldest first.
    public let weeks: [PlanWeekFact]
    public let activeHabitIds: [String]
    public let habitGatePercent: Int
    public let races: [PlanRaceFact]
    public let phases: [PlanPhaseFact]
    public let season: PlanSeasonFact?
    public let gateTestDate: LocalDate?
    public let appliedPlanEditIds: [String]

    public init(
        today: LocalDate,
        days: [PlanDayFact] = [],
        weeks: [PlanWeekFact] = [],
        activeHabitIds: [String] = [],
        habitGatePercent: Int = TrainingPlanFacts.defaultGatePercent,
        races: [PlanRaceFact] = [],
        phases: [PlanPhaseFact] = [],
        season: PlanSeasonFact? = nil,
        gateTestDate: LocalDate? = nil,
        appliedPlanEditIds: [String] = []
    ) {
        self.today = today
        self.days = days
        self.weeks = weeks
        self.activeHabitIds = activeHabitIds
        self.habitGatePercent = habitGatePercent
        self.races = races
        self.phases = phases
        self.season = season
        self.gateTestDate = gateTestDate
        self.appliedPlanEditIds = appliedPlanEditIds
    }

    // MARK: - Building

    public static func build(
        snapshot: TrainingSnapshot,
        extras: ProjectionRewardExtras = .empty,
        today: LocalDate
    ) -> TrainingPlanFacts {
        var days: [PlanDayFact] = []
        var weeks: [PlanWeekFact] = []
        var seenDates = Set<LocalDate>()

        for week in (snapshot.plan?.weeks ?? []).sorted(by: { $0.week < $1.week }) {
            var weekUnplannedKm = 0.0
            for day in week.days where day.date <= today {
                let fact = dayFact(day, snapshot: snapshot)
                weekUnplannedKm += fact.unplannedRunKm
                seenDates.insert(day.date)
                days.append(fact)
            }
            let load = extras.weekLoads[week.week.description]
            let status = week.status?.known
            let outlineKind = snapshot.outlineRow(for: week.week)?.row.kind?.known
            weeks.append(PlanWeekFact(
                week: week.week,
                isClosed: status == .closed,
                isApproved: status == .approved || status == .closed,
                isEasy: outlineKind.map { easyWeekKinds.contains($0) } ?? false,
                runKmTarget: week.targets.runKm,
                runKm: week.actual?.runKm,
                // The vault's number, else the unplanned runs the days list
                // (only for a week the vault has counted at all).
                unplannedRunKm: load?.unplannedRunKm ?? (week.actual == nil ? nil : weekUnplannedKm),
                overPlanKm: load?.overPlanKm
            ))
        }

        // Days only the phone knows: its own check-ins and ticks on a date
        // no written week holds.
        var phoneOnly = Set<LocalDate>()
        for date in snapshot.checkIns.lights.keys where date <= today && !seenDates.contains(date) {
            phoneOnly.insert(date)
        }
        for key in snapshot.checkIns.habitTicks.keys where key.date <= today && !seenDates.contains(key.date) {
            phoneOnly.insert(key.date)
        }
        for date in phoneOnly {
            days.append(phoneOnlyDayFact(date, snapshot: snapshot))
        }

        let gatePercent = snapshot.habits.gate.adherencePct.flatMap { (1...100).contains($0) ? $0 : nil } ?? defaultGatePercent
        return TrainingPlanFacts(
            today: today,
            days: days.sorted { $0.date < $1.date },
            weeks: weeks,
            activeHabitIds: snapshot.habits.ladder.filter { $0.state?.known == .active }.map(\.id),
            habitGatePercent: gatePercent,
            races: snapshot.races.map { raceFact($0, result: extras.raceResults[$0.id]) },
            phases: snapshot.phases.filter { !$0.id.isEmpty }.map { phase in
                PlanPhaseFact(
                    id: phase.id,
                    isClosed: phase.status?.known == .closed,
                    hasRecap: !(phase.recap?.isEmpty ?? true)
                )
            },
            season: snapshot.season.flatMap { season -> PlanSeasonFact? in
                guard let id = season.id, !id.isEmpty else { return nil }
                return PlanSeasonFact(id: id, end: season.period?.to)
            },
            gateTestDate: extras.gateIsStale ? nil : extras.gateDate,
            appliedPlanEditIds: extras.appliedPlanEditIds
        )
    }

    static func dayFact(_ day: Day, snapshot: TrainingSnapshot) -> PlanDayFact {
        let checkedIn = day.light?.known != nil && day.lightSource?.known == .checkin
        var habitIDs = Set(day.habitsExpected)
        if let counted = day.habitsDone {
            habitIDs.formUnion(counted.keys)
        }
        habitIDs.formUnion(snapshot.checkIns.habitTicks.keys.filter { $0.date == day.date }.map(\.habitId))
        let done = habitIDs.filter { snapshot.habitDone($0, on: day.date).done }.sorted()

        let unplannedRuns = day.unplanned.filter { $0.group?.known == .run }
        let isCarbLoad = day.fuel?.kind?.known == .carbLoad
        return PlanDayFact(
            date: day.date,
            isInPlan: true,
            checkInLight: checkedIn ? day.light?.known : nil,
            painAnswered: checkedIn && day.pains != nil,
            habitsExpected: day.habitsExpected,
            habitsDone: done,
            sessions: day.sessions.map { sessionFact($0, snapshot: snapshot) },
            unplannedRunKm: unplannedRuns.reduce(0.0) { $0 + max(0, $1.km ?? 0) },
            hasUnplannedRun: !unplannedRuns.isEmpty,
            carbLoadRaceId: isCarbLoad ? day.fuel?.raceId : nil,
            isCarbLoad: isCarbLoad
        )
    }

    static func phoneOnlyDayFact(_ date: LocalDate, snapshot: TrainingSnapshot) -> PlanDayFact {
        let ticked = snapshot.checkIns.habitTicks
            .compactMap { entry in entry.key.date == date && entry.value.value ? entry.key.habitId : nil }
            .sorted()
        return PlanDayFact(
            date: date,
            isInPlan: false,
            checkInLight: snapshot.checkIns.light(on: date)?.value,
            painAnswered: snapshot.checkIns.light(on: date) != nil && snapshot.checkIns.pains(on: date) != nil,
            habitsExpected: [],
            habitsDone: ticked,
            sessions: [],
            unplannedRunKm: 0,
            hasUnplannedRun: false,
            carbLoadRaceId: nil,
            isCarbLoad: false
        )
    }

    static func sessionFact(_ session: Session, snapshot: TrainingSnapshot) -> PlanSessionFact {
        let status = session.status?.known
        let type = session.type?.known
        let localNote = snapshot.checkIns.note(session: session.id)?.value
        let note = localNote ?? session.feedback?.note
        return PlanSessionFact(
            id: session.id,
            isDone: status == .done || session.done != nil,
            isSkipped: status == .skipped,
            isMissed: status == .missed,
            isTrafficLight: session.trafficLight,
            doneOption: session.done?.option?.known,
            isStrength: session.sport?.known == .strength || type == .strength,
            isRace: session.raceId != nil || type == .race,
            raceId: session.raceId,
            isTest: type == .test || session.test != nil,
            hasTestResult: !(session.test?.result?.isEmpty ?? true),
            hasRPE: snapshot.checkIns.rpe(session: session.id) != nil || session.feedback?.rpe != nil,
            hasNote: !(note?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        )
    }

    static func raceFact(_ race: Race, result: ProjectionRewardExtras.RaceResult?) -> PlanRaceFact {
        var prepComplete = false
        if let prep = race.prep {
            prepComplete = prep.startTime != nil
                && prep.fuel?.carbsPerHour != nil
                && (!prep.checkpoints.isEmpty || !prep.gear.isEmpty)
        }
        return PlanRaceFact(
            id: race.id,
            date: race.date,
            isPrepComplete: prepComplete,
            hasReport: race.report != nil,
            outcome: result?.outcome?.known,
            goalReached: result?.goalReached,
            isPersonalRecord: result?.pr,
            stoppedByRule: result?.stopRule,
            fuelPlanFollowed: result?.fuelPlanFollowed
        )
    }
}
