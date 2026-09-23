// CustomFood.swift
//
// A custom food (design.md D4, food-catalog spec's "Custom foods use the
// same shape a logged entry requires" requirement) for items Garmin's
// FatSecret-backed database doesn't carry -- common for regional Czech
// products (proposal.md).
//
// `POST /nutrition-service/customFood` (docs/garmin-routes.json) is
// documented but genuinely unconfirmed -- "documented, not exercised" is
// the route file's own words. Per task 15.3 ("if not [possible], implement
// the best-fit-existing-food fallback... and surface the discrepancy"),
// this type implements ONLY the fallback path for now: a custom food is
// always backed, from the moment it's created, by an existing Garmin
// food+serving the user explicitly confirms is the closest real match, plus
// a quantity multiplier. That backing pair is what actually gets sent to
// `Outbox.logFood` (via `resolvedLoggingTarget(quantity:)`), which is what
// keeps a custom food fully loggable OFFLINE, at confirm time, with zero
// network wait -- matching the log-entry-flow spec's hard requirement even
// though "closest existing food" is normally a search (a network
// operation). The search happens once, at CREATION time, not at every log.
//
// Wiring up real custom-food creation later (once the write contract
// settles, per task 15.3) is additive: add a `garminCustomFoodId` field,
// prefer it in `resolvedLoggingTarget` when present, and drop the
// discrepancy note for those foods. Not built now because the request body
// for that route is unconfirmed and, per openspec/config.yaml's task rule,
// "no task writes to the Garmin account before the write contract is
// documented" — this route's write contract is not.

import Foundation

// `Hashable` for the same reason as `Food` (see Food.swift) -- so the app
// layer can navigate to a confirm screen keyed on either a `Food` or a
// `CustomFoodDraft` via a single `Hashable` enum, without a wrapper type.
public struct CustomFoodDraft: Codable, Sendable, Equatable, Hashable, Identifiable {
    /// The single implicit serving every custom food has today (one
    /// hand-entered unit/quantity/macro set, no serving picker needed).
    /// Shared with `LogEntryCoordinator` so usage-history/serving-default
    /// bookkeeping and `asFood()` always agree on the same identifier.
    public static let servingId = "custom"

    public let id: UUID
    public var name: String
    public var brandName: String?
    public var servingUnit: String
    public var numberOfUnits: Double
    public var calories: Double?
    public var carbs: Double?
    public var protein: Double?
    public var fat: Double?
    public var fiber: Double?
    public var sugar: Double?
    public var saturatedFat: Double?
    public var sodium: Double?
    public var createdAt: Date

    /// The closest existing Garmin food this custom food actually logs as
    /// (see file header). Required, not optional: without it there is
    /// nothing this project can hand to `Outbox` at all, since only foods
    /// Garmin recognises can be written back to it (design.md's own
    /// non-goal: "Building a second food database").
    public var backingFoodId: String
    public var backingFoodName: String
    public var backingServingId: String
    /// Multiplies the user's chosen quantity before it's sent as the
    /// backing serving's `numberOfUnits` -- e.g. this custom food's "1
    /// homemade dumpling" might be declared as backed by "0.5x" a Garmin
    /// serving of a similar packaged product.
    public var backingQuantityMultiplier: Double
    /// A free-text note -- e.g. a scanned-but-unresolved barcode (design.md
    /// D3's fallback path) -- shown alongside the food, not sent to Garmin.
    public var note: String?
    /// The backing food's own region/language as Garmin reported them when
    /// it was picked (`Food.regionCode`/`.languageCode`). Matters when the
    /// backing food is itself a Garmin custom food: its nutrition record is
    /// looked up by exactly this tuple at log time. Optional so drafts saved
    /// before these fields existed still decode (`nil` = fall back to the
    /// account's region/language).
    public var backingRegionCode: String?
    public var backingLanguageCode: String?

    public init(
        id: UUID = UUID(),
        name: String,
        brandName: String? = nil,
        servingUnit: String,
        numberOfUnits: Double,
        calories: Double? = nil,
        carbs: Double? = nil,
        protein: Double? = nil,
        fat: Double? = nil,
        fiber: Double? = nil,
        sugar: Double? = nil,
        saturatedFat: Double? = nil,
        sodium: Double? = nil,
        createdAt: Date = Date(),
        backingFoodId: String,
        backingFoodName: String,
        backingServingId: String,
        backingQuantityMultiplier: Double = 1,
        note: String? = nil,
        backingRegionCode: String? = nil,
        backingLanguageCode: String? = nil
    ) {
        self.id = id
        self.name = name
        self.brandName = brandName
        self.servingUnit = servingUnit
        self.numberOfUnits = numberOfUnits
        self.calories = calories
        self.carbs = carbs
        self.protein = protein
        self.fat = fat
        self.fiber = fiber
        self.sugar = sugar
        self.saturatedFat = saturatedFat
        self.sodium = sodium
        self.createdAt = createdAt
        self.backingFoodId = backingFoodId
        self.backingFoodName = backingFoodName
        self.backingServingId = backingServingId
        self.backingQuantityMultiplier = backingQuantityMultiplier
        self.note = note
        self.backingRegionCode = backingRegionCode
        self.backingLanguageCode = backingLanguageCode
    }

    /// This custom food as a `Food`/`Serving` pair -- so the log-entry flow,
    /// quick-pick cache, and every view treat it exactly like a searched
    /// food (design.md D4's literal requirement).
    public func asFood() -> Food {
        Food(
            id: id.uuidString,
            name: name,
            brandName: brandName,
            source: .custom,
            servings: [
                Serving(
                    id: Self.servingId,
                    unit: servingUnit,
                    numberOfUnits: numberOfUnits,
                    calories: calories,
                    carbs: carbs,
                    protein: protein,
                    fat: fat,
                    fiber: fiber,
                    sugar: sugar,
                    saturatedFat: saturatedFat,
                    sodium: sodium
                )
            ]
        )
    }

    /// What actually gets sent to `Outbox.logFood` for a given user-chosen
    /// quantity (in units of THIS custom food's own declared serving) --
    /// pure, no network access, so the log-entry flow's zero-network-wait
    /// requirement holds even for a custom food.
    public func resolvedLoggingTarget(quantity: Double) -> (foodId: String, servingId: String, numberOfUnits: Double) {
        (backingFoodId, backingServingId, backingQuantityMultiplier * quantity)
    }

    /// Shown to the user per the food-catalog spec's "the discrepancy...
    /// is shown to the user" requirement -- never hidden.
    public var discrepancyNote: String {
        "Recorded in Garmin as \"\(backingFoodName)\" (closest match; custom-food creation isn't confirmed possible via Garmin's API yet)."
    }
}

/// JSON-file-backed, actor-isolated -- same pattern as the other stores in
/// this package.
public actor CustomFoodStore {
    private let fileURL: URL
    private var foodsById: [UUID: CustomFoodDraft] = [:]
    private var loaded = false

    public init(fileURL: URL = CustomFoodStore.defaultFileURL()) {
        self.fileURL = fileURL
    }

    public static func defaultFileURL() -> URL {
        FoodLogCoreStorage.directory().appendingPathComponent("custom-foods.json")
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = FoodLogCoreStorage.loadPersistedJSON([CustomFoodDraft].self, from: fileURL, decoder: decoder, category: "CustomFoodStore") ?? []
        foodsById = Dictionary(decoded.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
    }

    private func persist() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(Array(foodsById.values))
        try data.write(to: fileURL, options: .atomic)
    }

    public func all() -> [CustomFoodDraft] {
        loadIfNeeded()
        return Array(foodsById.values).sorted { $0.createdAt > $1.createdAt }
    }

    @discardableResult
    public func upsert(_ food: CustomFoodDraft) throws -> CustomFoodDraft {
        loadIfNeeded()
        foodsById[food.id] = food
        try persist()
        return food
    }

    public func delete(id: UUID) throws {
        loadIfNeeded()
        foodsById.removeValue(forKey: id)
        try persist()
    }
}
