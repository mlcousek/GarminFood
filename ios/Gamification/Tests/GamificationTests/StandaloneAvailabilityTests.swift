// StandaloneAvailabilityTests.swift
//
// add-standalone-mode 7.1 (data-mode spec, "Garmin-only gamification is
// unavailable, not locked"): with a snapshot built from a STANDALONE input
// -- even when the activity cache still holds Garmin-era activities -- no
// challenge template, bingo square or journey that needs activities is
// offered; Garmin-only badges are hidden unless already earned; "complete
// every challenge" counts only what can be offered. The Garmin-mode input
// still sees activities, so the owner's phone is unchanged.

import XCTest
@testable import Gamification
import FoodLogCore

final class StandaloneAvailabilityTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private let now = ISO8601DateFormatter().date(from: "2026-09-24T20:00:00Z")!

    /// 14 days with food, water, a weigh-in and a Garmin run each.
    private var input: SignalsInput {
        var events: [UsageEvent] = []
        var activityDays: [DayActivity] = []
        var water: [String: Double] = [:]
        var weight: [String: Double] = [:]
        for offset in 0..<14 {
            let date = now.addingTimeInterval(-Double(offset) * 86_400 - 10 * 3600)
            let day = NutritionDate.string(from: date, calendar: calendar)
            events.append(UsageEvent(foodId: "rohlik", servingId: "s", numberOfUnits: 1, timestamp: date, nutritionDay: day))
            let run = ActivitySummary(id: "run-\(offset)", typeKey: "running", day: day, start: date.addingTimeInterval(-3600), durationS: 3600, calories: 500)
            activityDays.append(DayActivity(day: day, activeKcal: 600, activities: [run]))
            water[day] = 2000
            weight[day] = 70
        }
        // Known macros, so rules that need `.macros` next to `.activities`
        // are judged on the activity half alone.
        let rohlik = Food(id: "rohlik", name: "Rohlík", source: .garmin, servings: [
            Serving(id: "s", unit: "g", numberOfUnits: 100, calories: 150, carbs: 28, protein: 5, fat: 2),
        ])
        return SignalsInput(events: events, foods: ["rohlik": rohlik], activityDays: activityDays, localWaterMLByDay: water, defaultWaterGoalML: 2000, weighInKgByDay: weight)
    }

    private func snapshot(standalone: Bool) -> SignalsSnapshot {
        let source = standalone ? input.standalone(localWeighIns: [WeightEntry(weightKg: 70, loggedAt: now)], calendar: calendar) : input
        return DaySignalsBuilder.build(input: source, today: now, calendar: calendar)
    }

    private func recentDays(_ snapshot: SignalsSnapshot) -> [DaySignals] {
        snapshot.days(snapshot.recentDayKeys(14))
    }

    // MARK: Offering

    func testNoActivityChallengeIsOfferedStandalone() {
        let policy = ChallengeRotationPolicy(signals: snapshot(standalone: true))
        let activityTemplates = ChallengeCatalog.all.filter { $0.kind.dataRequirement.contains(.activities) }
        for template in activityTemplates {
            XCTAssertEqual(policy.weight(for: template), 0, "\(template.id) needs activities")
        }
    }

    func testGarminModeStillOffersActivityChallenges() {
        let policy = ChallengeRotationPolicy(signals: snapshot(standalone: false))
        let offered = ChallengeCatalog.all.filter { $0.kind.dataRequirement.contains(.activities) && policy.weight(for: $0) > 0 }
        XCTAssertFalse(offered.isEmpty, "the owner's phone keeps its activity challenges")
    }

    func testNoActivityBingoSquareIsEligibleStandalone() {
        let eligible = BingoCardGenerator.eligibleTasks(recentDays: recentDays(snapshot(standalone: true)))
        XCTAssertFalse(eligible.isEmpty, "food and water squares stay")
        XCTAssertTrue(eligible.allSatisfy { !$0.requirement.contains(.activities) })
        let garmin = BingoCardGenerator.eligibleTasks(recentDays: recentDays(snapshot(standalone: false)))
        XCTAssertGreaterThan(garmin.count, eligible.count)
    }

    func testTheRoadTripJourneyIsUnavailableStandalone() {
        let days = recentDays(snapshot(standalone: true))
        XCTAssertFalse(JourneysEvaluator.isAvailable(.road, days: days))
        XCTAssertTrue(JourneysEvaluator.isAvailable(.water, days: days))
        XCTAssertTrue(JourneysEvaluator.isAvailable(.passport, days: days))
        XCTAssertTrue(JourneysEvaluator.isAvailable(.road, days: recentDays(snapshot(standalone: false))))
    }

    func testNoBossNeedsActivities() {
        // Bosses are offered by requirement too; none may need activities,
        // or a standalone week could have no boss at all.
        for archetype in BossCatalog.all {
            XCTAssertFalse(archetype.requirement.contains(.activities), "\(archetype)")
        }
    }

    // MARK: Showing

    func testGarminOnlyBadgesAreHiddenNotLockedStandalone() {
        let catalog = SportBodyCatalog.badges
        let visible = StandaloneAvailability.visibleBadges(catalog, isStandalone: true, unlockedIds: [])
        XCTAssertTrue(visible.allSatisfy { !$0.id.hasPrefix("sport.") }, "no sport badge shown locked forever")
        XCTAssertTrue(visible.contains { $0.id == SportBodyCatalog.halfwayId }, "weight badges stay")
        XCTAssertTrue(visible.contains { $0.id == "body.fast-7" }, "fasting badges stay")
    }

    func testAnEarnedGarminOnlyBadgeStaysVisible() {
        let visible = StandaloneAvailability.visibleBadges(SportBodyCatalog.badges, isStandalone: true, unlockedIds: [SportBodyCatalog.gelGuruId])
        XCTAssertTrue(visible.contains { $0.id == SportBodyCatalog.gelGuruId })
    }

    func testGarminModeShowsEveryBadge() {
        let catalog = SportBodyCatalog.badges
        XCTAssertEqual(StandaloneAvailability.visibleBadges(catalog, isStandalone: false, unlockedIds: []), catalog)
    }

    func testTheGarminOnlySetNamesTheExpectedBadges() {
        let ids = StandaloneAvailability.garminOnlyBadgeIds
        XCTAssertTrue(ids.contains("sport.fuel-1"))
        XCTAssertTrue(ids.contains("sport.carb-loader"))
        XCTAssertTrue(ids.contains("secret.dawn-patrol"))
        XCTAssertTrue(ids.contains("journey.vienna"), "road-trip milestones come from active kcal")
        XCTAssertFalse(ids.contains("journey.bathtub"))
        XCTAssertFalse(ids.contains(SportBodyCatalog.firstKiloId))
    }

    // MARK: Complete every challenge

    func testAllChallengesCountsOnlyOfferableTemplatesStandalone() {
        let all = ChallengeRotationPolicy.allChallengesProgress(completedTemplateIds: [])
        let standalone = ChallengeRotationPolicy.allChallengesProgress(completedTemplateIds: [], excluding: .activities)
        let unchanged = ChallengeRotationPolicy.allChallengesProgress(completedTemplateIds: [], excluding: [])
        XCTAssertEqual(unchanged.total, all.total)
        XCTAssertLessThan(standalone.total, all.total)
    }
}
