// SupplementLimitsStore.swift
//
// The user's own targets and upper limits per ingredient
// (add-supplements D6, task 2.1) -- e.g. an endurance athlete raising the
// magnesium or sodium limit. Only overrides are stored; the defaults live
// in `EvidenceCatalog`, so "Reset to default" simply deletes the override
// and a corrected default in a later build reaches everyone who never
// changed it.
//
// One small JSON file (`supplement-limits.json`), actor-isolated, with the
// package's store contract (SupplementStoreSupport.swift's header).
//
// Depended on by: AppServices, the limit editor and totals view (wave 3).
// Tests: SupplementStoresTests.

import Foundation
import GarminKit

public actor SupplementLimitsStore {
    private let fileURL: URL
    private var overridesByIngredient: SupplementLimits.Overrides = [:]
    private var loaded = false

    public init(fileURL: URL = SupplementLimitsStore.defaultFileURL()) {
        self.fileURL = fileURL
    }

    public static func defaultFileURL() -> URL {
        FoodLogCoreStorage.directory().appendingPathComponent("supplement-limits.json")
    }

    /// Every override. Throws when the file exists but can't be read yet.
    public func overrides() throws -> SupplementLimits.Overrides {
        loadIfNeeded()
        guard loaded else { throw PersistedJSONUnreadFileError(fileName: fileURL.lastPathComponent) }
        return overridesByIngredient
    }

    /// Stores `override`; an empty one (no target, no limit) is a reset.
    public func setOverride(_ override: LimitOverride) throws {
        loadIfNeeded()
        try FoodLogCoreStorage.ensureSafeToWrite(loaded: loaded, fileURL: fileURL, category: "SupplementLimitsStore")
        var next = overridesByIngredient
        if override.isEmpty {
            next.removeValue(forKey: override.ingredient)
        } else {
            next[override.ingredient] = override
        }
        guard next != overridesByIngredient else { return }
        try save(next)
    }

    /// "Reset to default" (design D6).
    public func reset(_ ingredient: IngredientID) throws {
        try setOverride(LimitOverride(ingredient: ingredient))
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        let result = FoodLogCoreStorage.loadPersistedJSON([LimitOverride].self, from: fileURL, decoder: JSONDecoder(), category: "SupplementLimitsStore")
        overridesByIngredient = Dictionary(
            (result.value ?? []).filter { !$0.isEmpty }.map { ($0.ingredient, $0) },
            uniquingKeysWith: { _, last in last }
        )
        // Unreadable (e.g. before first unlock): retry on next access.
        loaded = !result.isUnreadable
    }

    private func save(_ next: SupplementLimits.Overrides) throws {
        let list = next.values.sorted { $0.ingredient < $1.ingredient }
        try SupplementStoreIO.write(list, to: fileURL, category: "SupplementLimitsStore")
        overridesByIngredient = next
    }
}
