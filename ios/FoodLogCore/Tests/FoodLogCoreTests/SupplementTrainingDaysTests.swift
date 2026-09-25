// SupplementTrainingDaysTests.swift
//
// add-supplements 2.4: training days come from the cached Garmin activities
// plus `race` day-note tags; standalone mode uses the tags only (spec
// "Training days without activity data"). Real ActivityCacheStore and
// DayNoteStore on unique temp files, no mocks.

import XCTest
@testable import FoodLogCore

final class SupplementTrainingDaysTests: XCTestCase {
    private func tempURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("training-days-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(name)
    }

    private func run(on day: String) -> ActivitySummary {
        ActivitySummary(id: UUID().uuidString, typeKey: "running", day: day, start: Date(timeIntervalSince1970: 1_790_000_000), durationS: 3600)
    }

    func testActivityDaysAndRaceTagsCountButEmptyOrUnreadDaysDont() {
        let activityDays = [
            DayActivity(day: "2026-09-20", activities: [run(on: "2026-09-20")]),
            DayActivity(day: "2026-09-21", activities: []),
            DayActivity(day: "2026-09-22", activeKcal: 500, activities: nil)
        ]
        let notes = [
            DayNote(day: "2026-09-23", text: "", tags: [.race]),
            DayNote(day: "2026-09-24", text: "party", tags: [])
        ]

        let days = SupplementTrainingDays.days(activityDays: activityDays, notes: notes, includeActivities: true)

        XCTAssertEqual(days, ["2026-09-20", "2026-09-23"])
    }

    // Spec: Training days without activity data.
    func testStandaloneUsesRaceTagsOnly() {
        let activityDays = [DayActivity(day: "2026-09-20", activities: [run(on: "2026-09-20")])]
        let notes = [DayNote(day: "2026-09-23", text: "", tags: [.race])]

        let days = SupplementTrainingDays.days(activityDays: activityDays, notes: notes, includeActivities: false)

        XCTAssertEqual(days, ["2026-09-23"])
    }

    func testLoadReadsBothStoresWithinTheRange() async throws {
        let directory = tempURL("x").deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let activityCache = ActivityCacheStore(fileURL: directory.appendingPathComponent("activity-cache.json"))
        let dayNotes = DayNoteStore(fileURL: directory.appendingPathComponent("day-notes.json"))
        try await activityCache.recordActivities(
            [run(on: "2026-08-31"), run(on: "2026-09-02")],
            coveringDays: ["2026-08-31", "2026-09-01", "2026-09-02"]
        )
        _ = try await dayNotes.save(day: "2026-09-05", text: "", tags: [.race])

        let garmin = await SupplementTrainingDays.load(from: "2026-09-01", to: "2026-09-30", activityCache: activityCache, dayNotes: dayNotes, mode: .garminConnected)
        XCTAssertEqual(garmin, ["2026-09-02", "2026-09-05"], "2026-08-31 is outside the range")

        let standalone = await SupplementTrainingDays.load(from: "2026-09-01", to: "2026-09-30", activityCache: activityCache, dayNotes: dayNotes, mode: .standalone)
        XCTAssertEqual(standalone, ["2026-09-05"])
    }

    func testATrainingDaysScheduleIsDueOnlyOnThoseDays() {
        let product = SupplementProduct(name: "Beta-alanine", ingredients: [IngredientAmount(ingredient: .betaAlanine, amount: 3.2, unit: .g)])
        var plan = SupplementPlan(products: [product])
        plan.setSchedule(SupplementSchedule(slots: [.preWorkout], pattern: .trainingDays), for: product.id, from: "2026-09-01")
        let training = SupplementTrainingDays.days(
            activityDays: [],
            notes: [DayNote(day: "2026-09-23", text: "", tags: [.race])],
            includeActivities: false
        )

        XCTAssertEqual(ScheduleEvaluator.due(on: "2026-09-23", plan: plan, trainingDays: training).map(\.productId), [product.id])
        XCTAssertTrue(ScheduleEvaluator.due(on: "2026-09-22", plan: plan, trainingDays: training).isEmpty)
    }
}
