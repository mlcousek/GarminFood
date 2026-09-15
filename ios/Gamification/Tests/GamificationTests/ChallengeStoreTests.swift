import XCTest
@testable import Gamification

final class ChallengeStoreTests: XCTestCase {
    private func makeStore() -> ChallengeStore {
        ChallengeStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("gamification-challenge-\(UUID().uuidString).json"))
    }

    func testEnsureActiveActivatesATemplateWhenNoneIsActive() async throws {
        let store = makeStore()
        let initial = await store.current()
        XCTAssertNil(initial)

        let activated = try await store.ensureActive(catalog: ChallengeCatalog.all, now: TestClock.date(2026, 1, 1), baselineStreakLength: 0)
        XCTAssertTrue(ChallengeCatalog.all.contains { $0.id == activated.templateId })

        let current = await store.current()
        XCTAssertEqual(current, activated)
    }

    func testEnsureActiveDoesNotReplaceAnAlreadyActiveChallenge() async throws {
        let store = makeStore()
        let first = try await store.ensureActive(catalog: ChallengeCatalog.all, now: TestClock.date(2026, 1, 1), baselineStreakLength: 0)
        let second = try await store.ensureActive(catalog: ChallengeCatalog.all, now: TestClock.date(2026, 1, 5), baselineStreakLength: 3)
        XCTAssertEqual(first, second)
    }

    func testCompleteAndRotateActivatesADifferentChallengeWhenMoreThanOneTemplateExists() async throws {
        let store = makeStore()
        let first = try await store.ensureActive(catalog: ChallengeCatalog.all, now: TestClock.date(2026, 1, 1), baselineStreakLength: 0)
        let second = try await store.completeAndRotate(catalog: ChallengeCatalog.all, now: TestClock.date(2026, 1, 2), baselineStreakLength: 1)
        XCTAssertNotEqual(first.templateId, second.templateId, "rotation should avoid immediately repeating the just-completed template")
    }

    func testRotateIfWindowElapsedReturnsFalseWhileWithinTheWindow() async throws {
        let store = makeStore()
        _ = try await store.ensureActive(catalog: [ChallengeCatalog.all.first(where: { $0.id == "perfect-week" })!], now: TestClock.date(2026, 1, 1), baselineStreakLength: 0)
        let rotated = try await store.rotateIfWindowElapsed(catalog: ChallengeCatalog.all, now: TestClock.date(2026, 1, 3), baselineStreakLength: 0)
        XCTAssertFalse(rotated)
    }

    func testRotateIfWindowElapsedReplacesAStaleChallenge() async throws {
        let store = makeStore()
        let originalCatalog = [ChallengeCatalog.all.first(where: { $0.id == "perfect-week" })!] // 7-day window
        let original = try await store.ensureActive(catalog: originalCatalog, now: TestClock.date(2026, 1, 1), baselineStreakLength: 0)
        let rotated = try await store.rotateIfWindowElapsed(catalog: ChallengeCatalog.all, now: TestClock.date(2026, 1, 10), baselineStreakLength: 0)
        XCTAssertTrue(rotated)
        let current = await store.current()
        XCTAssertNotEqual(current?.templateId, original.templateId)
    }

    func testPersistsAcrossStoreInstancesPointingAtTheSameFile() async throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("gamification-challenge-\(UUID().uuidString).json")
        let store1 = ChallengeStore(fileURL: fileURL)
        let activated = try await store1.ensureActive(catalog: ChallengeCatalog.all, now: TestClock.date(2026, 1, 1), baselineStreakLength: 0)

        let store2 = ChallengeStore(fileURL: fileURL)
        let current = await store2.current()
        XCTAssertEqual(current, activated)
    }
}

final class ChallengeRotationTests: XCTestCase {
    func testPickNextIsDeterministicForTheSameInputs() {
        let now = TestClock.date(2026, 1, 1)
        let first = ChallengeRotation.pickNext(from: ChallengeCatalog.all, excluding: [], now: now)
        let second = ChallengeRotation.pickNext(from: ChallengeCatalog.all, excluding: [], now: now)
        XCTAssertEqual(first.id, second.id)
    }

    func testPickNextNeverReturnsAnExcludedTemplateWhenAlternativesExist() {
        let now = TestClock.date(2026, 1, 1)
        let excluded = Set(ChallengeCatalog.all.dropLast().map(\.id)) // exclude all but one
        let picked = ChallengeRotation.pickNext(from: ChallengeCatalog.all, excluding: excluded, now: now)
        XCTAssertFalse(excluded.contains(picked.id))
    }

    func testPickNextFallsBackToTheFullCatalogWhenEverythingIsExcluded() {
        let now = TestClock.date(2026, 1, 1)
        let excluded = Set(ChallengeCatalog.all.map(\.id))
        let picked = ChallengeRotation.pickNext(from: ChallengeCatalog.all, excluding: excluded, now: now)
        XCTAssertTrue(ChallengeCatalog.all.contains { $0.id == picked.id })
    }
}
