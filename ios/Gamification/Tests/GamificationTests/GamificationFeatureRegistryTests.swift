// GamificationFeatureRegistryTests.swift
//
// add-gamification-signals 5.6: all eight features are registered once, in
// the fixed order, and the stubs are inert (empty update, no badges).

import XCTest
import FoodLogCore
@testable import Gamification

final class GamificationFeatureRegistryTests: XCTestCase {
    /// Wave-2 features that have replaced their stub (each change adds its
    /// id here) -- they are tested in their own *Tests.swift files.
    private let implemented: Set<String> = [
        SeasonalEventsFeature.id, FoodCollectionsFeature.id, JourneysFeature.id, PersonalRecordsFeature.id,
        SportAndBodyFeature.id, SecretAchievementsFeature.id,
    ]

    private func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("features-\(UUID().uuidString)", isDirectory: true)
    }

    func testIdsAreUniqueAndInFixedOrder() {
        let features = GamificationFeatureRegistry.makeAll(directory: tempDirectory())
        let ids = features.map { $0.featureId }
        XCTAssertEqual(ids, ["bingo", "seasonal", "collections", "journeys", "records", "secrets", "sportBody", "boss"])
        XCTAssertEqual(ids, GamificationFeatureRegistry.orderedIds)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testStubsAreInert() async {
        let context = FeatureContext(
            snapshot: .empty,
            now: TestClock.date(2026, 9, 24),
            calendar: TestClock.calendar,
            streak: StreakEngine.status(loggedDays: [], today: TestClock.date(2026, 9, 24), calendar: TestClock.calendar),
            level: 1,
            unlockedBadgeIds: [],
            isConfirmPath: false
        )
        for feature in GamificationFeatureRegistry.makeAll(directory: tempDirectory())
        where !implemented.contains(feature.featureId) {
            let update = await feature.update(context)
            XCTAssertEqual(update, .empty, feature.featureId)
            XCTAssertTrue(feature.badges.isEmpty, feature.featureId)
        }
    }
}
