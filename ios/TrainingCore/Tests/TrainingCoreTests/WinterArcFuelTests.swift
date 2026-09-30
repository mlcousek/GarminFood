// WinterArcFuelTests.swift
//
// add-winter-arc-nutrition-and-rewards: the per-day `fuel` band's tolerant
// decoding (the `{ min, max }` shape beside the carb-load number), the gram
// targets it becomes (`DayFuelTargets`), and the reward facts read off the
// plan (`TrainingRewardFacts`). Every fixture is a small synthetic inline
// projection -- NOT the mirrored contract fixtures, which the vault updates
// separately -- so nothing here depends on their content.

import XCTest
@testable import TrainingCore

final class WinterArcFuelTests: XCTestCase {
    // MARK: - Helpers

    private func decodeDay(_ json: String, file: StaticString = #filePath, line: UInt = #line) throws -> Day {
        try JSONDecoder().decode(Day.self, from: Data(json.utf8))
    }

    /// A one-week projection (2030-W43, Mon 21 -- Sun 27 Oct) around `days`.
    private func projection(
        weightKg: String = "80",
        weekStatus: String = "approved",
        targets: String = "{\"runKm\": 50, \"sessions\": 5}",
        actual: String = "null",
        days: String
    ) throws -> Projection {
        let json = """
        {
          "schema": "hub.projection",
          "schemaVersion": 1,
          "asOf": "2030-10-23",
          "athlete": { "tz": "Europe/Prague", "dayBoundaryHour": 0, "weightKg": \(weightKg) },
          "plan": {
            "id": "phase-test",
            "weeks": [
              {
                "week": "2030-W43", "from": "2030-10-21", "to": "2030-10-27",
                "status": "\(weekStatus)",
                "targets": \(targets),
                "actual": \(actual),
                "days": \(days)
              }
            ]
          }
        }
        """
        guard case .success(let decoded) = ProjectionDecoder.decode(Data(json.utf8)) else {
            XCTFail("synthetic projection did not decode")
            throw ProjectionRejection.invalid(reason: "test")
        }
        return decoded.projection
    }

    // MARK: - Decoding

    func testTheBandShapeDecodes() throws {
        let day = try decodeDay("""
        { "date": "2030-10-22", "fuel": { "carbsGPerKg": { "min": 6, "max": 8 }, "proteinGPerKg": 1.7, "fasting": "off" } }
        """)
        let fuel = try XCTUnwrap(day.fuel)
        XCTAssertEqual(fuel.carbsBand, GramsPerKgRange(min: 6, max: 8))
        XCTAssertNil(fuel.carbsGPerKg)
        XCTAssertEqual(fuel.proteinGPerKg, 1.7)
        XCTAssertEqual(fuel.fasting, .known(.off))
        XCTAssertTrue(fuel.isFastingOff)
    }

    func testTheCarbLoadShapeStillDecodes() throws {
        let day = try decodeDay("""
        { "date": "2030-10-22", "fuel": { "kind": "carb-load", "raceId": "r1", "carbsGPerKg": 10, "carbsG": 800 } }
        """)
        let fuel = try XCTUnwrap(day.fuel)
        XCTAssertEqual(fuel.kind, .known(.carbLoad))
        XCTAssertEqual(fuel.carbsGPerKg, 10)
        XCTAssertEqual(fuel.carbsG, 800)
        XCTAssertNil(fuel.carbsBand)
        XCTAssertFalse(fuel.isFastingOff)
    }

    func testABrokenBandReadsAsNilAndKeepsTheRest() throws {
        let day = try decodeDay("""
        { "date": "2030-10-22", "fuel": { "carbsGPerKg": { "min": "a lot" }, "proteinGPerKg": -1, "fasting": "sometimes" } }
        """)
        let fuel = try XCTUnwrap(day.fuel)
        XCTAssertNil(fuel.carbsBand)
        XCTAssertNil(fuel.proteinGPerKg)
        XCTAssertEqual(fuel.fasting, .unknown("sometimes"))
        XCTAssertFalse(fuel.isFastingOff, "an unknown fasting word never pauses fasting")
    }

    func testAOneSidedOrReversedBandIsRepaired() throws {
        let oneSided = try decodeDay("""
        { "date": "2030-10-22", "fuel": { "carbsGPerKg": { "max": 7 } } }
        """)
        XCTAssertEqual(oneSided.fuel?.carbsBand, GramsPerKgRange(min: 7, max: 7))
        let reversed = try decodeDay("""
        { "date": "2030-10-22", "fuel": { "carbsGPerKg": { "min": 9, "max": 6 } } }
        """)
        XCTAssertEqual(reversed.fuel?.carbsBand?.min, 6)
        XCTAssertEqual(reversed.fuel?.carbsBand?.max, 9)
    }

    func testAFuelOfTheWrongTypeReadsAsNil() throws {
        let day = try decodeDay("""
        { "date": "2030-10-22", "fuel": "lots" }
        """)
        XCTAssertNil(day.fuel)
    }

    // MARK: - Gram targets

    func testTheBandTimesTheAthletesWeight() throws {
        let day = try decodeDay("""
        { "date": "2030-10-22", "fuel": { "carbsGPerKg": { "min": 6, "max": 8 }, "proteinGPerKg": 1.8, "fasting": "off" },
          "sessions": [ { "id": "s1", "sport": "run", "type": "easy" } ] }
        """)
        let targets = try XCTUnwrap(DayFuelTargets.resolve(day: day, athleteWeightKg: 80))
        XCTAssertEqual(try XCTUnwrap(targets.carbsMinG), 480, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(targets.carbsMaxG), 640, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(targets.proteinG), 144, accuracy: 1e-9)
        XCTAssertTrue(targets.hasCarbBand)
        XCTAssertTrue(targets.hasTrainingSessions)
        XCTAssertTrue(targets.isFastingPaused)
        XCTAssertFalse(targets.isCarbLoad)
    }

    func testProteinDefaultsToPMFuel1AndTheWeighInIsTheFallback() throws {
        let day = try decodeDay("""
        { "date": "2030-10-22", "fuel": { "carbsGPerKg": { "min": 5, "max": 7 } } }
        """)
        let targets = try XCTUnwrap(DayFuelTargets.resolve(day: day, athleteWeightKg: nil, fallbackWeightKg: 75))
        XCTAssertEqual(targets.weightKg, 75)
        XCTAssertEqual(try XCTUnwrap(targets.carbsMinG), 375, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(targets.proteinG), 120, accuracy: 1e-9)
        XCTAssertFalse(targets.hasTrainingSessions)
    }

    func testNoWeightMeansNoGramsButTheTrainingDayStays() throws {
        let day = try decodeDay("""
        { "date": "2030-10-22", "fuel": { "carbsGPerKg": { "min": 5, "max": 7 } },
          "sessions": [ { "id": "s1", "sport": "run" } ] }
        """)
        let targets = try XCTUnwrap(DayFuelTargets.resolve(day: day, athleteWeightKg: nil))
        XCTAssertNil(targets.carbsMinG)
        XCTAssertNil(targets.proteinG)
        XCTAssertFalse(targets.hasCarbBand)
        XCTAssertTrue(targets.hasTrainingSessions)
    }

    func testACarbLoadDayIsAOnePointBand() throws {
        let grams = try decodeDay("""
        { "date": "2030-10-22", "fuel": { "kind": "carb-load", "carbsGPerKg": 10, "carbsG": 820 } }
        """)
        let fromGrams = try XCTUnwrap(DayFuelTargets.resolve(day: grams, athleteWeightKg: 80))
        XCTAssertEqual(fromGrams.carbsMinG, 820)
        XCTAssertEqual(fromGrams.carbsMaxG, 820)
        XCTAssertTrue(fromGrams.isCarbLoad)

        let perKg = try decodeDay("""
        { "date": "2030-10-22", "fuel": { "kind": "carb-load", "carbsGPerKg": 10 } }
        """)
        let fromKg = try XCTUnwrap(DayFuelTargets.resolve(day: perKg, athleteWeightKg: 80))
        XCTAssertEqual(try XCTUnwrap(fromKg.carbsMinG), 800, accuracy: 1e-9)
    }

    func testARestDayWithoutFuelSaysNothing() throws {
        let day = try decodeDay("""
        { "date": "2030-10-22" }
        """)
        XCTAssertNil(DayFuelTargets.resolve(day: day, athleteWeightKg: 80))
    }

    func testTheSnapshotFindsTheDay() throws {
        let snapshot = TrainingSnapshot(projection: try projection(days: """
        [ { "date": "2030-10-22", "fuel": { "carbsGPerKg": { "min": 6, "max": 8 }, "fasting": "allowed" } } ]
        """))
        let targets = try XCTUnwrap(snapshot.fuelTargets(on: D.date("2030-10-22")))
        XCTAssertEqual(try XCTUnwrap(targets.carbsMaxG), 640, accuracy: 1e-9)
        XCTAssertFalse(targets.isFastingPaused)
        XCTAssertNil(snapshot.fuelTargets(on: D.date("2030-10-23")))
    }

    // MARK: - Reward facts

    private let factDays = """
    [
      { "date": "2030-10-21", "light": "amber", "lightSource": "checkin",
        "habitsExpected": ["h1", "h2"], "habitsDone": { "h1": 1, "h2": 0 },
        "sessions": [ { "id": "a", "sport": "run", "trafficLight": true, "status": "done",
                        "options": [ { "code": "G" }, { "code": "A" }, { "code": "R" } ],
                        "done": { "option": "A" } } ] },
      { "date": "2030-10-22", "light": "red", "lightSource": "checkin",
        "sessions": [ { "id": "b", "sport": "run", "trafficLight": true, "status": "done",
                        "options": [ { "code": "G" }, { "code": "A" }, { "code": "R" } ],
                        "done": { "option": "G" } },
                      { "id": "c", "sport": "strength", "type": "strength", "status": "done" } ] },
      { "date": "2030-10-23", "light": "green", "lightSource": "option",
        "sessions": [ { "id": "d", "type": "strength", "status": "planned" } ] },
      { "date": "2030-10-24", "light": "amber", "lightSource": "checkin",
        "sessions": [ { "id": "e", "sport": "strength", "status": "done" } ] }
    ]
    """

    func testDayFactsReadOffThePlan() throws {
        let snapshot = TrainingSnapshot(projection: try projection(days: factDays))
        let facts = TrainingRewardFacts.build(snapshot: snapshot, today: D.date("2030-10-23"))
        XCTAssertEqual(facts.days.map(\.date), [D.date("2030-10-21"), D.date("2030-10-22"), D.date("2030-10-23")], "days after today are left out")

        let monday = facts.days[0]
        XCTAssertTrue(monday.checkedIn)
        XCTAssertTrue(monday.honestLightFollowed, "amber, then the A option")
        XCTAssertEqual(monday.habitTicks, 1)
        XCTAssertEqual(monday.strengthSessionsDone, 0)

        let tuesday = facts.days[1]
        XCTAssertTrue(tuesday.checkedIn)
        XCTAssertFalse(tuesday.honestLightFollowed, "red, then the G option is not following the light")
        XCTAssertEqual(tuesday.strengthSessionsDone, 1)

        let wednesday = facts.days[2]
        XCTAssertFalse(wednesday.checkedIn, "a light inferred from the option is not a check-in")
        XCTAssertEqual(wednesday.strengthSessionsDone, 0, "a planned strength session isn't done")

        XCTAssertEqual(facts.weeks.first?.strengthSessionsDone, 1)
    }

    func testThePhonesOwnCheckInAndTickCount() throws {
        let events = [
            LoggedEvent(
                event: HubEvent(id: "e1", deviceId: "ios-0000beef", seq: 1, at: "t",
                                payload: .morningCheckIn(MorningCheckInPayload(date: D.date("2030-10-23"), light: .greenLight, sessionId: nil))),
                recordedAt: Date(timeIntervalSince1970: 1_918_951_651),
                segmentID: nil
            ),
            LoggedEvent(
                event: HubEvent(id: "e2", deviceId: "ios-0000beef", seq: 2, at: "t",
                                payload: .habitTick(HabitTickPayload(date: D.date("2030-10-23"), habitId: "h9", done: true))),
                recordedAt: Date(timeIntervalSince1970: 1_918_951_652),
                segmentID: nil
            ),
        ]
        let snapshot = TrainingSnapshot(
            projection: try projection(days: factDays),
            checkIns: CheckInOverlay.fold(events, unsentSegments: [])
        )
        let wednesday = try XCTUnwrap(TrainingRewardFacts.build(snapshot: snapshot, today: D.date("2030-10-23")).days.last)
        XCTAssertTrue(wednesday.checkedIn)
        XCTAssertFalse(wednesday.honestLightFollowed, "green is never an 'honest amber/red'")
        XCTAssertEqual(wednesday.habitTicks, 1)
    }

    func testAClosedWeekWithinPlan() throws {
        let kept = try projection(weekStatus: "closed", actual: "{\"runKm\": 53, \"sessionsDone\": 5, \"sessionsMissed\": 0}", days: "[]")
        XCTAssertTrue(TrainingRewardFacts.build(snapshot: TrainingSnapshot(projection: kept), today: D.date("2030-10-28")).weeks[0].keptWithinPlan)

        let overshot = try projection(weekStatus: "closed", actual: "{\"runKm\": 58, \"sessionsDone\": 5, \"sessionsMissed\": 0}", days: "[]")
        XCTAssertFalse(TrainingRewardFacts.build(snapshot: TrainingSnapshot(projection: overshot), today: D.date("2030-10-28")).weeks[0].keptWithinPlan, "more than 10 % over the run target")

        let missed = try projection(weekStatus: "closed", actual: "{\"runKm\": 40, \"sessionsDone\": 4, \"sessionsMissed\": 1}", days: "[]")
        XCTAssertFalse(TrainingRewardFacts.build(snapshot: TrainingSnapshot(projection: missed), today: D.date("2030-10-28")).weeks[0].keptWithinPlan)

        let open = try projection(weekStatus: "approved", actual: "{\"runKm\": 20, \"sessionsDone\": 2, \"sessionsMissed\": 0}", days: "[]")
        let openWeek = TrainingRewardFacts.build(snapshot: TrainingSnapshot(projection: open), today: D.date("2030-10-23")).weeks[0]
        XCTAssertFalse(openWeek.isClosed)
        XCTAssertFalse(openWeek.keptWithinPlan, "an open week is never judged")
    }
}
