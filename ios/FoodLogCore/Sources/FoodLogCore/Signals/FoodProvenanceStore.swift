// FoodProvenanceStore.swift
//
// Remembers where a food CAME FROM when that is lost later (design D3):
// an Open Food Facts product's `Food.id` IS its barcode and carries the
// OFF brand, but once the owner matches it to a Garmin food or turns it
// into a custom food, the logged food id is Garmin's and the barcode is
// gone. The tagger needs both -- the barcode for the Czech-EAN (859)
// fallback, the brand for `czechBrand` and brand-based rules.
//
// Written by the app inside the EXISTING OFF match / custom-food-create
// flow, after the user's action, as a plain local JSON write -- never a
// network await (local-first). Read by `DaySignalsBuilder` (via
// `SignalsInput.provenance`) as the third source of an entry's
// name/brand/barcode, after the Garmin day-log digest and FoodCache.
//
// Capped at `maxFoods` (2,000), least-recently-recorded dropped first.
// Unreadable-file contract as every store here (fix-silent-store-wipe).

import Foundation

public struct FoodProvenance: Codable, Sendable, Equatable {
    public let foodId: String
    public var barcode: String?
    public var brand: String?
    public var recordedAt: Date?

    public init(foodId: String, barcode: String? = nil, brand: String? = nil, recordedAt: Date? = nil) {
        self.foodId = foodId
        self.barcode = barcode
        self.brand = brand
        self.recordedAt = recordedAt
    }
}

public actor FoodProvenanceStore {
    public static let maxFoods = 2_000

    private let fileURL: URL
    private var byFood: [String: FoodProvenance] = [:]
    private var loaded = false

    public init(fileURL: URL = FoodProvenanceStore.defaultFileURL()) {
        self.fileURL = fileURL
    }

    public static func defaultFileURL() -> URL {
        FoodLogCoreStorage.directory().appendingPathComponent("food-provenance.json")
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let result = FoodLogCoreStorage.loadPersistedJSON([FoodProvenance].self, from: fileURL, decoder: decoder, category: "FoodProvenanceStore")
        // Unreadable (e.g. before first unlock): retry on next access.
        loaded = !result.isUnreadable
        byFood = Dictionary((result.value ?? []).map { ($0.foodId, $0) }, uniquingKeysWith: { _, last in last })
    }

    private func persist() throws {
        try FoodLogCoreStorage.ensureSafeToWrite(loaded: loaded, fileURL: fileURL, category: "FoodProvenanceStore")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(byFood.values.sorted { $0.foodId < $1.foodId })
        try data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: fileURL.path
        )
    }

    /// Records (or merges into) `foodId`'s provenance. A `nil`/blank value
    /// never erases a known one. Nothing to record -> no write.
    public func record(foodId: String, barcode: String?, brand: String?, now: Date = Date()) throws {
        loadIfNeeded()
        let cleanBarcode = barcode?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanBrand = brand?.trimmingCharacters(in: .whitespacesAndNewlines)
        let newBarcode = (cleanBarcode?.isEmpty ?? true) ? nil : cleanBarcode
        let newBrand = (cleanBrand?.isEmpty ?? true) ? nil : cleanBrand
        guard !foodId.isEmpty, newBarcode != nil || newBrand != nil else { return }

        var entry = byFood[foodId] ?? FoodProvenance(foodId: foodId)
        let before = entry
        if let newBarcode { entry.barcode = newBarcode }
        if let newBrand { entry.brand = newBrand }
        guard entry.barcode != before.barcode || entry.brand != before.brand || byFood[foodId] == nil else { return }
        entry.recordedAt = now
        byFood[foodId] = entry

        if byFood.count > Self.maxFoods {
            let overflow = byFood.count - Self.maxFoods
            let oldest = byFood.values
                .sorted { ($0.recordedAt ?? .distantPast, $0.foodId) < ($1.recordedAt ?? .distantPast, $1.foodId) }
                .prefix(overflow)
                .map(\.foodId)
            for id in oldest { byFood.removeValue(forKey: id) }
        }
        try persist()
    }

    public func provenance(for foodId: String) -> FoodProvenance? {
        loadIfNeeded()
        return byFood[foodId]
    }

    /// Everything recorded, keyed by food id.
    public func all() -> [String: FoodProvenance] {
        loadIfNeeded()
        return byFood
    }
}
