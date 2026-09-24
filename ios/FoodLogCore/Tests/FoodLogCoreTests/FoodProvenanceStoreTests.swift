// FoodProvenanceStoreTests.swift
//
// add-gamification-signals 4.3: `FoodProvenanceStore` (foodId ->
// barcode/brand, design D3). Covers merge-never-erases, the 2,000-food cap
// (oldest recorded dropped first), disk round-trip and corrupt-file
// quarantine. Real store on a temp file, never mocked (project convention).

import XCTest
@testable import FoodLogCore

final class FoodProvenanceStoreTests: XCTestCase {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("provenance-\(UUID().uuidString).json")
    }

    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    func testRecordMergesAndBlankNeverErases() async throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = FoodProvenanceStore(fileURL: url)

        try await store.record(foodId: "g-1", barcode: "8594001234567", brand: nil, now: t0)
        try await store.record(foodId: "g-1", barcode: "  ", brand: "Madeta", now: t0.addingTimeInterval(60))

        let entry = await store.provenance(for: "g-1")
        XCTAssertEqual(entry?.barcode, "8594001234567")
        XCTAssertEqual(entry?.brand, "Madeta")
        XCTAssertEqual(entry?.recordedAt, t0.addingTimeInterval(60))
    }

    func testNothingToRecordWritesNothing() async throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = FoodProvenanceStore(fileURL: url)
        try await store.record(foodId: "g-1", barcode: nil, brand: "", now: t0)
        try await store.record(foodId: "", barcode: "123", brand: nil, now: t0)
        let all = await store.all()
        XCTAssertTrue(all.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testRoundTripsThroughDisk() async throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try await FoodProvenanceStore(fileURL: url).record(foodId: "g-2", barcode: "4000417025005", brand: "Ritter Sport", now: t0)
        let reloaded = await FoodProvenanceStore(fileURL: url).provenance(for: "g-2")
        XCTAssertEqual(reloaded, FoodProvenance(foodId: "g-2", barcode: "4000417025005", brand: "Ritter Sport", recordedAt: t0))
    }

    func testCapDropsOldestRecordedFirst() async throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = FoodProvenanceStore(fileURL: url)
        for index in 0..<(FoodProvenanceStore.maxFoods + 5) {
            try await store.record(
                foodId: "f-\(index)",
                barcode: "\(index)",
                brand: nil,
                now: t0.addingTimeInterval(Double(index))
            )
        }
        let all = await store.all()
        XCTAssertEqual(all.count, FoodProvenanceStore.maxFoods)
        XCTAssertNil(all["f-0"])
        XCTAssertNil(all["f-4"])
        XCTAssertNotNil(all["f-5"])
        XCTAssertNotNil(all["f-\(FoodProvenanceStore.maxFoods + 4)"])
    }

    func testUndecodableFileIsQuarantinedNotOverwritten() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("provenance-corrupt-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("food-provenance.json")
        let garbage = Data(#"{"not":"an array"}"#.utf8)
        try garbage.write(to: url)

        let store = FoodProvenanceStore(fileURL: url)
        let before = await store.all()
        XCTAssertTrue(before.isEmpty)
        try await store.record(foodId: "g-3", barcode: "859", brand: nil, now: t0)

        let quarantined = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("food-provenance.unreadable-") && $0.pathExtension == "json" }
        XCTAssertEqual(quarantined.count, 1)
        XCTAssertEqual(try quarantined.first.map { try Data(contentsOf: $0) }, garbage)
    }
}
