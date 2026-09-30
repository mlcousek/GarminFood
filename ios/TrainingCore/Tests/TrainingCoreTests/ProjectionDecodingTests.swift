// ProjectionDecodingTests.swift
//
// The contract mirror (tasks 1.2, 2.3; design D13): the vault's two
// synthetic contract fixtures, copied verbatim into Fixtures/Contract/vault,
// decode with ZERO dropped elements, and every field the screens depend on
// (design D4's table) has its fixture value. Then the app-authored edge
// cases, each a small mutation of the example: unknown fields and enum
// values, a session without an id, a malformed date, `schemaVersion: 2`,
// a file that is not a projection, a `supersededBy` hint, snake_case
// schedule kinds, reserved fields filled.

import XCTest
@testable import TrainingCore

final class ProjectionDecodingTests: XCTestCase {
    private func decoded(_ data: Data) throws -> DecodedProjection {
        switch ProjectionDecoder.decode(data) {
        case .success(let decoded): return decoded
        case .failure(let rejection):
            XCTFail("rejected: \(rejection)")
            throw rejection
        }
    }

    private func rejection(_ data: Data) -> ProjectionRejection? {
        if case .failure(let rejection) = ProjectionDecoder.decode(data) { return rejection }
        return nil
    }

    // MARK: The vault's fixtures

    func testExampleDecodesWithNoDroppedElement() throws {
        let decoded = try Fixtures.exampleProjection()
        XCTAssertTrue(decoded.issues.isEmpty, decoded.issues.summary ?? "")
    }

    func testMinimalDecodesWithNoSeasonAndNoPlan() throws {
        let decoded = try decoded(try Fixtures.minimal())
        XCTAssertTrue(decoded.issues.isEmpty, decoded.issues.summary ?? "")
        let projection = decoded.projection
        XCTAssertNil(projection.season)
        XCTAssertNil(projection.plan)
        XCTAssertTrue(projection.workouts.isEmpty)
        XCTAssertTrue(projection.tests.isEmpty)
        XCTAssertTrue(projection.habits.ladder.isEmpty)
        XCTAssertEqual(projection.habits.gate.adherencePct, 80)
        XCTAssertEqual(projection.asOf, D.asOf)
    }

    func testExampleHeaderAndAthlete() throws {
        let projection = try Fixtures.exampleProjection().projection
        XCTAssertEqual(projection.schema, "hub.projection")
        XCTAssertEqual(projection.schemaVersion, 1)
        XCTAssertEqual(projection.asOf, D.asOf)
        XCTAssertEqual(projection.generatedAt, "2030-10-23T06:52:10+02:00")
        XCTAssertEqual(projection.athlete.tz, "Europe/Prague")
        XCTAssertEqual(projection.athlete.dayBoundaryHour, 3)
        XCTAssertEqual(projection.athlete.hrMax, 185)
        XCTAssertEqual(projection.athlete.weightKg, 70)
        let zones = try XCTUnwrap(projection.athlete.hrZones)
        XCTAssertEqual(zones.zones.map(\.number), [1, 2, 3, 4, 5])
        XCTAssertEqual(zones.zone(number: 2), HRZone(number: 2, low: 129, high: 145))
        // Filled from the event log since the vault's add-hub-ingest.
        XCTAssertEqual(CheckInOverlay.ackedSeqs(from: projection.acks), ["ios-0a1b2c3d": 23, "ios-5e6f7a8b": 3])
        XCTAssertEqual(projection.outcomes.count, 10)
        // Race sessions can't be moved from the app: the vault refuses it.
        let refused = projection.outcomes.first { $0["seq"] == .number(16) && $0["deviceId"]?.stringValue == "ios-0a1b2c3d" }
        XCTAssertEqual(refused?["status"]?.stringValue, "refused")
        XCTAssertEqual(refused?["sessionId"]?.stringValue, "2030-w44-sun-am")
        XCTAssertEqual(projection.rejected.count, 3)
        XCTAssertNil(projection.supersededBy)
    }

    func testExampleSeasonPhasesAndRaces() throws {
        let season = try XCTUnwrap(try Fixtures.exampleProjection().projection.season)
        XCTAssertEqual(season.id, "season-2030-31")
        XCTAssertEqual(season.title?.resolved(.english), "Season 2030/31")
        XCTAssertEqual(season.period?.from, D.date("2030-09-02"))
        XCTAssertEqual(season.phases.map(\.id), ["test-prelude-2030", "test-base-2030"])
        let base = season.phases[1]
        XCTAssertEqual(base.kind, .known(.base))
        XCTAssertEqual(base.status, .known(.active))
        XCTAssertEqual(base.outline.map(\.week.description), ["2030-W42", "2030-W43", "2030-W44", "2030-W45", "2030-W46"])
        XCTAssertEqual(base.outline[3].kind, .known(.recovery))
        XCTAssertNil(base.outline[4].runKmTarget)
        XCTAssertEqual(base.outline[0].note?.resolved(.czech), "Start plánu")

        XCTAssertEqual(season.races.map(\.id), ["lakeside-10k-2030", "valley-30k-2030", "ridge-ultra-2031"])
        let ultra = season.races[2]
        XCTAssertEqual(ultra.priority, .known(.a))
        XCTAssertTrue(ultra.hero)
        XCTAssertTrue(ultra.dateApprox)
        XCTAssertEqual(ultra.date, D.date("2031-06-21"))
        XCTAssertEqual(ultra.name?.resolved(.czech), "Ridge Ultra")
        let valley = season.races[1]
        XCTAssertEqual(valley.priority, .known(.b))
        let prep = try XCTUnwrap(valley.prep)
        XCTAssertEqual(prep.startTime?.description, "09:00")
        XCTAssertEqual(prep.checkpoints.count, 4)
        XCTAssertEqual(prep.checkpoints[2].aid, .known(.full))
        XCTAssertEqual(prep.fuel?.carbsPerHour, 70)
        XCTAssertEqual(prep.carbLoad.map(\.dayOffset), [-2, -1])
        XCTAssertEqual(prep.gear.map(\.mandatory), [true, false])
    }

    func testExamplePlanWeeksAndDays() throws {
        let plan = try XCTUnwrap(try Fixtures.exampleProjection().projection.plan)
        XCTAssertEqual(plan.id, "test-base-2030")
        XCTAssertEqual(plan.title?.resolved(.english), "Test Base 2030")
        XCTAssertEqual(plan.goals.map { $0.text.resolved(.czech) }, ["Zdravá šlacha", "Objem"])
        XCTAssertEqual(plan.rules.first?.text.resolved(.english), "Two ambers make the next quality session a ride")
        XCTAssertEqual(plan.weeks.map(\.week.description), ["2030-W41", "2030-W42", "2030-W43", "2030-W44"])
        XCTAssertTrue(plan.weeks.allSatisfy { $0.days.count == 7 })

        // A window week of the previous phase says so (deviation 1).
        XCTAssertEqual(plan.weeks[0].phaseId, "test-prelude-2030")
        let w43 = plan.weeks[2]
        XCTAssertEqual(w43.status, .known(.approved))
        // red-holds: the red morning of 2030-10-14 held the volume at 55.
        XCTAssertEqual(w43.targets.runKm, 55)
        XCTAssertEqual(w43.ruleNotes.count, 2)
        XCTAssertEqual(w43.ruleNotes.first?["rule"]?.stringValue, "red-holds")
        XCTAssertTrue(plan.weeks[3].ruleNotes.isEmpty)
        XCTAssertEqual(w43.targets.sessions, 6)
        XCTAssertEqual(w43.actual?.runKm, 10.1)
        XCTAssertEqual(w43.actual?.sessionsDone, 1)
        XCTAssertEqual(w43.actual?.sessionsMissed, 1)
        XCTAssertNil(w43.aiNote)
        XCTAssertTrue(w43.absorbed.isEmpty)
        XCTAssertNil(plan.weeks[3].actual)
        XCTAssertEqual(plan.weeks[1].aiNote?.resolved(.english), "Last week settled well; this week adds one long run.")

        let fri = try XCTUnwrap(plan.weeks[3].day(D.date("2030-11-01")))
        XCTAssertEqual(fri.fuel?.kind, .known(.carbLoad))
        XCTAssertEqual(fri.fuel?.carbsG, 560)
        XCTAssertEqual(fri.fuel?.carbsGPerKg, 8)
        XCTAssertEqual(fri.fuel?.raceId, "valley-30k-2030")

        let tue = try XCTUnwrap(plan.weeks[1].day(D.date("2030-10-15")))
        // No check-in that day: the light is inferred from the executed R.
        XCTAssertEqual(tue.light, .known(.redLight))
        XCTAssertEqual(tue.lightSource, .known(.option))
        let checkedIn = try XCTUnwrap(plan.weeks[2].day(D.asOf))
        XCTAssertEqual(checkedIn.light, .known(.amberLight))
        XCTAssertEqual(checkedIn.lightSource, .known(.checkin))
        XCTAssertEqual(checkedIn.habitsDone, ["holds": 2, "gym": 0], "a habit.tick overrides the daily note")
        XCTAssertNil(plan.weeks[3].days[0].light)
        XCTAssertNil(plan.weeks[3].days[0].lightSource)
        XCTAssertEqual(tue.habitsExpected, ["holds"])
        XCTAssertEqual(tue.habitsDone, ["holds": 1, "gym": 0])
        XCTAssertEqual(tue.unplanned.first?.group, .known(.ride))
        XCTAssertEqual(tue.unplanned.first?.km, 8.4)
        XCTAssertNil(plan.weeks[0].days[0].habitsDone)
    }

    func testExampleSessionsOptionsAndDone() throws {
        let plan = try XCTUnwrap(try Fixtures.exampleProjection().projection.plan)
        let tue = try XCTUnwrap(plan.weeks[1].day(D.date("2030-10-15"))?.sessions.first)
        XCTAssertEqual(tue.id, "2030-w42-tue-am")
        XCTAssertEqual(tue.slot, .known(.am))
        XCTAssertEqual(tue.sport, .known(.run))
        XCTAssertEqual(tue.type, .known(.easy))
        XCTAssertEqual(tue.status, .known(.done))
        XCTAssertTrue(tue.trafficLight)
        XCTAssertEqual(tue.options.map(\.code.rawValue), ["G", "A", "R"])
        let r = try XCTUnwrap(tue.option(.r))
        XCTAssertEqual(r.sport, .known(.ride))
        XCTAssertEqual(r.targets.min, 45)
        XCTAssertEqual(r.targets.hrMax, 128)
        XCTAssertNil(r.watch)
        XCTAssertEqual(r.label?.resolved(.czech), "Kolo 45 min Z1 + výdrže")
        let done = try XCTUnwrap(tue.done)
        XCTAssertEqual(done.option, .known(.r))
        XCTAssertEqual(done.source, .known(.sportInferred))
        XCTAssertEqual(done.matchedBy, .known(.dateSportGroup))
        XCTAssertEqual(done.activity?.sport, "VirtualRide")
        XCTAssertEqual(done.activity?.start?.description, "05:10")
        XCTAssertNil(tue.origin)
        XCTAssertTrue(tue.ruleNotes.isEmpty)

        // Done, and the option token in the activity's name says A
        // (add-garmin-workout-push, contract point 3).
        let fri = try XCTUnwrap(plan.weeks[1].day(D.date("2030-10-18"))?.sessions.first)
        XCTAssertEqual(fri.status, .known(.done))
        XCTAssertEqual(fri.done?.option, .known(.a))
        XCTAssertEqual(fri.done?.source, .known(.activityName))

        // The watch push's state on today's options (contract point 12).
        let wed = try XCTUnwrap(plan.weeks[2].day(D.asOf)?.sessions.first)
        XCTAssertEqual(wed.options.map { $0.watch?.state }, [.known(.scheduled), .known(.pending), .known(.failed)])
        XCTAssertEqual(wed.options[0].watch?.name, "G W43 Wed Easy 10 km")
        XCTAssertEqual(wed.options[0].watch?.channel, .known(.intervals))
        XCTAssertEqual(wed.options[0].watch?.ref, "100001")
        XCTAssertEqual(wed.options[0].watch?.at, "2030-10-20T19:42:10+02:00")
        XCTAssertNil(wed.options[1].watch?.ref)

        // A test with a result.
        let test = try XCTUnwrap(plan.weeks[1].day(D.date("2030-10-16"))?.sessions.last)
        XCTAssertEqual(test.type, .known(.test))
        XCTAssertEqual(test.test?.result, ["reps_l": 22, "reps_r": 27])
        XCTAssertEqual(test.done?.matchedBy, .known(.testResult))

        // hrMin (added to v1) and a race session.
        let tempo = try XCTUnwrap(plan.weeks[2].day(D.date("2030-10-22"))?.sessions.first)
        XCTAssertEqual(tempo.targets.hrMin, 145)
        XCTAssertEqual(tempo.targets.hrMax, 151)
        // The race session: on the race's day, or moved by a plan command
        // with the move recorded in `origin` (the vault is about to refuse
        // moving race sessions; either state of the example passes).
        let raceDate = try Fixtures.exampleDate(ofSession: "2030-w44-sun-am")
        let race = try XCTUnwrap(plan.weeks[3].day(raceDate)?.sessions.first { $0.id == "2030-w44-sun-am" })
        XCTAssertEqual(race.raceId, "valley-30k-2030")
        XCTAssertEqual(race.fuel?.carbsPerHour, 70)
        if raceDate == D.date("2030-11-03") {
            XCTAssertNil(race.origin)
        } else {
            XCTAssertEqual(race.origin?["kind"]?.stringValue, "moved")
            XCTAssertEqual(race.origin?["from"]?.stringValue, "2030-11-03")
        }

        // Another device's applied move: Sunday's walk now on Friday.
        let walk = try XCTUnwrap(plan.weeks[2].day(D.date("2030-10-25"))?.sessions.first)
        XCTAssertEqual(walk.id, "2030-w43-sun-pm")
        XCTAssertEqual(walk.origin?["kind"]?.stringValue, "moved")
        XCTAssertEqual(walk.origin?["from"]?.stringValue, "2030-10-27")

        // add-hub-ingest: feedback, a skipped session, a rule's edit.
        XCTAssertEqual(tempo.feedback, SessionFeedback(rpe: 7, feel: 3, note: "Calf tight on the last repeat, eased off."))
        XCTAssertEqual(plan.weeks[1].day(D.date("2030-10-19"))?.sessions.first?.feedback, SessionFeedback(rpe: 5, feel: nil, note: nil))
        XCTAssertNil(wed.feedback)
        XCTAssertEqual(plan.weeks[3].day(D.date("2030-10-28"))?.sessions.first?.status, .known(.skipped))
        let ruled = try XCTUnwrap(plan.weeks[3].day(D.date("2030-10-30"))?.sessions.first)
        XCTAssertEqual(ruled.options.map(\.code.rawValue), ["R"])
        XCTAssertEqual(ruled.ruleNotes.count, 1)
        XCTAssertEqual(ruled.origin?["kind"]?.stringValue, "rule")

        // Zone spelling in the contract is upper case.
        XCTAssertEqual(tue.targets.zone, "Z1")
    }

    func testExampleWorkoutsTestsAndHabits() throws {
        let projection = try Fixtures.exampleProjection().projection
        XCTAssertEqual(projection.workouts.count, 10)
        let gym = try XCTUnwrap(projection.workouts["gym-a"])
        XCTAssertEqual(gym.id, "gym-a")
        XCTAssertEqual(gym.steps.map(\.kind?.rawValue), ["hold", "exercise", "exercise", "rest"])
        XCTAssertEqual(gym.steps[1].reps?.text, "8-12")
        XCTAssertEqual(gym.steps[2].reps?.text, "8")
        XCTAssertEqual(gym.steps[1].load?.text, "40 kg")
        XCTAssertEqual(gym.steps[0].side, .known(.each))
        let tempo = try XCTUnwrap(projection.workouts["tempo-3x8"])
        XCTAssertEqual(tempo.steps[1].times, 3)
        XCTAssertEqual(tempo.steps[1].recoverSec, 90)
        XCTAssertEqual(tempo.steps[1].hrLo, 150)
        let calf = try XCTUnwrap(projection.workouts["calf-raise-test"])
        XCTAssertEqual(calf.kind, .known(.test))
        XCTAssertEqual(calf.measures.map(\.key), ["reps_l", "reps_r"])
        XCTAssertEqual(calf.measures[0].better, .known(.higher))
        XCTAssertEqual(projection.workouts["bike-45-z1"]?.watchName, "Bike 45 Z1")
        XCTAssertEqual(projection.workouts["easy-6-flat"]?.watchName, "Easy 6k flat")
        XCTAssertNil(projection.workouts["gym-a"]?.watchName)

        XCTAssertEqual(projection.tests.map(\.workout), ["calf-raise-test", "time-trial-3k"])
        XCTAssertEqual(projection.tests[0].history.map(\.date.description), ["2030-09-18", "2030-10-16"])
        XCTAssertEqual(projection.tests[0].history[0].values["reps_l"], 18)
        XCTAssertTrue(projection.tests[1].history.isEmpty)

        let ladder = projection.habits.ladder
        XCTAssertEqual(ladder.map(\.id), ["holds", "gym", "stretch", "quality", "pool", "stretch-plus"])
        XCTAssertEqual(ladder[0].schedule?.kind, .known(.daily))
        XCTAssertEqual(ladder[0].schedule?.perDay, 2)
        XCTAssertEqual(ladder[0].dose?.resolved(.czech), "5 × 45 s, twice a day")
        XCTAssertEqual(ladder[0].window14?.pct, 75)
        XCTAssertEqual(ladder[0].window14?.recordedDays, 12)
        XCTAssertEqual(ladder[1].schedule?.days, ["MO", "TH"])
        XCTAssertEqual(ladder[1].gateMet, false)
        XCTAssertEqual(ladder[2].schedule?.kind, .known(.withSessions))
        XCTAssertEqual(ladder[2].schedule?.types, ["easy"])
        XCTAssertNil(ladder[2].window14)
        XCTAssertEqual(ladder[3].schedule?.kind, .known(.weeklyCount))
        XCTAssertEqual(ladder[4].schedule?.kind, .known(.everyNWeeks))
        XCTAssertEqual(ladder[4].schedule?.anchor, D.date("2030-11-30"))
        XCTAssertEqual(ladder[3].state, .known(.later))
        XCTAssertNil(ladder[0].gateBlockedBy)
    }

    // MARK: Gates

    func testSchemaVersionTwoIsUnsupportedMajor() throws {
        let data = try Fixtures.mutatedExample { $0["schemaVersion"] = 2 }
        XCTAssertEqual(rejection(data), .unsupportedMajor(found: 2))
        XCTAssertThrowsError(try ProjectionDecoder.validate(data))
    }

    func testOtherSchemaIsNotAProjection() throws {
        let data = try Fixtures.mutatedExample { $0["schema"] = "something-else" }
        XCTAssertEqual(rejection(data), .invalid(reason: "not a plan projection"))
    }

    func testMissingOrZeroVersionIsInvalid() throws {
        XCTAssertEqual(rejection(try Fixtures.mutatedExample { $0["schemaVersion"] = nil }), .invalid(reason: "no schemaVersion"))
        XCTAssertEqual(rejection(try Fixtures.mutatedExample { $0["schemaVersion"] = 0 }), .invalid(reason: "no schemaVersion"))
    }

    func testNotJSONOrNotAnObjectIsInvalid() {
        XCTAssertEqual(rejection(Data("not json".utf8)), .invalid(reason: "not a JSON object"))
        XCTAssertEqual(rejection(Data("[1, 2]".utf8)), .invalid(reason: "not a JSON object"))
    }

    func testTopLevelSectionOfTheWrongTypeIsInvalid() throws {
        let data = try Fixtures.mutatedExample { $0["plan"] = "a string" }
        guard case .invalid? = rejection(data) else {
            return XCTFail("expected invalid")
        }
    }

    func testRejectionRoundTripsThroughTheFetchReportReason() {
        for rejection in [ProjectionRejection.unsupportedMajor(found: 2), .invalid(reason: "not a plan projection")] {
            XCTAssertEqual(ProjectionRejection(reportReason: rejection.description), rejection)
        }
        XCTAssertNil(ProjectionRejection(reportReason: "too large (1 bytes)"))
    }

    func testSupersededByHintIsTolerated() throws {
        let data = try Fixtures.mutatedExample { $0["supersededBy"] = ["schemaVersion": 2, "minAppBuild": 140] }
        let projection = try decoded(data).projection
        XCTAssertEqual(projection.supersededBy?.schemaVersion, 2)
        XCTAssertEqual(projection.supersededBy?.minAppBuild, "140")
    }

    // MARK: Tolerance

    func testUnknownFieldsAndEnumValuesEverywhere() throws {
        let data = try Fixtures.mutatedExample { object in
            object["futureTopLevel"] = ["x": 1]
            try Fixtures.mutateSession(&object, week: 2, day: 2, session: 0) { session in
                session["type"] = "hike"
                session["status"] = "rescheduled"
                session["newField"] = [1, 2, 3]
            }
            try Fixtures.mutateDay(&object, week: 2, day: 1) { day in
                day["light"] = "purple"
            }
            try Fixtures.mutateSession(&object, week: 1, day: 1, session: 0) { session in
                guard var done = session["done"] as? [String: Any] else { return }
                done["source"] = "watch-link"
                session["done"] = done
            }
            try Fixtures.mutateSession(&object, week: 2, day: 2, session: 0) { session in
                guard var options = session["options"] as? [[String: Any]],
                      var watch = options[0]["watch"] as? [String: Any] else { return }
                watch["state"] = "archived"
                options[0]["watch"] = watch
                session["options"] = options
            }
        }
        let decoded = try decoded(data)
        XCTAssertTrue(decoded.issues.isEmpty)
        let plan = try XCTUnwrap(decoded.projection.plan)
        let session = try XCTUnwrap(plan.weeks[2].day(D.asOf)?.sessions.first)
        XCTAssertEqual(session.type, .unknown("hike"))
        XCTAssertEqual(session.status, .unknown("rescheduled"))
        XCTAssertEqual(session.title?.resolved(.english), "Easy 10 km")
        XCTAssertEqual(plan.weeks[2].day(D.date("2030-10-22"))?.light, .unknown("purple"))
        XCTAssertEqual(plan.weeks[1].day(D.date("2030-10-15"))?.sessions.first?.done?.source, .unknown("watch-link"))
        XCTAssertEqual(session.options[0].watch?.state, .unknown("archived"))
    }

    func testSessionWithoutIDIsDroppedAndCounted() throws {
        let data = try Fixtures.mutatedExample { object in
            try Fixtures.mutateSession(&object, week: 1, day: 3, session: 0) { $0["id"] = nil }
        }
        let decoded = try decoded(data)
        XCTAssertEqual(decoded.issues.summary, "session skipped x1: missing id")
        XCTAssertEqual(decoded.issues.issues.first?.path, "plan.weeks[1].days[3].sessions[0]")
        let thursday = try XCTUnwrap(decoded.projection.plan?.weeks[1].day(D.date("2030-10-17")))
        XCTAssertEqual(thursday.sessions.map(\.id), ["2030-w42-thu-pm"])
    }

    func testMalformedDateDropsOnlyItsDay() throws {
        let data = try Fixtures.mutatedExample { object in
            try Fixtures.mutateDay(&object, week: 2, day: 6) { $0["date"] = "27. 10. 2030" }
        }
        let decoded = try decoded(data)
        XCTAssertEqual(decoded.issues.summary, "day skipped x1: malformed date")
        XCTAssertEqual(decoded.projection.plan?.weeks[2].days.count, 6)
        XCTAssertEqual(decoded.projection.plan?.weeks.count, 4)
    }

    func testNullListsAndMissingKeysReadAsEmpty() throws {
        let data = try Fixtures.mutatedExample { object in
            object["tests"] = NSNull()
            object["workouts"] = nil
            try Fixtures.mutateDay(&object, week: 2, day: 2) { day in
                day["unplanned"] = NSNull()
                day["habitsExpected"] = nil
            }
        }
        let decoded = try decoded(data)
        XCTAssertTrue(decoded.issues.isEmpty)
        XCTAssertTrue(decoded.projection.tests.isEmpty)
        XCTAssertTrue(decoded.projection.workouts.isEmpty)
        let day = try XCTUnwrap(decoded.projection.plan?.weeks[2].day(D.asOf))
        XCTAssertTrue(day.unplanned.isEmpty)
        XCTAssertTrue(day.habitsExpected.isEmpty)
    }

    func testSnakeCaseScheduleKindsAndReservedFieldsFilled() throws {
        let data = try Fixtures.mutatedExample { object in
            var habits = try XCTUnwrap(object["habits"] as? [String: Any])
            var ladder = try XCTUnwrap(habits["ladder"] as? [[String: Any]])
            let schedule: [String: Any] = ["kind": "weekly_count", "times": 2]
            ladder[3]["schedule"] = schedule
            ladder[0]["gateBlockedBy"] = ["rule": "two-ambers"]
            habits["ladder"] = ladder
            object["habits"] = habits
            try Fixtures.mutateSession(&object, week: 2, day: 2, session: 0) { session in
                session["origin"] = ["movedFrom": "2030-10-22"]
                session["ruleNotes"] = [["en": "Two ambers", "cz": "Dvě oranžové"]]
                if var options = session["options"] as? [[String: Any]] {
                    options[0]["watch"] = ["name": "Easy 10", "state": "scheduled"]
                    session["options"] = options
                }
            }
            try Fixtures.mutateDay(&object, week: 2, day: 2) { $0["light"] = "amber" }
        }
        let projection = try decoded(data).projection
        XCTAssertEqual(projection.habits.ladder[3].schedule?.kind, .known(.weeklyCount))
        XCTAssertNotNil(projection.habits.ladder[0].gateBlockedBy)
        let day = try XCTUnwrap(projection.plan?.weeks[2].day(D.asOf))
        XCTAssertEqual(day.light, .known(.amberLight))
        let session = try XCTUnwrap(day.sessions.first)
        XCTAssertEqual(session.origin?["movedFrom"]?.stringValue, "2030-10-22")
        XCTAssertEqual(session.ruleNotes.count, 1)
        XCTAssertEqual(session.options[0].watch?.state, .known(.scheduled))
    }
}
