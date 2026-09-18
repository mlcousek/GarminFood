import XCTest
@testable import Gamification
import FoodLogCore

final class ChallengeEngineTests: XCTestCase {
    private func event(_ foodId: String, day: Int, hour: Int = 12, servingId: String = "s1") -> UsageEvent {
        UsageEvent(foodId: foodId, servingId: servingId, numberOfUnits: 1, timestamp: TestClock.date(2026, 1, day, hour: hour))
    }

    private func goalStatus(day: Int, calories: Bool = false, protein: Bool = false, carbs: Bool = false, fat: Bool = false) -> DailyGoalStatus {
        DailyGoalStatus(date: String(format: "2026-01-%02d", day), metCalorieGoal: calories, metProteinGoal: protein, metCarbGoal: carbs, metFatGoal: fat)
    }

    private func active(startDay: Int = 1, baselineStreakLength: Int = 0) -> ActiveChallenge {
        ActiveChallenge(templateId: "test", startedAt: TestClock.date(2026, 1, startDay), baselineStreakLength: baselineStreakLength)
    }

    private func template(_ id: String) -> ChallengeTemplate {
        guard let template = ChallengeCatalog.all.first(where: { $0.id == id }) else {
            fatalError("no template named \(id)")
        }
        return template
    }

    private func progress(_ id: String, events: [UsageEvent], goals: [DailyGoalStatus] = [], now: Date, active: ActiveChallenge? = nil) -> ChallengeProgress {
        let template = self.template(id)
        let activeChallenge = active ?? self.active()
        return ChallengeEngine.progress(for: template, active: activeChallenge, events: events, goalStatuses: goals, now: now)
    }

    // MARK: - Catalog sanity

    // expand-gamification-depth: the catalog was deliberately expanded from
    // 13 to 220+ (design.md D2, challenges spec's "at least 200 templates"
    // requirement) -- this replaces the old 10-15 sanity bound.
    func testCatalogHasAtLeast220Templates() {
        XCTAssertGreaterThanOrEqual(ChallengeCatalog.all.count, 220)
    }

    func testCatalogIdsAreUnique() {
        let ids = ChallengeCatalog.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testCatalogCoversAllThreeCategories() {
        let categories = Set(ChallengeCatalog.all.map(\.category))
        XCTAssertEqual(categories, [.streakExtension, .goalHitting, .varietySeeking])
    }

    // MARK: - logOnDistinctDays ("Perfect Week")

    func testPerfectWeekCompletesWhenAllSevenDaysAreLogged() {
        let events = (1...7).map { event("food-\($0)", day: $0) }
        let result = progress("perfect-week", events: events, now: TestClock.date(2026, 1, 7, hour: 20))
        XCTAssertTrue(result.isComplete)
        XCTAssertEqual(result.current, 7)
    }

    func testPerfectWeekIsIncompleteWhenOneDayIsMissedEvenIfTheStreakWouldForgiveIt() {
        // Unlike the streak itself, "Perfect Week" allows no grace at all.
        let events = [1, 2, 3, 5, 6, 7].map { event("food-\($0)", day: $0) }
        let result = progress("perfect-week", events: events, now: TestClock.date(2026, 1, 7, hour: 20))
        XCTAssertFalse(result.isComplete)
        XCTAssertEqual(result.current, 6)
    }

    // MARK: - extendStreakBy ("Keep the Flame Alive")

    func testKeepTheFlameAliveTracksStreakGrowthSinceActivation() {
        let events = (1...4).map { event("food-\($0)", day: $0) }
        let activeChallenge = active(startDay: 1, baselineStreakLength: 0)
        let result = progress("keep-the-flame-alive", events: events, now: TestClock.date(2026, 1, 4, hour: 20), active: activeChallenge)
        // Streak grew from 0 (baseline) to 4; target is +3.
        XCTAssertTrue(result.isComplete)
    }

    func testKeepTheFlameAliveIsIncompleteWhenTheStreakHasNotGrownEnough() {
        let events = [event("food-1", day: 1)]
        let activeChallenge = active(startDay: 1, baselineStreakLength: 0)
        let result = progress("keep-the-flame-alive", events: events, now: TestClock.date(2026, 1, 1, hour: 20), active: activeChallenge)
        XCTAssertFalse(result.isComplete)
        XCTAssertEqual(result.current, 1)
    }

    // MARK: - goalHitDays ("Protein Push")

    func testProteinPushCompletesOnFourOfFiveDays() {
        let goals = [
            goalStatus(day: 1, protein: true),
            goalStatus(day: 2, protein: true),
            goalStatus(day: 3, protein: false),
            goalStatus(day: 4, protein: true),
            goalStatus(day: 5, protein: true)
        ]
        let result = progress("protein-push", events: [], goals: goals, now: TestClock.date(2026, 1, 5, hour: 20))
        XCTAssertTrue(result.isComplete)
        XCTAssertEqual(result.current, 4)
    }

    func testProteinPushIsIncompleteWithOnlyThreeHitDays() {
        let goals = [
            goalStatus(day: 1, protein: true),
            goalStatus(day: 2, protein: false),
            goalStatus(day: 3, protein: true),
            goalStatus(day: 4, protein: false),
            goalStatus(day: 5, protein: true)
        ]
        let result = progress("protein-push", events: [], goals: goals, now: TestClock.date(2026, 1, 5, hour: 20))
        XCTAssertFalse(result.isComplete)
        XCTAssertEqual(result.current, 3)
    }

    // MARK: - goalHitStreak ("Goal Getter")

    func testGoalGetterCompletesOnThreeConsecutiveDaysHittingAnyGoal() {
        let goals = [
            goalStatus(day: 1, protein: true),
            goalStatus(day: 2, carbs: true),
            goalStatus(day: 3, calories: true)
        ]
        let result = progress("goal-getter", events: [], goals: goals, now: TestClock.date(2026, 1, 3, hour: 20))
        XCTAssertTrue(result.isComplete)
    }

    func testGoalGetterResetsItsConsecutiveCountOnAMissedDay() {
        let goals = [
            goalStatus(day: 1, protein: true),
            goalStatus(day: 2, carbs: false),
            goalStatus(day: 3, calories: true),
            goalStatus(day: 4, calories: true)
        ]
        let result = progress("goal-getter", events: [], goals: goals, now: TestClock.date(2026, 1, 4, hour: 20))
        // Longest consecutive run is days 3-4 (2), not 3.
        XCTAssertFalse(result.isComplete)
        XCTAssertEqual(result.current, 2)
    }

    // MARK: - newFoodsTried ("Try Something New")

    func testTryNewFoodsCountsOnlyFoodsFirstEverSeenInsideTheWindow() {
        let events = [
            event("old-food", day: 1), // first ever seen BEFORE the window
            event("new-food-a", day: 2),
            event("new-food-b", day: 3),
            event("new-food-a", day: 4), // re-logging an already-new food doesn't double count
            event("new-food-c", day: 5)
        ]
        let activeChallenge = active(startDay: 2)
        let result = progress("try-something-new", events: events, now: TestClock.date(2026, 1, 5, hour: 20), active: activeChallenge)
        XCTAssertTrue(result.isComplete)
        XCTAssertEqual(result.current, 3)
    }

    func testTryNewFoodsDoesNotCountAFoodFirstSeenBeforeActivation() {
        let events = [
            event("old-food", day: 1),
            event("old-food", day: 3) // re-logged inside the window, but not NEW
        ]
        let activeChallenge = active(startDay: 2)
        let result = progress("try-something-new", events: events, now: TestClock.date(2026, 1, 3, hour: 20), active: activeChallenge)
        XCTAssertEqual(result.current, 0)
    }

    // MARK: - mealTimeOnDistinctDays ("Breakfast Club")

    func testBreakfastClubCountsDistinctBreakfastTimeDays() {
        let events = [
            event("a", day: 1, hour: 7),
            event("b", day: 1, hour: 19), // same day, dinner time -- must not double count the day
            event("c", day: 2, hour: 8),
            event("d", day: 3, hour: 9),
            event("e", day: 4, hour: 9),
            event("f", day: 5, hour: 9)
        ]
        let result = progress("breakfast-club", events: events, now: TestClock.date(2026, 1, 5, hour: 20))
        XCTAssertTrue(result.isComplete)
        XCTAssertEqual(result.current, 5)
    }

    func testBreakfastClubDoesNotCountNonBreakfastTimeLogs() {
        let events = (1...5).map { event("food-\($0)", day: $0, hour: 19) } // all dinner-time
        let result = progress("breakfast-club", events: events, now: TestClock.date(2026, 1, 5, hour: 20))
        XCTAssertEqual(result.current, 0)
    }

    // MARK: - multiMealDays ("Full Plate")

    func testFullPlateCountsDaysWithThreeDistinctMealTimeBuckets() {
        let day1 = [event("a", day: 1, hour: 7), event("b", day: 1, hour: 12), event("c", day: 1, hour: 19)]
        let day2 = [event("d", day: 2, hour: 7), event("e", day: 2, hour: 12)] // only 2 buckets -- doesn't count
        let day3 = [event("f", day: 3, hour: 7), event("g", day: 3, hour: 16), event("h", day: 3, hour: 20)]
        let day4 = [event("i", day: 4, hour: 8), event("j", day: 4, hour: 13), event("k", day: 4, hour: 21)]
        let events = day1 + day2 + day3 + day4
        let result = progress("full-plate", events: events, now: TestClock.date(2026, 1, 4, hour: 22))
        XCTAssertTrue(result.isComplete)
        XCTAssertEqual(result.current, 3)
    }

    // MARK: - busyDays ("Triple Threat")

    func testTripleThreatCountsDaysWithAtLeastThreeEntries() {
        let day1 = ["a", "b", "c"].map { event($0, day: 1) }
        let day2 = ["d", "e"].map { event($0, day: 2) } // only 2 -- doesn't count
        let day3 = ["f", "g", "h", "i"].map { event($0, day: 3) }
        let day4 = ["j", "k", "l"].map { event($0, day: 4) }
        let events = day1 + day2 + day3 + day4
        let result = progress("triple-threat", events: events, now: TestClock.date(2026, 1, 4, hour: 22))
        XCTAssertTrue(result.isComplete)
        XCTAssertEqual(result.current, 3)
    }

    // MARK: - weekendBothDays ("Weekend Warrior")

    func testWeekendWarriorCompletesWhenBothSaturdayAndSundayAreLogged() {
        // Jan 3, 2026 is a Saturday; Jan 4 is the following Sunday.
        let events = [event("a", day: 3), event("b", day: 4)]
        let result = progress("weekend-warrior", events: events, now: TestClock.date(2026, 1, 4, hour: 20))
        XCTAssertTrue(result.isComplete)
        XCTAssertEqual(result.current, 2)
    }

    func testWeekendWarriorIsIncompleteWithOnlySaturdayLogged() {
        let events = [event("a", day: 3)]
        let result = progress("weekend-warrior", events: events, now: TestClock.date(2026, 1, 4, hour: 20))
        XCTAssertFalse(result.isComplete)
        XCTAssertEqual(result.current, 1)
    }

    // MARK: - Window elapsed (challenges spec's "also rotates after a time window")

    func testWindowElapsedIsFalseWhileStillWithinTheWindow() {
        let template = self.template("perfect-week") // 7-day window
        let activeChallenge = active(startDay: 1)
        XCTAssertFalse(ChallengeEngine.isWindowElapsed(active: activeChallenge, template: template, now: TestClock.date(2026, 1, 6, hour: 12)))
    }

    func testWindowElapsedIsTrueOnceThePeriodHasPassed() {
        let template = self.template("perfect-week") // 7-day window: Jan 1-7
        let activeChallenge = active(startDay: 1)
        XCTAssertTrue(ChallengeEngine.isWindowElapsed(active: activeChallenge, template: template, now: TestClock.date(2026, 1, 9, hour: 12)))
    }
}
