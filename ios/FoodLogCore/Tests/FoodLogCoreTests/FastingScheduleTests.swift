// FastingScheduleTests.swift
//
// Schedule math for FastingSchedule.swift (redesign-fasting-schedule 1.1):
// same-day and overnight windows, exact boundaries, midnight edges, and
// both 2026 Europe/Prague DST transition days (spring forward Sun 29 Mar
// 02:00 CET -> 03:00 CEST; fall back Sun 25 Oct 03:00 CEST -> 02:00 CET).
// Every test uses an explicit Prague calendar so the result never depends
// on the CI runner's own time zone. Absolute instants around a DST switch
// are written in UTC (`utc(...)`), where there's no ambiguity to trip on.

import XCTest
@testable import FoodLogCore

final class FastingScheduleTests: XCTestCase {
    private let hour: TimeInterval = 3600
    private let minute: TimeInterval = 60

    private var prague: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
        return calendar
    }

    /// A Prague wall-clock time. Only used for times that exist exactly
    /// once on their day (never inside a DST switch hour).
    private func local(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        prague.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func utc(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func schedule(_ startHour: Int, _ startMinute: Int, _ endHour: Int, _ endMinute: Int) -> FastingSchedule {
        FastingSchedule(startMinute: startHour * 60 + startMinute, endMinute: endHour * 60 + endMinute)!
    }

    // MARK: - Construction

    func testStandardScheduleIsTwentyToTwelve() {
        let standard = FastingSchedule.standard
        XCTAssertEqual(standard.startMinute, 20 * 60)
        XCTAssertEqual(standard.endMinute, 12 * 60)
        XCTAssertTrue(standard.crossesMidnight)
        XCTAssertEqual(standard.fastingMinutes, 16 * 60, "spec: 20:00-12:00 shows as a 16 h fast")
        XCTAssertEqual(standard.eatingMinutes, 8 * 60, "spec: ... and 8 h eating")
    }

    func testEqualStartAndEndIsRejected() {
        XCTAssertNil(FastingSchedule(startMinute: 600, endMinute: 600))
        XCTAssertNil(FastingSchedule(startMinute: 0, endMinute: 1440), "1440 wraps to 0, the same clock time")
    }

    func testMinutesAreWrappedIntoOneDay() {
        let wrapped = FastingSchedule(startMinute: -60, endMinute: 1500)!
        XCTAssertEqual(wrapped.startMinute, 23 * 60)
        XCTAssertEqual(wrapped.endMinute, 60)
        XCTAssertTrue(wrapped.crossesMidnight)
        XCTAssertEqual(wrapped.fastingMinutes, 120)
    }

    func testSameDayScheduleDoesNotCrossMidnight() {
        let sameDay = schedule(8, 0, 14, 0)
        XCTAssertFalse(sameDay.crossesMidnight)
        XCTAssertEqual(sameDay.fastingMinutes, 6 * 60)
        XCTAssertEqual(sameDay.eatingMinutes, 18 * 60)
    }

    // MARK: - Windows on an ordinary day

    func testSameDayWindowStartsAndEndsOnTheSameDay() {
        let sameDay = schedule(8, 0, 14, 0)

        let window = sameDay.window(startingOn: local(2026, 9, 23, 17), calendar: prague)

        XCTAssertEqual(window?.start, local(2026, 9, 23, 8))
        XCTAssertEqual(window?.end, local(2026, 9, 23, 14))
        XCTAssertEqual(sameDay.window(forFastEndingOn: local(2026, 9, 23, 1), calendar: prague), window)
    }

    func testOvernightWindowEndingOnADayStartedTheEveningBefore() {
        let window = FastingSchedule.standard.window(forFastEndingOn: local(2026, 9, 23, 15), calendar: prague)

        XCTAssertEqual(window?.start, local(2026, 9, 22, 20))
        XCTAssertEqual(window?.end, local(2026, 9, 23, 12))
        XCTAssertEqual(window?.duration ?? 0, 16 * hour, accuracy: 0.001)
    }

    func testOvernightWindowStartingOnADayEndsTheNextDay() {
        let window = FastingSchedule.standard.window(startingOn: local(2026, 9, 23, 3), calendar: prague)

        XCTAssertEqual(window?.start, local(2026, 9, 23, 20))
        XCTAssertEqual(window?.end, local(2026, 9, 24, 12))
    }

    func testMidnightStartIsTheStartOfThatDay() {
        let window = schedule(0, 0, 8, 0).window(startingOn: local(2026, 9, 23, 15), calendar: prague)

        XCTAssertEqual(window?.start, local(2026, 9, 23, 0))
        XCTAssertEqual(window?.end, local(2026, 9, 23, 8))
    }

    func testMidnightEndBelongsToTheNextDay() {
        let untilMidnight = schedule(16, 0, 0, 0)
        XCTAssertTrue(untilMidnight.crossesMidnight)

        let window = untilMidnight.window(startingOn: local(2026, 9, 23, 9), calendar: prague)

        XCTAssertEqual(window?.start, local(2026, 9, 23, 16))
        XCTAssertEqual(window?.end, local(2026, 9, 24, 0))
        XCTAssertEqual(untilMidnight.window(forFastEndingOn: local(2026, 9, 24, 9), calendar: prague), window)
        XCTAssertEqual(untilMidnight.phase(at: local(2026, 9, 24, 0), calendar: prague)?.kind, .eating, "midnight itself is already the eating window")
    }

    // MARK: - Phase (spec scenarios)

    func testDuringTheFastAtSevenTwenty() {
        let now = local(2026, 9, 23, 7, 20)

        let phase = FastingSchedule.standard.phase(at: now, calendar: prague)

        XCTAssertEqual(phase?.kind, .fasting)
        XCTAssertEqual(phase?.startedAt, local(2026, 9, 22, 20))
        XCTAssertEqual(phase?.scheduledEndAt, local(2026, 9, 23, 12), "eating opens at 12:00")
        XCTAssertEqual(phase?.elapsed(at: now) ?? 0, 11 * hour + 20 * minute, accuracy: 0.001, "spec: 11 h 20 m in")
    }

    func testDuringTheEatingWindowAtTenToFive() {
        let now = local(2026, 9, 23, 16, 50)

        let phase = FastingSchedule.standard.phase(at: now, calendar: prague)

        XCTAssertEqual(phase?.kind, .eating)
        XCTAssertEqual(phase?.startedAt, local(2026, 9, 23, 12))
        XCTAssertEqual(phase?.scheduledEndAt, local(2026, 9, 23, 20), "closes at 20:00")
        XCTAssertEqual(phase?.remaining(at: now) ?? 0, 3 * hour + 10 * minute, accuracy: 0.001, "spec: 3 h 10 m left")
    }

    func testJustAfterMidnightIsStillInYesterdayEveningsFast() {
        let phase = FastingSchedule.standard.phase(at: local(2026, 9, 23, 0, 30), calendar: prague)

        XCTAssertEqual(phase?.kind, .fasting)
        XCTAssertEqual(phase?.startedAt, local(2026, 9, 22, 20))
        XCTAssertEqual(phase?.scheduledEndAt, local(2026, 9, 23, 12))
    }

    func testExactBoundariesAreHalfOpen() {
        let standard = FastingSchedule.standard

        let atEnd = standard.phase(at: local(2026, 9, 23, 12), calendar: prague)
        XCTAssertEqual(atEnd?.kind, .eating, "12:00 on a fast until 12:00 is already eating")
        XCTAssertEqual(atEnd?.startedAt, local(2026, 9, 23, 12))

        let justBeforeEnd = standard.phase(at: local(2026, 9, 23, 12).addingTimeInterval(-1), calendar: prague)
        XCTAssertEqual(justBeforeEnd?.kind, .fasting)

        let atStart = standard.phase(at: local(2026, 9, 23, 20), calendar: prague)
        XCTAssertEqual(atStart?.kind, .fasting, "20:00 on a fast from 20:00 is already fasting")
        XCTAssertEqual(atStart?.startedAt, local(2026, 9, 23, 20))
        XCTAssertEqual(atStart?.scheduledEndAt, local(2026, 9, 24, 12))

        let justBeforeStart = standard.phase(at: local(2026, 9, 23, 20).addingTimeInterval(-1), calendar: prague)
        XCTAssertEqual(justBeforeStart?.kind, .eating)
        XCTAssertEqual(justBeforeStart?.scheduledEndAt, local(2026, 9, 23, 20))
    }

    func testSameDayScheduleEatingSpansMidnight() {
        let sameDay = schedule(8, 0, 14, 0)

        let early = sameDay.phase(at: local(2026, 9, 23, 3), calendar: prague)
        XCTAssertEqual(early?.kind, .eating)
        XCTAssertEqual(early?.startedAt, local(2026, 9, 22, 14))
        XCTAssertEqual(early?.scheduledEndAt, local(2026, 9, 23, 8))

        let late = sameDay.phase(at: local(2026, 9, 23, 20), calendar: prague)
        XCTAssertEqual(late?.kind, .eating)
        XCTAssertEqual(late?.startedAt, local(2026, 9, 23, 14))
        XCTAssertEqual(late?.scheduledEndAt, local(2026, 9, 24, 8))

        XCTAssertEqual(sameDay.phase(at: local(2026, 9, 23, 10), calendar: prague)?.kind, .fasting)
    }

    func testWindowContainingIsNilDuringEating() {
        XCTAssertNil(FastingSchedule.standard.window(containing: local(2026, 9, 23, 15), calendar: prague))
        XCTAssertEqual(
            FastingSchedule.standard.window(containing: local(2026, 9, 23, 9), calendar: prague)?.end,
            local(2026, 9, 23, 12)
        )
    }

    func testFractionIsClamped() {
        let phase = FastingPhase(kind: .fasting, startedAt: Date(timeIntervalSince1970: 0), scheduledEndAt: Date(timeIntervalSince1970: 16 * hour))
        XCTAssertEqual(phase.fraction(at: Date(timeIntervalSince1970: 0)), 0)
        XCTAssertEqual(phase.fraction(at: Date(timeIntervalSince1970: 8 * hour)), 0.5, accuracy: 0.001)
        XCTAssertEqual(phase.fraction(at: Date(timeIntervalSince1970: 40 * hour)), 1)
    }

    // MARK: - DST: spring forward (Sun 29 Mar 2026, 02:00 CET -> 03:00 CEST)

    func testOvernightFastOnTheSpringForwardNightIsFifteenHours() {
        let window = FastingSchedule.standard.window(forFastEndingOn: local(2026, 3, 29, 15), calendar: prague)

        XCTAssertEqual(window?.start, utc(2026, 3, 28, 19), "20:00 CET")
        XCTAssertEqual(window?.end, utc(2026, 3, 29, 10), "12:00 CEST")
        XCTAssertEqual(window?.duration ?? 0, 15 * hour, accuracy: 0.001, "the clock skips an hour, so the same 20:00-12:00 is an hour shorter")
    }

    func testPhaseOnTheSpringForwardMorningReadsTheRealElapsedTime() {
        let now = utc(2026, 3, 29, 5, 20) // 07:20 CEST

        let phase = FastingSchedule.standard.phase(at: now, calendar: prague)

        XCTAssertEqual(phase?.kind, .fasting)
        XCTAssertEqual(phase?.startedAt, utc(2026, 3, 28, 19))
        XCTAssertEqual(phase?.scheduledEndAt, utc(2026, 3, 29, 10))
        XCTAssertEqual(phase?.elapsed(at: now) ?? 0, 10 * hour + 20 * minute, accuracy: 0.001, "11 h 20 m on the clock, but only 10 h 20 m really elapsed")
    }

    func testSameDayWindowAcrossTheSpringForwardHour() {
        let window = schedule(1, 0, 5, 0).window(startingOn: local(2026, 3, 29, 12), calendar: prague)

        XCTAssertEqual(window?.start, utc(2026, 3, 29, 0), "01:00 CET")
        XCTAssertEqual(window?.end, utc(2026, 3, 29, 3), "05:00 CEST")
        XCTAssertEqual(window?.duration ?? 0, 3 * hour, accuracy: 0.001)
        XCTAssertEqual(schedule(1, 0, 5, 0).phase(at: utc(2026, 3, 29, 0, 45), calendar: prague)?.kind, .fasting, "01:45 CET, just before the jump")
    }

    func testAnEndTimeInsideTheSkippedHourResolvesJustAfterTheJump() {
        // 02:30 doesn't exist on 29 Mar in Prague. It must resolve to a real
        // moment right after the jump (03:00 or 03:30 CEST) -- never nil,
        // never a day off.
        let window = schedule(22, 0, 2, 30).window(forFastEndingOn: local(2026, 3, 29, 12), calendar: prague)

        XCTAssertEqual(window?.start, utc(2026, 3, 28, 21), "22:00 CET")
        guard let end = window?.end else {
            return XCTFail("a skipped end time must still produce a window")
        }
        XCTAssertGreaterThanOrEqual(end, utc(2026, 3, 29, 1), "no earlier than 03:00 CEST")
        XCTAssertLessThanOrEqual(end, utc(2026, 3, 29, 1, 30), "no later than 03:30 CEST")
    }

    // MARK: - DST: fall back (Sun 25 Oct 2026, 03:00 CEST -> 02:00 CET)

    func testOvernightFastOnTheFallBackNightIsSeventeenHours() {
        let window = FastingSchedule.standard.window(forFastEndingOn: local(2026, 10, 25, 15), calendar: prague)

        XCTAssertEqual(window?.start, utc(2026, 10, 24, 18), "20:00 CEST")
        XCTAssertEqual(window?.end, utc(2026, 10, 25, 11), "12:00 CET")
        XCTAssertEqual(window?.duration ?? 0, 17 * hour, accuracy: 0.001, "the clock repeats an hour, so the same 20:00-12:00 is an hour longer")
    }

    func testPhaseOnTheFallBackMorningReadsTheRealElapsedTime() {
        let now = utc(2026, 10, 25, 6, 20) // 07:20 CET

        let phase = FastingSchedule.standard.phase(at: now, calendar: prague)

        XCTAssertEqual(phase?.kind, .fasting)
        XCTAssertEqual(phase?.elapsed(at: now) ?? 0, 12 * hour + 20 * minute, accuracy: 0.001)
        XCTAssertEqual(phase?.remaining(at: now) ?? 0, 4 * hour + 40 * minute, accuracy: 0.001)
    }

    func testSameDayWindowAcrossTheFallBackHour() {
        let window = schedule(1, 0, 5, 0).window(startingOn: local(2026, 10, 25, 12), calendar: prague)

        XCTAssertEqual(window?.start, utc(2026, 10, 24, 23), "01:00 CEST")
        XCTAssertEqual(window?.end, utc(2026, 10, 25, 4), "05:00 CET")
        XCTAssertEqual(window?.duration ?? 0, 5 * hour, accuracy: 0.001)
    }

    func testAnEndTimeInsideTheRepeatedHourResolvesToOneOfItsTwoOccurrences() {
        // 02:30 happens twice on 25 Oct in Prague (00:30 and 01:30 UTC).
        let window = schedule(22, 0, 2, 30).window(forFastEndingOn: local(2026, 10, 25, 12), calendar: prague)

        XCTAssertEqual(window?.start, utc(2026, 10, 24, 20), "22:00 CEST")
        let end = window?.end
        XCTAssertTrue(end == utc(2026, 10, 25, 0, 30) || end == utc(2026, 10, 25, 1, 30), "got \(String(describing: end))")
    }

    func testTheDayAfterEachDSTSwitchIsBackToSixteenHours() {
        let afterSpring = FastingSchedule.standard.window(forFastEndingOn: local(2026, 3, 30, 15), calendar: prague)
        let afterAutumn = FastingSchedule.standard.window(forFastEndingOn: local(2026, 10, 26, 15), calendar: prague)

        XCTAssertEqual(afterSpring?.duration ?? 0, 16 * hour, accuracy: 0.001)
        XCTAssertEqual(afterAutumn?.duration ?? 0, 16 * hour, accuracy: 0.001)
    }

    // MARK: - Logging note

    func testLoggingDuringTheFastReportsWhenItEnds() {
        let end = FastingSchedule.standard.fastEndIfLogging(at: local(2026, 9, 23, 9), forDay: local(2026, 9, 23, 0), calendar: prague)
        XCTAssertEqual(end, local(2026, 9, 23, 12), "spec: \"You're fasting until 12:00\"")
    }

    func testLoggingDuringTheEatingWindowReportsNothing() {
        XCTAssertNil(FastingSchedule.standard.fastEndIfLogging(at: local(2026, 9, 23, 13), forDay: local(2026, 9, 23, 0), calendar: prague))
    }

    func testBackfillingYesterdayDuringTheFastReportsNothing() {
        XCTAssertNil(
            FastingSchedule.standard.fastEndIfLogging(at: local(2026, 9, 23, 9), forDay: local(2026, 9, 22, 0), calendar: prague),
            "yesterday's dinner entered this morning doesn't break this morning's fast"
        )
    }
}
