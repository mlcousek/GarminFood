// TrainingPlanFactsTests.swift
//
// add-training-gamification-and-150-levels (design D6): the plan's facts the
// training XP is built on (`TrainingPlanFacts`), and the sidecar that reads
// the fields the shared model does not carry yet (`ProjectionRewardExtras`).
//
// Every fixture is a small synthetic inline projection of a 2030 season --
// NOT the mirrored contract fixtures, which the vault updates on its own
// schedule -- so nothing here depends on their content. Nothing is real.
//
// What is checked: each fact is read off the right field; a light inferred
// from the executed option is not a check-in; the phone's own check-in,
// tick, rating and note count at once; a date only the phone knows is a day
// outside the plan; the extras tolerate absent, null and broken values and
// never turn a missing number into 0.

import XCTest
@testable import TrainingCore

final class TrainingPlanFactsTests: XCTestCase {
    // MARK: - A synthetic projection

    private static let days = """
    [
      { "date": "2030-10-21", "light": "amber", "lightSource": "checkin", "pains": [],
        "habitsExpected": ["h1", "h3"], "habitsDone": { "h1": 1, "h3": 0 },
        "fuel": { "kind": "daily", "carbsGPerKg": { "min": 5, "max": 7 } },
        "sessions": [ { "id": "s1", "sport": "run", "type": "easy", "trafficLight": true, "status": "done",
                        "options": [ { "code": "G" }, { "code": "A" }, { "code": "R" } ],
                        "done": { "option": "A" },
                        "feedback": { "rpe": 4, "note": "fine" } } ],
        "unplanned": [ { "group": "run", "km": 3.2 }, { "group": "walk", "km": 2 } ] },
      { "date": "2030-10-22", "light": "green", "lightSource": "option",
        "habitsExpected": ["h1"], "habitsDone": null,
        "fuel": { "kind": "carb-load", "raceId": "race-a", "carbsGPerKg": 10, "carbsG": 800 },
        "sessions": [ { "id": "s2", "type": "strength", "status": "skipped" },
                      { "id": "s3", "type": "test", "status": "done", "test": { "workout": "t", "result": { "reps": 12 } } },
                      { "id": "s4", "type": "race", "raceId": "race-a", "status": "missed" } ] },
      { "date": "2030-10-23", "habitsExpected": ["h1"], "sessions": [ { "id": "s5", "sport": "run", "status": "planned" } ] },
      { "date": "2030-10-24", "light": "red", "lightSource": "checkin", "sessions": [] }
    ]
    """

    private func projectionData(
        gate: String = "{ \"date\": \"2030-10-20\", \"walkPain\": 1, \"hopPain\": 3, \"stale\": false }",
        actual: String = "{ \"runKm\": 43.2, \"sessionsDone\": 2, \"sessionsMissed\": 1, \"unplannedRunKm\": 3.2, \"overPlanKm\": 3.2 }",
        raceResult: String = "{ \"outcome\": \"dnf\", \"goalReached\": false, \"stopRule\": true }"
    ) -> Data {
        let json = """
        {
          "schema": "hub.projection",
          "schemaVersion": 1,
          "asOf": "2030-10-23",
          "athlete": { "tz": "Europe/Prague", "dayBoundaryHour": 0, "gate": \(gate) },
          "season": {
            "id": "season-2030",
            "period": { "from": "2030-10-01", "to": "2031-09-30" },
            "phases": [
              { "id": "phase-a", "status": "closed", "recap": { "en": "Done.", "cz": "Hotovo." }, "outline": [] },
              { "id": "phase-test", "status": "active", "recap": null,
                "outline": [ { "week": "2030-W43", "kind": "deload", "runKmTarget": 40 } ] }
            ],
            "races": [
              { "id": "race-a", "date": "2030-10-27",
                "prep": { "startTime": "09:00", "fuel": { "carbsPerHour": 60 }, "gear": [ { "item": "vest", "mandatory": true } ] },
                "report": null,
                "result": \(raceResult) },
              { "id": "race-b", "date": "2030-10-13",
                "prep": { "startTime": "10:00" },
                "report": { "note": "report" } }
            ]
          },
          "plan": {
            "id": "phase-test",
            "weeks": [
              {
                "week": "2030-W43", "from": "2030-10-21", "to": "2030-10-27",
                "status": "closed",
                "targets": { "runKm": 40, "sessions": 5 },
                "actual": \(actual),
                "days": \(Self.days)
              }
            ]
          },
          "habits": {
            "gate": { "adherencePct": 75, "windowDays": 14 },
            "ladder": [ { "id": "h1", "step": 0, "state": "active" }, { "id": "h2", "step": 1, "state": "next" } ]
          },
          "outcomes": [
            { "event": "ev-1", "type": "plan.session.moved", "status": "applied" },
            { "event": "ev-2", "type": "plan.session.skipped", "status": "refused" },
            { "event": "ev-3", "type": "habit.tick", "status": "refused" },
            { "event": "ev-4", "type": "plan.session.swapped", "status": "absorbed" },
            { "event": "ev-1", "type": "plan.session.moved", "status": "applied" }
          ]
        }
        """
        return Data(json.utf8)
    }

    private func snapshot(_ data: Data, checkIns: CheckInOverlay = .empty) throws -> TrainingSnapshot {
        guard case .success(let decoded) = ProjectionDecoder.decode(data) else {
            XCTFail("synthetic projection did not decode")
            throw ProjectionRejection.invalid(reason: "test")
        }
        return TrainingSnapshot(projection: decoded.projection, checkIns: checkIns)
    }

    private func buildFacts(checkIns: CheckInOverlay = .empty, today: String = "2030-10-23") throws -> TrainingPlanFacts {
        let data = projectionData()
        return TrainingPlanFacts.build(
            snapshot: try snapshot(data, checkIns: checkIns),
            extras: ProjectionRewardExtras.decode(data),
            today: D.date(today)
        )
    }

    private func logged(_ seq: Int, _ payload: HubEventPayload) -> LoggedEvent {
        LoggedEvent(
            event: HubEvent(id: "e\(seq)", deviceId: "ios-0000beef", seq: seq, at: "t", payload: payload),
            recordedAt: Date(timeIntervalSince1970: 1_918_951_650 + Double(seq)),
            segmentID: nil
        )
    }

    // MARK: - Days and sessions

    func testDaysUpToTodayAreReadOffThePlan() throws {
        let facts = try buildFacts()
        XCTAssertEqual(facts.today, D.date("2030-10-23"))
        XCTAssertEqual(facts.days.map(\.date), [D.date("2030-10-21"), D.date("2030-10-22"), D.date("2030-10-23")], "days after today are left out")
        XCTAssertTrue(facts.days.allSatisfy(\.isInPlan))

        let monday = facts.days[0]
        XCTAssertEqual(monday.checkInLight, .amberLight)
        XCTAssertTrue(monday.painAnswered, "an empty pain list is an answer")
        XCTAssertEqual(monday.habitsExpected, ["h1", "h3"])
        XCTAssertEqual(monday.habitsDone, ["h1"], "a recorded 0 is not done")
        XCTAssertEqual(monday.unplannedRunKm, 3.2, accuracy: 1e-9, "the walk is not a run")
        XCTAssertTrue(monday.hasUnplannedRun)
        XCTAssertFalse(monday.isCarbLoad)
        XCTAssertNil(monday.carbLoadRaceId)
        XCTAssertEqual(monday.sessions, [
            PlanSessionFact(id: "s1", isDone: true, isTrafficLight: true, doneOption: .a, hasRPE: true, hasNote: true),
        ])

        let tuesday = facts.days[1]
        XCTAssertNil(tuesday.checkInLight, "a light inferred from the option is not a check-in")
        XCTAssertFalse(tuesday.painAnswered)
        XCTAssertEqual(tuesday.habitsDone, [], "an unknown map is not done")
        XCTAssertTrue(tuesday.isCarbLoad)
        XCTAssertEqual(tuesday.carbLoadRaceId, "race-a")
        XCTAssertFalse(tuesday.hasUnplannedRun)
        XCTAssertEqual(tuesday.sessions, [
            PlanSessionFact(id: "s2", isDone: false, isSkipped: true, isStrength: true),
            PlanSessionFact(id: "s3", isDone: true, isTest: true, hasTestResult: true),
            PlanSessionFact(id: "s4", isDone: false, isMissed: true, isRace: true, raceId: "race-a"),
        ])

        let wednesday = facts.days[2]
        XCTAssertNil(wednesday.checkInLight)
        XCTAssertEqual(wednesday.sessions, [PlanSessionFact(id: "s5", isDone: false)])
    }

    func testThePhonesOwnEventsCountAtOnce() throws {
        let overlay = CheckInOverlay.fold([
            logged(1, .morningCheckIn(MorningCheckInPayload(date: D.date("2030-10-23"), light: .redLight, sessionId: nil, pains: []))),
            logged(2, .habitTick(HabitTickPayload(date: D.date("2030-10-22"), habitId: "h1", done: true))),
            logged(3, .sessionRPE(SessionRPEPayload(date: D.date("2030-10-22"), sessionId: "s3", rpe: 6))),
            logged(4, .sessionNote(SessionNotePayload(date: D.date("2030-10-22"), sessionId: "s3", text: "steady"))),
            logged(5, .habitTick(HabitTickPayload(date: D.date("2030-10-21"), habitId: "h1", done: false))),
        ], unsentSegments: [])
        let facts = try buildFacts(checkIns: overlay)

        let wednesday = facts.days[2]
        XCTAssertEqual(wednesday.checkInLight, .redLight)
        XCTAssertTrue(wednesday.painAnswered)

        let tuesday = facts.days[1]
        XCTAssertEqual(tuesday.habitsDone, ["h1"])
        let test = try XCTUnwrap(tuesday.sessions.first { $0.id == "s3" })
        XCTAssertTrue(test.hasRPE)
        XCTAssertTrue(test.hasNote)

        XCTAssertEqual(facts.days[0].habitsDone, [], "the phone's un-tick wins over the projection's count")
    }

    func testADateOnlyThePhoneKnowsIsADayOutsideThePlan() throws {
        let overlay = CheckInOverlay.fold([
            logged(1, .morningCheckIn(MorningCheckInPayload(date: D.date("2030-10-14"), light: .greenLight, sessionId: nil))),
            logged(2, .habitTick(HabitTickPayload(date: D.date("2030-10-15"), habitId: "h1", done: true))),
            logged(3, .habitTick(HabitTickPayload(date: D.date("2030-10-15"), habitId: "h3", done: false))),
            logged(4, .morningCheckIn(MorningCheckInPayload(date: D.date("2030-10-30"), light: .greenLight, sessionId: nil))),
        ], unsentSegments: [])
        let facts = try buildFacts(checkIns: overlay)
        XCTAssertEqual(Array(facts.days.map(\.date).prefix(2)), [D.date("2030-10-14"), D.date("2030-10-15")])
        XCTAssertFalse(facts.days.contains { $0.date == D.date("2030-10-30") }, "a later date is left out")

        let checkedIn = facts.days[0]
        XCTAssertFalse(checkedIn.isInPlan)
        XCTAssertEqual(checkedIn.checkInLight, .greenLight)
        XCTAssertFalse(checkedIn.painAnswered, "this check-in carried no pain answer")
        XCTAssertTrue(checkedIn.sessions.isEmpty)

        let ticked = facts.days[1]
        XCTAssertFalse(ticked.isInPlan)
        XCTAssertNil(ticked.checkInLight)
        XCTAssertEqual(ticked.habitsDone, ["h1"])
        XCTAssertEqual(ticked.habitsExpected, [])
    }

    // MARK: - Weeks, habits, races, phases, season

    func testTheWeekCarriesItsStatusItsKindAndTheVaultsLoad() throws {
        let facts = try buildFacts()
        XCTAssertEqual(facts.weeks, [
            PlanWeekFact(
                week: D.week("2030-W43"),
                isClosed: true,
                isApproved: true,
                isEasy: true,
                runKmTarget: 40,
                runKm: 43.2,
                unplannedRunKm: 3.2,
                overPlanKm: 3.2
            ),
        ])
    }

    func testWithoutTheLoadFieldsUnplannedKmComeFromTheDaysAndOverPlanIsUnknown() throws {
        let data = projectionData(actual: "{ \"runKm\": 43.2, \"sessionsDone\": 2, \"sessionsMissed\": 1 }")
        let facts = TrainingPlanFacts.build(snapshot: try snapshot(data), extras: ProjectionRewardExtras.decode(data), today: D.date("2030-10-27"))
        let week = try XCTUnwrap(facts.weeks.first)
        XCTAssertEqual(week.unplannedRunKm ?? -1, 3.2, accuracy: 1e-9, "the unplanned runs the days list")
        XCTAssertNil(week.overPlanKm, "never invented")

        let future = projectionData(actual: "null")
        let uncounted = TrainingPlanFacts.build(snapshot: try snapshot(future), extras: ProjectionRewardExtras.decode(future), today: D.date("2030-10-27"))
        XCTAssertNil(uncounted.weeks.first?.unplannedRunKm, "a week the vault has not counted says nothing")
        XCTAssertNil(uncounted.weeks.first?.runKm)
    }

    func testHabitsRacesPhasesAndTheSeason() throws {
        let facts = try buildFacts()
        XCTAssertEqual(facts.activeHabitIds, ["h1"])
        XCTAssertEqual(facts.habitGatePercent, 75)

        XCTAssertEqual(facts.races, [
            PlanRaceFact(id: "race-b", date: D.date("2030-10-13"), isPrepComplete: false, hasReport: true),
            PlanRaceFact(
                id: "race-a", date: D.date("2030-10-27"), isPrepComplete: true, hasReport: false,
                outcome: .dnf, goalReached: false, stoppedByRule: true
            ),
        ], "date order; a prep without a fuel figure is not complete")

        XCTAssertEqual(facts.phases, [
            PlanPhaseFact(id: "phase-a", isClosed: true, hasRecap: true),
            PlanPhaseFact(id: "phase-test", isClosed: false, hasRecap: false),
        ])
        XCTAssertEqual(facts.season, PlanSeasonFact(id: "season-2030", end: D.date("2031-09-30")))
        XCTAssertEqual(facts.gateTestDate, D.date("2030-10-20"))
        XCTAssertEqual(facts.appliedPlanEditIds, ["ev-1", "ev-4"], "applied or absorbed plan commands, each once")
    }

    func testNoPlanGivesNoFacts() throws {
        let json = #"{ "schema": "hub.projection", "schemaVersion": 1, "asOf": "2030-10-23", "season": null, "plan": null }"#
        let data = Data(json.utf8)
        let facts = TrainingPlanFacts.build(snapshot: try snapshot(data), extras: ProjectionRewardExtras.decode(data), today: D.date("2030-10-23"))
        XCTAssertTrue(facts.days.isEmpty)
        XCTAssertTrue(facts.weeks.isEmpty)
        XCTAssertTrue(facts.races.isEmpty)
        XCTAssertTrue(facts.phases.isEmpty)
        XCTAssertNil(facts.season)
        XCTAssertNil(facts.gateTestDate)
        XCTAssertEqual(facts.habitGatePercent, TrainingPlanFacts.defaultGatePercent)
    }

    // MARK: - The extras

    func testTheExtrasReadTheNewFields() {
        let extras = ProjectionRewardExtras.decode(projectionData())
        XCTAssertEqual(extras.gateDate, D.date("2030-10-20"))
        XCTAssertFalse(extras.gateIsStale)
        XCTAssertEqual(extras.weekLoads, ["2030-W43": ProjectionRewardExtras.WeekLoad(unplannedRunKm: 3.2, overPlanKm: 3.2)])
        XCTAssertEqual(extras.raceResults, [
            "race-a": ProjectionRewardExtras.RaceResult(outcome: .known(.dnf), goalReached: false, stopRule: true),
        ])
        XCTAssertEqual(extras.appliedPlanEditIds, ["ev-1", "ev-4"])
    }

    func testTheExtrasTolerateAbsentNullAndBrokenValues() {
        XCTAssertEqual(ProjectionRewardExtras.decode(Data("not json".utf8)), .empty)
        XCTAssertEqual(ProjectionRewardExtras.decode(Data("[1, 2]".utf8)), .empty)
        XCTAssertEqual(ProjectionRewardExtras.decode(Data(#"{ "athlete": 3, "plan": "x", "season": [], "outcomes": {} }"#.utf8)), .empty)

        let broken = ProjectionRewardExtras.decode(projectionData(
            gate: "null",
            actual: "{ \"runKm\": 43.2, \"unplannedRunKm\": \"3\", \"overPlanKm\": null }",
            raceResult: "{ \"outcome\": \"walked-off\", \"goalReached\": 1, \"stopRule\": \"yes\" }"
        ))
        XCTAssertNil(broken.gateDate)
        XCTAssertTrue(broken.weekLoads.isEmpty, "a text or null number is unknown, never 0")
        let result = broken.raceResults["race-a"]
        XCTAssertEqual(result?.outcome, .unknown("walked-off"))
        XCTAssertNil(result?.outcome?.known)
        XCTAssertNil(result?.goalReached, "a number is not a Boolean")
        XCTAssertNil(result?.stopRule)

        let stale = ProjectionRewardExtras.decode(projectionData(gate: "{ \"date\": \"2030-10-01\", \"stale\": true }"))
        XCTAssertEqual(stale.gateDate, D.date("2030-10-01"))
        XCTAssertTrue(stale.gateIsStale)
    }

    func testAStaleGateTestIsNotAFact() throws {
        let data = projectionData(gate: "{ \"date\": \"2030-10-01\", \"stale\": true }")
        let facts = TrainingPlanFacts.build(snapshot: try snapshot(data), extras: ProjectionRewardExtras.decode(data), today: D.date("2030-10-23"))
        XCTAssertNil(facts.gateTestDate)
    }
}
