// StandaloneSignalsTests.swift
//
// add-standalone-mode 7.1 (design D11): the standalone signals input drops
// every Garmin-only source -- activities and active kcal even when the
// activity cache still holds them from Garmin days, Garmin's water total
// and weigh-ins -- and uses the phone's own weigh-ins. Pure, literal
// inputs, UTC calendar (as in DaySignalsBuilderTests).

import XCTest
@testable import FoodLogCore
import GarminKit

final class StandaloneSignalsTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func at(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    private let today = "2026-09-24"
    private var now: Date { at("2026-09-24T20:00:00Z") }

    private var garminStyleInput: SignalsInput {
        let run = ActivitySummary(id: "1", typeKey: "running", day: today, start: at("2026-09-24T06:00:00Z"), durationS: 3600, calories: 600)
        return SignalsInput(
            events: [UsageEvent(foodId: "rohlik", servingId: "s", numberOfUnits: 1, timestamp: at("2026-09-24T08:00:00Z"), nutritionDay: today, mealType: .breakfast)],
            activityDays: [DayActivity(day: today, activeKcal: 700, activities: [run])],
            localWaterMLByDay: [today: 1500],
            garminWaterByDay: [today: GarminWaterDay(totalML: 2500, goalML: 3000)],
            defaultWaterGoalML: 2000,
            weighInKgByDay: [today: 80]
        )
    }

    func testGarminModeStillSeesActivitiesAndGarminWater() {
        let day = DaySignalsBuilder.build(input: garminStyleInput, today: now, calendar: calendar).day(today)
        XCTAssertEqual(day?.availability.hasActivities, true)
        XCTAssertEqual(day?.activeKcal, 700)
        XCTAssertEqual(day?.waterML, 2500)
        XCTAssertEqual(day?.weighInKg, 80)
    }

    func testStandaloneDropsActivitiesActiveKcalAndGarminWater() {
        let localWeighIns = [
            WeightEntry(weightKg: 61.8, loggedAt: at("2026-09-24T06:30:00Z")),
            WeightEntry(weightKg: 61.2, loggedAt: at("2026-09-24T18:30:00Z")),
        ]
        let input = garminStyleInput.standalone(localWeighIns: localWeighIns, calendar: calendar)
        let day = DaySignalsBuilder.build(input: input, today: now, calendar: calendar).day(today)

        XCTAssertEqual(day?.availability.hasActivities, false, "no activity data without Garmin")
        XCTAssertNil(day?.activeKcal)
        XCTAssertEqual(day?.activities, [])
        XCTAssertEqual(day?.waterML, 1500, "the phone's own drinks only")
        XCTAssertEqual(day?.waterGoalML, 2000)
        XCTAssertEqual(day?.weighInKg, 61.2, "the day's last local weigh-in")
        XCTAssertEqual(day?.hasEntries, true, "food signals work locally")
    }

    func testLocalWeighInsKeepTheLastOfEachDay() {
        let entries = [
            WeightEntry(weightKg: 70, loggedAt: at("2026-09-23T07:00:00Z")),
            WeightEntry(weightKg: 69.5, loggedAt: at("2026-09-23T19:00:00Z")),
            WeightEntry(weightKg: 69.8, loggedAt: at("2026-09-24T07:00:00Z")),
        ]
        XCTAssertEqual(
            SignalsInput.weighInKgByDay(localEntries: entries, calendar: calendar),
            ["2026-09-23": 69.5, "2026-09-24": 69.8]
        )
    }

    func testHasFoodLogIsTheModeNeutralName() {
        XCTAssertTrue(SignalAvailability(hasGarminLog: true).hasFoodLog)
        XCTAssertFalse(SignalAvailability().hasFoodLog)
    }
}
