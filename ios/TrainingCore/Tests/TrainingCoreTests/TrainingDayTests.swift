// TrainingDayTests.swift
//
// The training day and the heart-rate zones (tasks 2.5; design D6; spec
// "The training day follows the plan's time zone and day boundary" and
// "Heart-rate target in zones").

import XCTest
@testable import TrainingCore

final class TrainingDayTests: XCTestCase {
    private var prague: TimeZone { TimeZone(identifier: "Europe/Prague")! }
    private var newYork: TimeZone { TimeZone(identifier: "America/New_York")! }

    /// `hour:minute` local time on `date` in `zone`.
    private func instant(_ date: String, _ hour: Int, _ minute: Int, in zone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let day = D.date(date)
        return calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: hour, minute: minute))!
    }

    func testJustAfterMidnightIsStillThePreviousTrainingDay() {
        let now = instant("2026-10-21", 0, 40, in: prague)
        let day = TrainingDay.resolve(selectedDate: D.date("2026-10-21"), isToday: true, now: now, boundaryHour: 3, timeZone: prague)
        XCTAssertEqual(day.description, "2026-10-20")
    }

    func testAtTheBoundaryHourTheNewDayStarts() {
        let now = instant("2026-10-21", 3, 0, in: prague)
        XCTAssertEqual(TrainingDay.current(now: now, boundaryHour: 3, timeZone: prague).description, "2026-10-21")
        let before = instant("2026-10-21", 2, 59, in: prague)
        XCTAssertEqual(TrainingDay.current(now: before, boundaryHour: 3, timeZone: prague).description, "2026-10-20")
    }

    func testBoundaryZeroIsMidnight() {
        let now = instant("2026-10-21", 0, 5, in: prague)
        XCTAssertEqual(TrainingDay.current(now: now, boundaryHour: 0, timeZone: prague).description, "2026-10-21")
    }

    func testAnotherSelectedDateIsUsedAsIs() {
        let now = instant("2026-10-21", 0, 40, in: prague)
        let day = TrainingDay.resolve(selectedDate: D.date("2026-10-22"), isToday: false, now: now, boundaryHour: 3, timeZone: prague)
        XCTAssertEqual(day.description, "2026-10-22")
    }

    func testDaylightSavingChangeDays() {
        // Europe/Prague leaves summer time at 03:00 on 27 Oct 2030 (clocks
        // go back to 02:00). 00:30 UTC is 02:30 CEST: still the 26th.
        let utc = TimeZone(identifier: "UTC")!
        let beforeChange = instant("2030-10-27", 0, 30, in: utc)
        XCTAssertEqual(TrainingDay.current(now: beforeChange, boundaryHour: 3, timeZone: prague).description, "2030-10-26")
        // 02:30 UTC is 03:30 CET: the 27th.
        let afterChange = instant("2030-10-27", 2, 30, in: utc)
        XCTAssertEqual(TrainingDay.current(now: afterChange, boundaryHour: 3, timeZone: prague).description, "2030-10-27")
        // Spring forward: 31 Mar 2030, 02:00 -> 03:00. 01:30 UTC is 03:30 CEST.
        let spring = instant("2030-03-31", 1, 30, in: utc)
        XCTAssertEqual(TrainingDay.current(now: spring, boundaryHour: 3, timeZone: prague).description, "2030-03-31")
    }

    func testAthleteZoneWinsOverTheDevicesAndFallsBack() {
        // 05:30 in Prague is 23:30 the day before in New York.
        let now = instant("2030-10-23", 5, 30, in: prague)
        let athlete = Athlete(tz: "Europe/Prague", dayBoundaryHour: 3)
        XCTAssertEqual(TrainingDay.resolve(selectedDate: D.asOf, isToday: true, now: now, athlete: athlete, deviceTimeZone: newYork).description, "2030-10-23")
        let noZone = Athlete(tz: nil, dayBoundaryHour: 3)
        XCTAssertEqual(TrainingDay.resolve(selectedDate: D.asOf, isToday: true, now: now, athlete: noZone, deviceTimeZone: newYork).description, "2030-10-22")
        let unknownZone = Athlete(tz: "Mars/Olympus", dayBoundaryHour: 3)
        XCTAssertEqual(unknownZone.timeZone(fallback: newYork), newYork)
    }

    // MARK: Heart-rate zones

    private let zones = HRZones([
        HRZone(number: 1, low: 0, high: 128),
        HRZone(number: 2, low: 129, high: 144),
        HRZone(number: 3, low: 145, high: 156),
        HRZone(number: 4, low: 157, high: 168),
        HRZone(number: 5, low: 169, high: 185),
    ])

    func testZoneNamesIgnoreCase() {
        let mapper = HRZoneMapper(zones: zones)
        XCTAssertEqual(mapper.zone(named: "Z2")?.high, 144)
        XCTAssertEqual(mapper.zone(named: "z2")?.high, 144)
        XCTAssertNil(mapper.zone(named: "Zone 2"))
        XCTAssertEqual(HRZoneMapper.normalizedLabel(" z3 "), "Z3")
    }

    func testCeilingFloorAndBandLabels() {
        let mapper = HRZoneMapper(zones: zones)
        XCTAssertEqual(mapper.label(zone: nil, hrMin: nil, hrMax: 144), "Z2") // top edge
        XCTAssertEqual(mapper.label(zone: nil, hrMin: nil, hrMax: 129), "Z2") // bottom edge
        XCTAssertEqual(mapper.label(zone: nil, hrMin: nil, hrMax: 128), "Z1")
        XCTAssertEqual(mapper.label(zone: nil, hrMin: 150, hrMax: nil), "Z3")
        XCTAssertEqual(mapper.label(zone: nil, hrMin: 146, hrMax: 156), "Z3")
        XCTAssertNil(mapper.label(zone: nil, hrMin: 140, hrMax: 150)) // spans two zones
        XCTAssertEqual(mapper.label(zone: "z4", hrMin: nil, hrMax: 140), "Z4") // explicit wins
        XCTAssertNil(mapper.label(zone: nil, hrMin: nil, hrMax: nil))
    }

    func testNoZonesMeansNoLabelButBpmStay() {
        let mapper = HRZoneMapper(zones: nil)
        XCTAssertNil(mapper.label(zone: nil, hrMin: nil, hrMax: 144))
        let targets = TargetFormatter(text: TrainingText(.english), zones: mapper)
        XCTAssertEqual(targets.heartRate(Targets(hrMax: 144)), "≤144 bpm")
        XCTAssertEqual(targets.heartRate(Targets(zone: "Z2")), "Z2")
    }

    /// Spec: option G targets `hrMax: 144` and zone 2 is 129-144.
    func testHeartRateTargetInZones() {
        let targets = TargetFormatter(text: TrainingText(.english), zones: HRZoneMapper(zones: zones))
        XCTAssertEqual(targets.heartRate(Targets(hrMax: 144)), "≤144 bpm · Z2")
        XCTAssertEqual(targets.heartRate(Targets(hrMin: 129, hrMax: 144)), "129–144 bpm · Z2")
        XCTAssertEqual(targets.heartRate(Targets(hrMin: 140, hrMax: 150)), "140–150 bpm")
        XCTAssertEqual(targets.heartRate(Targets(zone: "Z2")), "Z2 · 129–144 bpm")
        XCTAssertEqual(targets.heartRate(Targets(hrMin: 150)), "≥150 bpm · Z3")
        XCTAssertNil(targets.heartRate(Targets(km: 12)))
        XCTAssertEqual(targets.lines(Targets(km: 12, hrMax: 144)), ["12 km", "≤144 bpm · Z2"])
        XCTAssertEqual(targets.summary(Targets(km: 12, min: 60)), "12 km · 1 h")
    }
}
