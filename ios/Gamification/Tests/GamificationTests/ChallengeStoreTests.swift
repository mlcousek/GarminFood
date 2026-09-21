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

    // 2026-09-21 bug fix: the old unconditional `completeAndRotate` was
    // removed entirely (see ChallengeStore.swift's doc comment) -- its
    // "rotation should avoid immediately repeating the just-completed
    // template" guarantee is now covered by
    // `testCompleteAndRotateIfStillActiveRotatesWhenTheTemplateIsStillActive`
    // below, via the replacement atomic method.

    // 2026-09-21 bug fix: `completeAndRotateIfStillActive` closes the race
    // where two overlapping `handleLogConfirmed()` calls could both see
    // the same challenge as complete and both rotate/award. It must be a
    // no-op (return nil, no rotation) once the active challenge is no
    // longer the one the caller thinks it's completing.
    func testCompleteAndRotateIfStillActiveRotatesWhenTheTemplateIsStillActive() async throws {
        let store = makeStore()
        let active = try await store.ensureActive(catalog: ChallengeCatalog.all, now: TestClock.date(2026, 1, 1), baselineStreakLength: 0)

        let rotated = try await store.completeAndRotateIfStillActive(templateId: active.templateId, catalog: ChallengeCatalog.all, now: TestClock.date(2026, 1, 2), baselineStreakLength: 1)

        XCTAssertNotNil(rotated)
        let current = await store.current()
        XCTAssertEqual(current, rotated)
        XCTAssertNotEqual(current?.templateId, active.templateId, "should have rotated to a different template")
    }

    func testCompleteAndRotateIfStillActiveIsANoOpWhenTheTemplateIsNoLongerActive() async throws {
        let store = makeStore()
        let active = try await store.ensureActive(catalog: ChallengeCatalog.all, now: TestClock.date(2026, 1, 1), baselineStreakLength: 0)
        // Simulates a concurrent caller having already completed/rotated
        // this exact instance first.
        let alreadyRotated = try await store.completeAndRotateIfStillActive(templateId: active.templateId, catalog: ChallengeCatalog.all, now: TestClock.date(2026, 1, 2), baselineStreakLength: 1)
        XCTAssertNotNil(alreadyRotated)

        // A second, overlapping call for the ORIGINAL (now stale) templateId.
        let secondAttempt = try await store.completeAndRotateIfStillActive(templateId: active.templateId, catalog: ChallengeCatalog.all, now: TestClock.date(2026, 1, 2), baselineStreakLength: 1)

        XCTAssertNil(secondAttempt, "a second overlapping completion of the same already-rotated instance must be a no-op")
        let current = await store.current()
        XCTAssertEqual(current, alreadyRotated, "the store must still reflect only the FIRST caller's rotation, not a second one")
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
