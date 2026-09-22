// MealPreset.swift
//
// A meal preset: a named, fixed group of foods (proposal.md's own stated
// non-goal for the original scope -- "Recipe or multi-ingredient meal
// building. A meal here is one or more independently-logged food entries
// sharing a meal type, not a composed recipe" -- reversed by explicit later
// request). The point is entirely in `LogEntryCoordinator.confirmMealPreset`:
// logging a preset enqueues one outbox entry PER ingredient, all sharing the
// same meal type/date/timestamp, in one action -- "create my own foods from
// multiple ingredients... I only log the meal."
//
// Deliberately NOT built as a single aggregated Garmin custom food (one
// food with summed macros). Two reasons:
//   1. `GarminClient.createCustomFood`'s request/response shape is still
//      documented-but-unconfirmed (see its own header) -- building a second,
//      bigger feature on top of an unconfirmed write contract compounds that
//      risk for no real benefit here.
//   2. Logging each ingredient separately means each one still shows up
//      individually in Garmin Connect's own food log (and in this app's own
//      per-ingredient usage history / quick-pick ranking, via reusing
//      `LogEntryCoordinator.confirm`/`confirmCustomFood` unchanged) -- exactly
//      what already works and is already verified, just invoked N times
//      instead of once.
//
// An ingredient is stored as a full `Food`/`Serving` snapshot at add-time
// (the same pattern `FoodCacheStore` already uses), not just an id -- so a
// preset stays fully loggable offline, at confirm time, with zero network
// wait, and survives that ingredient's own food being edited or removed
// elsewhere later. `customFoodDraft`, when set, carries the extra
// backing-food indirection a custom-food ingredient needs to log correctly
// (see CustomFood.swift's header) -- also snapshotted, for the same reason.

import Foundation

public struct MealPresetIngredient: Codable, Sendable, Equatable, Hashable, Identifiable {
    public let id: UUID
    public var food: Food
    public var serving: Serving
    /// The multiplier of `serving` this ingredient contributes to the
    /// preset -- same meaning as `numberOfUnits` everywhere else in this
    /// package (e.g. `LogEntryCoordinator.confirm`).
    public var quantity: Double
    /// Set only when `food` came from a custom food (design.md D4's
    /// fallback path) -- `food`/`serving` alone (via `CustomFoodDraft.
    /// asFood()`) are not enough to log correctly, since a custom food
    /// actually writes to Garmin as its BACKING food/serving, scaled by its
    /// own multiplier. `nil` for a real catalog/Open-Food-Facts-matched
    /// ingredient, which logs directly as `food`/`serving`.
    public var customFoodDraft: CustomFoodDraft?

    public init(
        id: UUID = UUID(),
        food: Food,
        serving: Serving,
        quantity: Double,
        customFoodDraft: CustomFoodDraft? = nil
    ) {
        self.id = id
        self.food = food
        self.serving = serving
        self.quantity = quantity
        self.customFoodDraft = customFoodDraft
    }

    public var calories: Double? { serving.calories.map { $0 * quantity } }
    public var carbs: Double? { serving.carbs.map { $0 * quantity } }
    public var protein: Double? { serving.protein.map { $0 * quantity } }
    public var fat: Double? { serving.fat.map { $0 * quantity } }
}

public struct MealPreset: Codable, Sendable, Equatable, Hashable, Identifiable {
    public struct Totals: Sendable, Equatable {
        public let calories: Double
        public let carbs: Double
        public let protein: Double
        public let fat: Double

        public init(calories: Double, carbs: Double, protein: Double, fat: Double) {
            self.calories = calories
            self.carbs = carbs
            self.protein = protein
            self.fat = fat
        }
    }

    public let id: UUID
    public var name: String
    public var ingredients: [MealPresetIngredient]
    public var note: String?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        ingredients: [MealPresetIngredient],
        note: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.ingredients = ingredients
        self.note = note
        self.createdAt = createdAt
    }

    /// The preset's nutrition, summed across every ingredient at its own
    /// preset quantity, then scaled by `servingsMultiplier` -- e.g. `0.5` to
    /// preview/log half the preset as composed (a smaller portion of the
    /// same recipe, not a different recipe).
    public func totals(servingsMultiplier: Double = 1) -> Totals {
        var calories = 0.0, carbs = 0.0, protein = 0.0, fat = 0.0
        for ingredient in ingredients {
            calories += ingredient.calories ?? 0
            carbs += ingredient.carbs ?? 0
            protein += ingredient.protein ?? 0
            fat += ingredient.fat ?? 0
        }
        return Totals(
            calories: calories * servingsMultiplier,
            carbs: carbs * servingsMultiplier,
            protein: protein * servingsMultiplier,
            fat: fat * servingsMultiplier
        )
    }
}

/// JSON-file-backed, actor-isolated -- same pattern as `CustomFoodStore`.
public actor MealPresetStore {
    private let fileURL: URL
    private var presetsById: [UUID: MealPreset] = [:]
    private var loaded = false

    public init(fileURL: URL = MealPresetStore.defaultFileURL()) {
        self.fileURL = fileURL
    }

    public static func defaultFileURL() -> URL {
        FoodLogCoreStorage.directory().appendingPathComponent("meal-presets.json")
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = (try? decoder.decode([MealPreset].self, from: data)) ?? []
        presetsById = Dictionary(uniqueKeysWithValues: decoded.map { ($0.id, $0) })
    }

    private func persist() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(Array(presetsById.values))
        try data.write(to: fileURL, options: .atomic)
    }

    public func all() -> [MealPreset] {
        loadIfNeeded()
        return Array(presetsById.values).sorted { $0.createdAt > $1.createdAt }
    }

    @discardableResult
    public func upsert(_ preset: MealPreset) throws -> MealPreset {
        loadIfNeeded()
        presetsById[preset.id] = preset
        try persist()
        return preset
    }

    public func delete(id: UUID) throws {
        loadIfNeeded()
        presetsById.removeValue(forKey: id)
        try persist()
    }
}
