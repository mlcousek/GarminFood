import XCTest
@testable import Gamification

final class StreakEngineTests: XCTestCase {
    private let calendar = TestClock.calendar

    private func status(_ days: [Date], now: Date) -> StreakEngine.Status {
        StreakEngine.status(eventTimestamps: days, now: now, calendar: calendar)
    }

    // MARK: - Basic scenarios (streaks spec)

    func testNoHistoryIsZero() {
        let result = status([], now: TestClock.date(2026, 1, 5))
        XCTAssertEqual(result.length, 0)
        XCTAssertFalse(result.hasLoggedToday)
        XCTAssertFalse(result.isAtRiskToday)
        XCTAssertNil(result.lastLoggedDay)
    }

    func testFiveConsecutiveDaysLoggedIsAStreakOfFive() {
        let days = (1...5).map { TestClock.date(2026, 1, $0) }
        let result = status(days, now: TestClock.date(2026, 1, 5, hour: 20))
        XCTAssertEqual(result.length, 5)
        XCTAssertTrue(result.hasLoggedToday)
        XCTAssertFalse(result.isAtRiskToday, "today is already logged -- this is the 'safe' state")
    }

    func testNothingLoggedYetTodayButYesterdayLoggedIsAtRisk() {
        let days = (1...5).map { TestClock.date(2026, 1, $0) }
        // "now" is day 6, before anything has been logged that day.
        let result = status(days, now: TestClock.date(2026, 1, 6, hour: 9))
        XCTAssertEqual(result.length, 5, "the streak as of yesterday is still intact")
        XCTAssertFalse(result.hasLoggedToday)
        XCTAssertTrue(result.isAtRiskToday)
    }

    // 2026-09-21 bug fix: `isAtRiskToday` used to require yesterday itself
    // to have been logged, which was false -- reporting "not at risk" --
    // on exactly the day after a grace-forgiven miss, even though a SECOND
    // miss today (the day after) is not forgiven and resets the streak.
    func testADayAfterAGraceForgivenMissIsStillAtRisk() {
        // Jan 1-5 logged (streak 5), Jan 6 missed (the week's one grace,
        // forgiven, streak stays 5), "now" is Jan 7 with nothing logged
        // yet -- missing today too would be the second miss in the
        // rolling window and would reset the whole streak.
        let days = (1...5).map { TestClock.date(2026, 1, $0) }
        let result = status(days, now: TestClock.date(2026, 1, 7, hour: 9))
        XCTAssertEqual(result.length, 5, "the grace-forgiven miss on Jan 6 does not reduce the streak")
        XCTAssertFalse(result.hasLoggedToday)
        XCTAssertTrue(result.isAtRiskToday, "missing today too would be the second miss in the window and reset the streak")
    }

    func testTwoConsecutiveMissedDaysLeavesNoAtRiskState() {
        // Logged day 1 only; day 2 is missed (forgiven, the week's one
        // grace), day 3 is ALSO missed -- the second miss within the
        // rolling window, so by "now" (day 4) the streak has already
        // reset to zero. A reset streak has nothing left to be "at risk".
        let days = [TestClock.date(2026, 1, 1)]
        let result = status(days, now: TestClock.date(2026, 1, 4, hour: 9))
        XCTAssertEqual(result.length, 0)
        XCTAssertFalse(result.isAtRiskToday, "there is no live streak left to be 'at risk'")
    }

    // MARK: - Named edge cases (design.md Risks: "these are exactly the
    // cases worth writing tests for before shipping")

    /// "A miss immediately followed by a make-up day" -- a single isolated
    /// miss is forgiven and the chain continues, but the missed day itself
    /// contributes no length (streaks spec: "as if it had not occurred").
    func testSingleMissImmediatelyFollowedByAMakeUpDayIsForgiven() {
        // Jan 1-3 logged, Jan 4 missed, Jan 5-7 logged.
        var days = [1, 2, 3].map { TestClock.date(2026, 1, $0) }
        days += [5, 6, 7].map { TestClock.date(2026, 1, $0) }
        let result = status(days, now: TestClock.date(2026, 1, 7, hour: 20))
        XCTAssertEqual(result.length, 6, "6 logged days survive; the miss is skipped, not subtracted from further")
        XCTAssertTrue(result.hasLoggedToday)
    }

    /// "Two misses in one week" -- design.md D2 / streaks spec's own
    /// scenario: the SECOND miss within the rolling 7-day window resets
    /// the streak to zero, counting again only from the next logged day.
    func testTwoMissesWithinARollingWeekResetsTheStreak() {
        // Jan 1-3 logged (streak 3), Jan 4 missed (forgiven), Jan 5 logged
        // (streak continues to 4), Jan 6 missed (2 days after the Jan 4
        // miss -- second miss within the rolling window -> reset), Jan 7
        // logged (streak restarts at 1).
        var days = [1, 2, 3].map { TestClock.date(2026, 1, $0) }
        days.append(TestClock.date(2026, 1, 5))
        days.append(TestClock.date(2026, 1, 7))
        let result = status(days, now: TestClock.date(2026, 1, 7, hour: 20))
        XCTAssertEqual(result.length, 1, "the streak resets and counts again only from the day logged after the second miss")
        XCTAssertTrue(result.hasLoggedToday)
    }

    /// "A miss straddling a week boundary" -- design.md D2's named risk.
    /// Jan 3, 2026 is a Saturday (last day of a Sunday-starting calendar
    /// week) and Jan 5, 2026 is the following Monday (first weekday of the
    /// NEXT Sunday-starting calendar week) -- only 2 days apart. A
    /// (deliberately wrong) implementation that resets its "one grace per
    /// literal calendar week" bookkeeping every Sunday would wrongly
    /// forgive BOTH misses, since each looks like "the first miss of its
    /// own week." The actual rule is a pure rolling 7-day window with no
    /// concept of calendar weeks at all, so two misses only 2 days apart
    /// must still trigger a reset regardless of which calendar week each
    /// nominally falls in.
    func testMissStraddlingACalendarWeekBoundaryStillResets() {
        // Jan 1 (Thu), Jan 2 (Fri) logged; Jan 3 (Sat) missed (forgiven);
        // Jan 4 (Sun) logged; Jan 5 (Mon) missed -- 2 days after the Jan 3
        // miss, so this is the second miss in the rolling window.
        var days = [1, 2].map { TestClock.date(2026, 1, $0) }
        days.append(TestClock.date(2026, 1, 4))
        days.append(TestClock.date(2026, 1, 6))
        let result = status(days, now: TestClock.date(2026, 1, 6, hour: 20))
        XCTAssertEqual(result.length, 1, "Jan 3 and Jan 5's misses are only 2 days apart and must reset, despite nominally spanning a Sun/Mon week boundary")
    }

    /// The complementary case: two misses far enough apart (7+ days) that
    /// they are NOT in the same rolling window, even though one falls at
    /// the tail of one calendar week and the other near the start of the
    /// next -- both are independently forgiven, and the streak must not
    /// reset just because a naive implementation thought "a new calendar
    /// week started."
    func testMissesMoreThanAWeekApartAreBothIndependentlyForgiven() {
        // Jan 1-2 logged, Jan 3 missed (forgiven), Jan 4-9 logged (6 days),
        // Jan 10 missed (7 days after the Jan 3 miss -- outside the
        // rolling window, so independently forgiven), Jan 11 logged.
        var days = [1, 2].map { TestClock.date(2026, 1, $0) }
        days += (4...9).map { TestClock.date(2026, 1, $0) }
        days.append(TestClock.date(2026, 1, 11))
        let result = status(days, now: TestClock.date(2026, 1, 11, hour: 20))
        XCTAssertEqual(result.length, 9, "both misses are forgiven independently since they are 7 days apart, not 6")
    }

    // MARK: - Nutrition-day boundary (design.md D1)

    func testALogBeforeTheBoundaryHourCountsTowardThePreviousNutritionDay() {
        // 03:00 on Jan 2 is before the 04:00 boundary -- it should count
        // toward Jan 1's nutrition-day, not Jan 2's.
        let earlyLog = TestClock.date(2026, 1, 2, hour: 3)
        let result = status([earlyLog], now: TestClock.date(2026, 1, 2, hour: 20))
        XCTAssertFalse(result.hasLoggedToday, "a 03:00 log belongs to the PREVIOUS nutrition day, not the one 'now' (20:00) is in")
        XCTAssertEqual(result.length, 1, "yesterday's (Jan 1's) nutrition-day is still what's logged, and is one day removed from a Jan-2 'now'")
    }

    func testALogAtOrAfterTheBoundaryHourCountsTowardThatCalendarDay() {
        let log = TestClock.date(2026, 1, 2, hour: 5)
        let result = status([log], now: TestClock.date(2026, 1, 2, hour: 20))
        XCTAssertTrue(result.hasLoggedToday)
        XCTAssertEqual(result.length, 1)
    }
}
