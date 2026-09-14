// Food.swift
//
// Domain models the rest of this package and the app's UI layer operate on
// -- `Food` and `Serving` (tasks 12.2), separate from GarminKit's wire-format
// DTOs (`FoodSearchResult` / `NutritionContent` in GarminModels.swift). Two
// reasons for the extra layer rather than using GarminKit's types directly:
//
//   1. A custom food (Custom.swift) and a Garmin search result both need to
//      become the same shape so the log-entry flow treats them identically
//      (design.md D4) -- neither is naturally a `FoodSearchResult`.
//   2. Keeps GarminKit's types purely about the wire contract (per its own
//      header comment) and this package's types about what the app actually
//      displays and logs, so a future Garmin field rename only touches the
//      adapter (`Food.init(searchResult:)`) below, not every view.
//
// `imageURL` exists because task 12.2 names "images" as a `Food` field, but
// docs/garmin-routes.json's confirmed `foodSearch` response shape (2026-09-14)
// does not include one -- FatSecret-backed results here carry no image data
// today. Kept as an always-nil optional for forward compatibility rather
// than dropped, since removing it now and re-adding it later would be a
// breaking change to every call site; every call site MUST treat it as
// possibly nil already, so there is no false expectation being set. If a
// future Garmin response shape adds one, only the adapter below changes.

import Foundation
import GarminKit

public enum FoodSource: String, Codable, Sendable, Equatable {
    case garmin = "GARMIN"
    case fatSecret = "FATSECRET"
    case custom = "CUSTOM"

    /// Maps GarminKit's free-form `FoodMetaData.source` string (only
    /// "GARMIN" | "FATSECRET" confirmed live) to this closed set, falling
    /// back to `.garmin` for anything unrecognised rather than failing the
    /// whole decode -- an unknown source string is cosmetic, not a reason to
    /// lose an otherwise-loggable food.
    public init(garminSourceString: String?) {
        switch garminSourceString?.uppercased() {
        case "FATSECRET": self = .fatSecret
        default: self = .garmin
        }
    }
}

/// One servable quantity of a `Food`, with its full macro/micro breakdown.
/// Mirrors `GarminKit.NutritionContent` field-for-field (task 12.2's "full
/// macro/micro breakdown") but as a value this package owns, so a custom
/// food's hand-entered serving can be represented identically (design.md D4).
public struct Serving: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let unit: String
    public let numberOfUnits: Double
    public let calories: Double?
    public let carbs: Double?
    public let protein: Double?
    public let fat: Double?
    public let fiber: Double?
    public let sugar: Double?
    public let saturatedFat: Double?
    public let monounsaturatedFat: Double?
    public let polyunsaturatedFat: Double?
    public let cholesterol: Double?
    public let sodium: Double?
    public let potassium: Double?
    public let vitaminA: Double?
    public let vitaminC: Double?
    public let calcium: Double?
    public let iron: Double?

    public init(
        id: String,
        unit: String,
        numberOfUnits: Double,
        calories: Double? = nil,
        carbs: Double? = nil,
        protein: Double? = nil,
        fat: Double? = nil,
        fiber: Double? = nil,
        sugar: Double? = nil,
        saturatedFat: Double? = nil,
        monounsaturatedFat: Double? = nil,
        polyunsaturatedFat: Double? = nil,
        cholesterol: Double? = nil,
        sodium: Double? = nil,
        potassium: Double? = nil,
        vitaminA: Double? = nil,
        vitaminC: Double? = nil,
        calcium: Double? = nil,
        iron: Double? = nil
    ) {
        self.id = id
        self.unit = unit
        self.numberOfUnits = numberOfUnits
        self.calories = calories
        self.carbs = carbs
        self.protein = protein
        self.fat = fat
        self.fiber = fiber
        self.sugar = sugar
        self.saturatedFat = saturatedFat
        self.monounsaturatedFat = monounsaturatedFat
        self.polyunsaturatedFat = polyunsaturatedFat
        self.cholesterol = cholesterol
        self.sodium = sodium
        self.potassium = potassium
        self.vitaminA = vitaminA
        self.vitaminC = vitaminC
        self.calcium = calcium
        self.iron = iron
    }

    /// A short human-readable label, e.g. "100 g" or "1 medium". Falls back
    /// to just the unit if `numberOfUnits` is 1 and the unit already reads
    /// naturally (Garmin's `servingUnit` sometimes already contains a count,
    /// e.g. "100g").
    public var displayLabel: String {
        let trimmedUnit = unit.trimmingCharacters(in: .whitespaces)
        guard !trimmedUnit.isEmpty else { return Self.formattedQuantity(numberOfUnits) }
        if numberOfUnits == 1 { return trimmedUnit }
        return "\(Self.formattedQuantity(numberOfUnits)) \(trimmedUnit)"
    }

    private static func formattedQuantity(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(format: "%.1f", value)
    }

    init?(nutritionContent: NutritionContent) {
        guard let id = nutritionContent.servingId else { return nil }
        self.init(
            id: id,
            unit: nutritionContent.servingUnit ?? "serving",
            numberOfUnits: nutritionContent.numberOfUnits ?? 1,
            calories: nutritionContent.calories,
            carbs: nutritionContent.carbs,
            protein: nutritionContent.protein,
            fat: nutritionContent.fat,
            fiber: nutritionContent.fiber,
            sugar: nutritionContent.sugar,
            saturatedFat: nutritionContent.saturatedFat,
            monounsaturatedFat: nutritionContent.monounsaturatedFat,
            polyunsaturatedFat: nutritionContent.polyunsaturatedFat,
            cholesterol: nutritionContent.cholesterol,
            sodium: nutritionContent.sodium,
            potassium: nutritionContent.potassium,
            vitaminA: nutritionContent.vitaminA,
            vitaminC: nutritionContent.vitaminC,
            calcium: nutritionContent.calcium,
            iron: nutritionContent.iron
        )
    }
}

/// A loggable food -- either a real Garmin/FatSecret catalog entry or a
/// locally-created custom food (`source == .custom`), both represented
/// identically per design.md D4 so the rest of the app doesn't need to
/// special-case which kind it's showing.
public struct Food: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let brandName: String?
    public let source: FoodSource
    public let servings: [Serving]
    /// Always `nil` today -- see this file's header comment.
    public let imageURL: String?
    /// Garmin's own per-search-result flags (`isFavorite`/`isRecent`).
    /// `nil` for a custom food, or when unknown. These reflect Garmin's own
    /// account state, NOT this project's local usage ranking (design.md
    /// D1) -- surfaced only as a secondary badge in the UI, never used for
    /// the quick-pick ranking itself.
    public let garminIsFavorite: Bool?
    public let garminIsRecent: Bool?

    public init(
        id: String,
        name: String,
        brandName: String? = nil,
        source: FoodSource,
        servings: [Serving],
        imageURL: String? = nil,
        garminIsFavorite: Bool? = nil,
        garminIsRecent: Bool? = nil
    ) {
        self.id = id
        self.name = name
        self.brandName = brandName
        self.source = source
        self.servings = servings
        self.imageURL = imageURL
        self.garminIsFavorite = garminIsFavorite
        self.garminIsRecent = garminIsRecent
    }

    /// Adapts a `GarminKit.FoodSearchResult` (the confirmed-live
    /// `food/search` response shape) into this package's domain model.
    /// Fails only when Garmin's own required identifier is unusable or the
    /// result carries zero servings -- an unloggable "food" with no serving
    /// to attach a quantity to isn't useful to show at all.
    public init?(searchResult: FoodSearchResult) {
        let servings = (searchResult.nutritionContents ?? []).compactMap(Serving.init(nutritionContent:))
        guard !servings.isEmpty else { return nil }
        let meta = searchResult.foodMetaData
        guard !meta.foodId.isEmpty else { return nil }

        self.init(
            id: meta.foodId,
            name: meta.foodName ?? "Unnamed food",
            brandName: meta.brandName,
            source: FoodSource(garminSourceString: meta.source),
            servings: servings,
            imageURL: nil,
            garminIsFavorite: searchResult.isFavorite,
            garminIsRecent: searchResult.isRecent
        )
    }
}
