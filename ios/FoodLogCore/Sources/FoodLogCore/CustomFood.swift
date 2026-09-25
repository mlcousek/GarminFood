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
//
// add-standalone-mode D5 (task 3.3): the backing food is OPTIONAL. A
// standalone user has no Garmin to back anything with -- her custom food is
// logged as itself, with its own macros (`LocalLogEntryCoordinator`). The
// three backing fields are Optional Codable, so every file written before
// this change (which always has them) decodes exactly as before, and a new
// food simply omits them. A backing-less food seen in Garmin mode (after a
// mode switch) is never logged silently or dropped: `resolvedLoggingTarget`
// is nil, `LogEntryCoordinator` throws `CustomFoodLoggingError.
// needsGarminMatch` before writing anything, and the confirm screen offers
// the backing picker. `barcode` (optional, standalone's editor) lets a
// scanned product the databases don't know be found again by its code.

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
    /// in Garmin mode (see file header). Without it there is nothing this
    /// project can hand to `Outbox`, since only foods Garmin recognises can
    /// be written back to it -- so Garmin mode requires one before logging.
    /// `nil` for a food created in standalone mode (add-standalone-mode D5).
    public var backingFoodId: String?
    public var backingFoodName: String?
    public var backingServingId: String?
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
    /// The product barcode, when this food was created from a scan nobody
    /// knew (standalone barcode chain, add-standalone-mode 3.5). `nil` for
    /// every food created before it existed.
    public var barcode: String?

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
        backingFoodId: String? = nil,
        backingFoodName: String? = nil,
        backingServingId: String? = nil,
        backingQuantityMultiplier: Double = 1,
        note: String? = nil,
        backingRegionCode: String? = nil,
        backingLanguageCode: String? = nil,
        barcode: String? = nil
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
        self.barcode = barcode
    }

    /// Whether this food can be logged to Garmin (it has a backing food
    /// and serving). Always true for a food created in Garmin mode.
    public var hasGarminBacking: Bool {
        guard let backingFoodId, let backingServingId else { return false }
        return !backingFoodId.isEmpty && !backingServingId.isEmpty
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
    /// requirement holds even for a custom food. `nil` when there is no
    /// backing food (`hasGarminBacking == false`): nothing can be sent.
    public func resolvedLoggingTarget(quantity: Double) -> (foodId: String, servingId: String, numberOfUnits: Double)? {
        guard hasGarminBacking, let backingFoodId, let backingServingId else { return nil }
        return (backingFoodId, backingServingId, backingQuantityMultiplier * quantity)
    }

    /// Shown to the user per the food-catalog spec's "the discrepancy...
    /// is shown to the user" requirement -- never hidden.
    /// Empty when there is no backing food (nothing is recorded in Garmin).
    public var discrepancyNote: String {
        guard hasGarminBacking, let backingFoodName else { return "" }
        return String(
            localized: "Recorded in Garmin as \"\(backingFoodName)\" (closest match; custom-food creation isn't confirmed possible via Garmin's API yet).",
            bundle: .module,
            comment: "Note under a custom food. %@ is the name of the Garmin food it is actually logged as."
        )
    }
}

/// Thrown by the Garmin `LogEntryCoordinator` for a custom food without a
/// backing food (add-standalone-mode D5) -- before anything is written.
public enum CustomFoodLoggingError: Error, Sendable, Equatable, LocalizedError {
    case needsGarminMatch

    public var errorDescription: String? {
        String(
            localized: "Needs a Garmin match before it can be logged to Garmin.",
            bundle: .module,
            comment: "A custom food created without Garmin (standalone mode) can't be logged to Garmin until a closest Garmin food is picked."
        )
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
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let result = FoodLogCoreStorage.loadPersistedJSON([CustomFoodDraft].self, from: fileURL, decoder: decoder, category: "CustomFoodStore")
        // Unreadable (e.g. before first unlock): retry on next access.
        loaded = !result.isUnreadable
        let decoded = result.value ?? []
        foodsById = Dictionary(decoded.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
    }

    private func persist() throws {
        try FoodLogCoreStorage.ensureSafeToWrite(loaded: loaded, fileURL: fileURL, category: "CustomFoodStore")
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
