// SupplementStoresTests.swift
//
// add-supplements 2.1: the three supplement stores. What matters: data
// survives a relaunch (a fresh actor on the same file), planned ticks are
// idempotent per (day, product, slot) -- the reminder's "Taken" action may
// arrive twice --, only today and the last 365 days are writable, and a
// file this build can't use is quarantined or refused, never silently
// wiped. Real stores on unique temp paths (LogEntryCoordinatorTests'
// pattern), no mocks.

import XCTest
@testable import FoodLogCore
import GarminKit

final class SupplementStoresTests: XCTestCase {
    private let takenAt = Date(timeIntervalSince1970: 1_790_000_000)
    private let today = "2026-09-25"

    private func makeDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("supplements-\(UUID().uuidString)", isDirectory: true)
    }

    private func creatine() -> SupplementProduct {
        SupplementProduct(name: "Creatine", form: .powder, ingredients: [IngredientAmount(ingredient: .creatine, amount: 5, unit: .g)], packServings: 100)
    }

    // MARK: - SupplementPlanStore

    func testPlanSurvivesARelaunch() async throws {
        let url = makeDirectory().appendingPathComponent("supplement-plan.json")
        let product = creatine()
        let store = SupplementPlanStore(fileURL: url)
        try await store.upsertProduct(product)
        try await store.setSchedule(SupplementSchedule(slots: [.morning]), for: product.id, from: "2026-09-01")
        try await store.setSchedule(SupplementSchedule(slots: [.evening], pattern: .weekdays([2])), for: product.id, from: "2026-09-20")

        let reloaded = try await SupplementPlanStore(fileURL: url).plan()

        XCTAssertEqual(reloaded.products, [product])
        XCTAssertEqual(reloaded.schedule(of: product.id, on: "2026-09-10")?.slots, [.morning])
        XCTAssertEqual(reloaded.schedule(of: product.id, on: "2026-09-21")?.pattern, .weekdays([2]))
    }

    func testRemovingFromTheStackKeepsTheProductAndDeleteRemovesIt() async throws {
        let url = makeDirectory().appendingPathComponent("supplement-plan.json")
        let product = creatine()
        let store = SupplementPlanStore(fileURL: url)
        try await store.upsertProduct(product)
        try await store.setSchedule(SupplementSchedule(slots: [.morning]), for: product.id, from: "2026-09-01")

        try await store.removeFromStack(product.id, from: "2026-09-25")
        var plan = try await SupplementPlanStore(fileURL: url).plan()
        XCTAssertEqual(plan.products.map(\.id), [product.id])
        XCTAssertNil(plan.schedule(of: product.id, on: "2026-09-25"))
        XCTAssertNotNil(plan.schedule(of: product.id, on: "2026-09-24"), "history is kept")

        try await store.deleteProduct(product.id)
        plan = try await SupplementPlanStore(fileURL: url).plan()
        XCTAssertTrue(plan.products.isEmpty)
        XCTAssertTrue(plan.items.isEmpty)
    }

    func testStockAndRestockMarkPersist() async throws {
        let url = makeDirectory().appendingPathComponent("supplement-plan.json")
        let product = creatine()
        let store = SupplementPlanStore(fileURL: url)
        try await store.upsertProduct(product)
        let tick = IntakeRecord(day: "2026-09-25", productId: product.id, slot: .morning, servings: 1, takenAt: takenAt, kind: .planned)

        try await store.setStock(of: product.id, servingsOnHand: 40, on: "2026-09-25", records: [tick])
        try await store.markRestockReminded(product.id)
        var stored = try XCTUnwrap(try await SupplementPlanStore(fileURL: url).plan().product(id: product.id))
        XCTAssertEqual(StockProjection.remainingServings(of: stored, records: [tick]), 40)
        XCTAssertEqual(stored.restockRemindedFor, "2026-09-25")

        try await store.refill(product.id, on: "2026-09-26", records: [tick])
        stored = try XCTUnwrap(try await SupplementPlanStore(fileURL: url).plan().product(id: product.id))
        XCTAssertEqual(StockProjection.remainingServings(of: stored, records: [tick]), 140)
        XCTAssertTrue(StockProjection.shouldRemindRestock(stored, daysLeft: 1), "a refill re-arms the reminder")
    }

    func testAnUndecodablePlanIsQuarantinedNotWiped() async throws {
        let directory = makeDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("supplement-plan.json")
        let garbage = Data("not json at all".utf8)
        try garbage.write(to: url)
        let store = SupplementPlanStore(fileURL: url)

        let plan = try await store.plan()
        XCTAssertTrue(plan.products.isEmpty)

        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        let quarantined = try XCTUnwrap(files.first { $0.hasPrefix("supplement-plan.unreadable-") })
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent(quarantined)), garbage)

        let product = creatine()
        try await store.upsertProduct(product)
        let reloaded = try await SupplementPlanStore(fileURL: url).plan()
        XCTAssertEqual(reloaded.products, [product])
    }

    func testAPlanThatCantBeReadRefusesReadsAndSaves() async throws {
        let url = makeDirectory().appendingPathComponent("supplement-plan.json", isDirectory: true)
        // A directory where the file should be: it exists but can't be read
        // as a file, like a file locked before first unlock.
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let store = SupplementPlanStore(fileURL: url)

        do {
            _ = try await store.plan()
            XCTFail("an unread plan must not read as an empty stack")
        } catch {
            XCTAssertTrue(error is PersistedJSONUnreadFileError)
        }
        do {
            try await store.upsertProduct(creatine())
            XCTFail("an unread plan must not be overwritten")
        } catch {
            XCTAssertTrue(error is PersistedJSONUnreadFileError)
        }
    }

    func testAnOlderMinimalPlanFileDecodes() async throws {
        let directory = makeDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("supplement-plan.json")
        let id = UUID()
        try Data("{\"products\":[{\"id\":\"\(id.uuidString)\",\"name\":\"Zinc\"}]}".utf8).write(to: url)

        let plan = try await SupplementPlanStore(fileURL: url).plan()

        XCTAssertEqual(plan.products.first?.id, id)
        XCTAssertEqual(plan.products.first?.ingredients, [])
        XCTAssertTrue(plan.items.isEmpty)
    }

    // MARK: - SupplementIntakeStore

    // Spec: Take all / Double tap.
    func testPlannedTicksAreIdempotentPerDayProductAndSlot() async throws {
        let directory = makeDirectory()
        let store = SupplementIntakeStore(directoryURL: directory)
        let creatineId = UUID(), vitaminDId = UUID(), omegaId = UUID()
        let morning = [
            DueItem(productId: creatineId, slot: .morning, servings: 1),
            DueItem(productId: vitaminDId, slot: .morning, servings: 1),
            DueItem(productId: omegaId, slot: .morning, servings: 2)
        ]

        let single = try await store.recordPlanned([morning[0]], on: today, takenAt: takenAt, today: today)
        let takeAll = try await store.recordPlanned(morning, on: today, takenAt: takenAt.addingTimeInterval(60), today: today)
        let takenAgain = try await store.recordPlanned(morning, on: today, takenAt: takenAt.addingTimeInterval(120), today: today)

        XCTAssertEqual(takeAll.first, single.first, "the earlier tick is kept, not duplicated")
        XCTAssertEqual(takenAgain, takeAll)
        let stored = try await SupplementIntakeStore(directoryURL: directory).records(forDay: today)
        XCTAssertEqual(stored.count, 3)
        XCTAssertEqual(Set(stored.compactMap(\.plannedKey)).count, 3)
        XCTAssertTrue(stored.allSatisfy { $0.recordedOn == today })
        XCTAssertEqual(stored.first { $0.productId == omegaId }?.servings, 2)

        // The same product in another slot is another item.
        try await store.recordPlanned([DueItem(productId: creatineId, slot: .evening, servings: 1)], on: today, takenAt: takenAt, today: today)
        let afterEvening = try await store.records(forDay: today)
        XCTAssertEqual(afterEvening.count, 4)
    }

    func testUntickExtrasAndRemove() async throws {
        let directory = makeDirectory()
        let store = SupplementIntakeStore(directoryURL: directory)
        let productId = UUID()
        try await store.recordPlanned([DueItem(productId: productId, slot: .evening, servings: 1)], on: today, takenAt: takenAt, today: today)
        let extra = try await store.addExtra(productId: productId, servings: 1, on: today, takenAt: takenAt, today: today)

        try await store.removePlanned(productId: productId, slot: .evening, on: today, today: today)
        var records = try await SupplementIntakeStore(directoryURL: directory).records(forDay: today)
        XCTAssertEqual(records, [extra], "unticking leaves the extra")
        XCTAssertEqual(records.first?.kind, .extra)
        XCTAssertNil(records.first?.slot)

        try await store.remove(id: extra.id, on: today, today: today)
        records = try await SupplementIntakeStore(directoryURL: directory).records(forDay: today)
        XCTAssertTrue(records.isEmpty)
    }

    // Spec: Fix yesterday / Backfill a month ago / Too far back.
    func testOnlyTodayAndTheLast365DaysAreWritable() async throws {
        let store = SupplementIntakeStore(directoryURL: makeDirectory())
        let item = DueItem(productId: UUID(), slot: .morning, servings: 1)

        try await store.recordPlanned([item], on: "2026-09-24", takenAt: takenAt, today: today)
        try await store.recordPlanned([item], on: "2026-08-25", takenAt: takenAt, today: today)
        try await store.recordPlanned([item], on: "2025-09-25", takenAt: takenAt, today: today)
        for day in ["2025-09-24", "2026-09-26", "not-a-day"] {
            do {
                try await store.recordPlanned([item], on: day, takenAt: takenAt, today: today)
                XCTFail("\(day) must be refused")
            } catch {
                XCTAssertEqual(error as? SupplementStoreError, .dayNotEditable(day))
            }
        }
        do {
            _ = try await store.addExtra(productId: item.productId, servings: 1, on: "2026-10-01", takenAt: takenAt, today: today)
            XCTFail("a future extra must be refused")
        } catch {
            XCTAssertEqual(error as? SupplementStoreError, .dayNotEditable("2026-10-01"))
        }

        let backfilled = try await store.records(forDay: "2026-08-25")
        XCTAssertEqual(backfilled.first?.recordedOn, today)
        XCTAssertFalse(PastDayLogging.grantsXP(try XCTUnwrap(backfilled.first)), "a month late: history, no XP")
    }

    func testMonthsAreShardedAndRangesCrossThem() async throws {
        let directory = makeDirectory()
        let store = SupplementIntakeStore(directoryURL: directory)
        let productId = UUID()
        for day in ["2025-12-31", "2026-01-01", "2026-09-25"] {
            _ = try await store.addExtra(productId: productId, servings: 1, on: day, takenAt: takenAt, today: today)
        }

        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        XCTAssertEqual(files, ["2025-12.json", "2026-01.json", "2026-09.json"])
        let range = try await SupplementIntakeStore(directoryURL: directory).records(fromDay: "2025-12-15", toDay: "2026-01-31")
        XCTAssertEqual(range.map(\.day), ["2025-12-31", "2026-01-01"])
    }

    func testAnUndecodableMonthIsQuarantinedAndAnUnreadableOneRefused() async throws {
        let directory = makeDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let garbage = Data("[{\"broken\":".utf8)
        try garbage.write(to: directory.appendingPathComponent("2026-09.json"))
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("2026-08.json", isDirectory: true), withIntermediateDirectories: true)
        let store = SupplementIntakeStore(directoryURL: directory)

        let september = try await store.records(forDay: today)
        XCTAssertTrue(september.isEmpty)
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(files.filter { $0.hasPrefix("2026-09.unreadable-") }.count, 1)

        do {
            _ = try await store.records(forDay: "2026-08-25")
            XCTFail("an unread month must not read as empty")
        } catch {
            XCTAssertTrue(error is PersistedJSONUnreadFileError)
        }
        do {
            try await store.recordPlanned([DueItem(productId: UUID(), slot: .morning, servings: 1)], on: "2026-08-25", takenAt: takenAt, today: today)
            XCTFail("an unread month must not be overwritten")
        } catch {
            XCTAssertTrue(error is PersistedJSONUnreadFileError)
        }
    }

    func testAnOlderMinimalIntakeFileDecodes() async throws {
        let directory = makeDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let productId = UUID()
        let json = """
        [{ "id": "\(UUID().uuidString)", "day": "2026-09-25", "productId": "\(productId.uuidString)", "slot": { "kind": "morning" }, "moodEmoji": "💊" }]
        """
        try Data(json.utf8).write(to: directory.appendingPathComponent("2026-09.json"))
        let store = SupplementIntakeStore(directoryURL: directory)

        let records = try await store.records(forDay: today)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.kind, .planned)
        XCTAssertEqual(records.first?.servings, 1)

        // Its key still makes a later tick of the same item a no-op.
        try await store.recordPlanned([DueItem(productId: productId, slot: .morning, servings: 1)], on: today, takenAt: takenAt, today: today)
        let after = try await store.records(forDay: today)
        XCTAssertEqual(after.count, 1)
    }

    // MARK: - SupplementLimitsStore

    func testLimitOverridesPersistAndReset() async throws {
        let url = makeDirectory().appendingPathComponent("supplement-limits.json")
        let store = SupplementLimitsStore(fileURL: url)
        try await store.setOverride(LimitOverride(ingredient: .magnesium, upperLimit: 500))
        try await store.setOverride(LimitOverride(ingredient: .sodium, target: 3000, upperLimit: 6000))

        var overrides = try await SupplementLimitsStore(fileURL: url).overrides()
        XCTAssertEqual(overrides[.magnesium]?.upperLimit, 500)
        XCTAssertEqual(SupplementLimits.effective(for: .magnesium, overrides: overrides).upperLimit, 500)

        try await store.reset(.magnesium)
        try await store.setOverride(LimitOverride(ingredient: .sodium))
        overrides = try await SupplementLimitsStore(fileURL: url).overrides()
        XCTAssertTrue(overrides.isEmpty, "an empty override is a reset")
        XCTAssertEqual(SupplementLimits.effective(for: .magnesium, overrides: overrides).upperLimit, 250)
    }

    func testUndecodableLimitsAreQuarantined() async throws {
        let directory = makeDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("supplement-limits.json")
        try Data("{\"not\":\"a list\"}".utf8).write(to: url)
        let store = SupplementLimitsStore(fileURL: url)

        let overrides = try await store.overrides()
        XCTAssertTrue(overrides.isEmpty)
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(files.filter { $0.hasPrefix("supplement-limits.unreadable-") }.count, 1)

        try await store.setOverride(LimitOverride(ingredient: .zinc, upperLimit: 40))
        let reloaded = try await SupplementLimitsStore(fileURL: url).overrides()
        XCTAssertEqual(reloaded[.zinc]?.upperLimit, 40)
    }
}
