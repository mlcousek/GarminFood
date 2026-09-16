// ServingDefaults.swift
//
// Per-food remembered serving choice (design.md D2, task 13.3): once a
// serving is picked for a food, remember it and pre-select it next time,
// while keeping it editable and updating the remembered choice whenever the
// user picks something else (food-catalog spec's "A food's serving choice
// is remembered as a default" requirement, both scenarios).

import Foundation

public struct ServingDefault: Codable, Sendable, Equatable {
    public let foodId: String
    public var servingId: String
    public var numberOfUnits: Double
    public var updatedAt: Date

    public init(foodId: String, servingId: String, numberOfUnits: Double, updatedAt: Date) {
        self.foodId = foodId
        self.servingId = servingId
        self.numberOfUnits = numberOfUnits
        self.updatedAt = updatedAt
    }
}

/// JSON-file-backed, actor-isolated -- same pattern as `UsageHistoryStore`.
public actor ServingDefaultStore {
    private let fileURL: URL
    private var defaultsByFoodId: [String: ServingDefault] = [:]
    private var loaded = false

    public init(fileURL: URL = ServingDefaultStore.defaultFileURL()) {
        self.fileURL = fileURL
    }

    public static func defaultFileURL() -> URL {
        FoodLogCoreStorage.directory().appendingPathComponent("serving-defaults.json")
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = (try? decoder.decode([ServingDefault].self, from: data)) ?? []
        defaultsByFoodId = Dictionary(uniqueKeysWithValues: decoded.map { ($0.foodId, $0) })
    }

    private func persist() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(Array(defaultsByFoodId.values))
        try data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: fileURL.path
        )
    }

    public func defaultServing(forFoodId foodId: String) -> ServingDefault? {
        loadIfNeeded()
        return defaultsByFoodId[foodId]
    }

    /// Sets (or overwrites) the remembered serving for a food. Called both
    /// on first log AND whenever the user picks something other than the
    /// current default (food-catalog spec's "Changing the remembered
    /// serving" scenario: "the new selection becomes the remembered default
    /// for that food going forward").
    public func setDefault(foodId: String, servingId: String, numberOfUnits: Double, updatedAt: Date = Date()) throws {
        loadIfNeeded()
        defaultsByFoodId[foodId] = ServingDefault(foodId: foodId, servingId: servingId, numberOfUnits: numberOfUnits, updatedAt: updatedAt)
        try persist()
    }

    public func all() -> [ServingDefault] {
        loadIfNeeded()
        return Array(defaultsByFoodId.values)
    }
}

public enum ServingResolution {
    /// Resolves a remembered default against a food's CURRENT servings.
    /// Pure and testable without any store at all.
    ///
    /// Returns `nil` when there is no remembered default, OR when the
    /// remembered `servingId` no longer exists among `food.servings` --
    /// design.md's named risk ("Garmin changes a servingId") requires
    /// treating that as "re-resolve from a fresh search" rather than
    /// crashing or silently picking something the user never chose; `nil`
    /// here is the caller's signal to fall back to prompting the serving
    /// picker instead of silently guessing.
    public static func resolve(_ remembered: ServingDefault?, in food: Food) -> Serving? {
        guard let remembered else { return nil }
        return food.servings.first { $0.id == remembered.servingId }
    }
}
