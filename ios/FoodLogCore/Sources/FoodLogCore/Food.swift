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

public enum FoodSource: String, Codable, Sendable, Equatable, Hashable {
    case garmin = "GARMIN"
    case fatSecret = "FATSECRET"
    case custom = "CUSTOM"
    /// A result from Open Food Facts (add-czech-food-catalog) -- never
    /// produced by `init(garminSourceString:)` below, since Garmin itself
    /// never reports this as a food's source. Set explicitly by
    /// `OpenFoodFactsClient`'s own adapter when it builds a `Food` from an
    /// OFF product. Kept as its own case (not folded into `.custom`) so the
    /// catalog UI and matching flow can tell "a Czech-database result that
    /// still needs matching/creation in Garmin" apart from "a locally
    /// hand-entered food already backed by a real Garmin food" -- the two
    /// have different logging paths (garmin-food-matching spec vs
    /// design.md D4's existing custom-food fallback).
    case openFoodFacts = "OPENFOODFACTS"

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
///
/// 2026-09-22 (implement-micronutrients): audited against both real sources
/// this app has -- Garmin's own `NutritionContent` (GarminModels.swift,
/// confirmed-live `foodSearch` shape) and Open Food Facts's `nutriments`
/// object (OpenFoodFactsClient.swift). Garmin/FatSecret's `vitaminA`/
/// `vitaminC`/`calcium`/`iron` below are a **percentage of daily value**
/// (`MealDashboard.NutrientKind.unit`'s existing "%" documents this) --
/// that is the only form Garmin's API returns them in, so those four fields
/// stay Garmin/FatSecret-only. Everything from `vitaminB1` down is a NEW
/// field this pass adds, populated **only from Open Food Facts** (in
/// absolute mg/µg per serving, OFF's own convention) -- Garmin's confirmed
/// `NutritionContent` shape has no equivalent fields at all (verified by
/// re-reading every field GarminModels.swift already decodes; nothing
/// further was left undecoded there). Mixing an absolute mg/µg value into
/// the same field as a %DV value would be exactly the kind of
/// misleading-as-real data this project has zero tolerance for, so the two
/// vocabularies are kept in clearly separate fields rather than merged. See
/// `Serving.detailedNutrients` below for how this expanded set reaches the
/// UI (`MealDashboard.NutrientKind`/`NutrientAmount`, reused here for a
/// single serving rather than a day/meal total).
public struct Serving: Codable, Sendable, Equatable, Hashable, Identifiable {
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
    /// mg. Garmin's own `NutritionContent.cholesterol` is confirmed mg
    /// (`docs/garmin-food-log-contract.md`'s read-shape example: `4` for a
    /// 65-kcal food). Open Food Facts also populates this now
    /// (`OpenFoodFactsClient` converts its raw per-100g grams to mg) -- both
    /// sources agree on the unit, unlike `vitaminA`/`calcium`/etc. below.
    public let cholesterol: Double?
    /// mg, same both-sources-agree-on-unit note as `cholesterol` above.
    public let sodium: Double?
    /// mg, same note.
    public let potassium: Double?
    /// %DV -- Garmin/FatSecret only, see this struct's header comment.
    public let vitaminA: Double?
    /// %DV -- Garmin/FatSecret only.
    public let vitaminC: Double?
    /// %DV -- Garmin/FatSecret only.
    public let calcium: Double?
    /// %DV -- Garmin/FatSecret only.
    public let iron: Double?

    // MARK: New in implement-micronutrients (2026-09-22) -- Open Food Facts
    // only; Garmin's confirmed API shape has no equivalent field for any of
    // these (see this struct's header comment). All mg/µg, absolute per
    // serving, OFF's own convention -- OpenFoodFactsClient converts OFF's
    // raw per-100g GRAMS values to these units at decode time. Field ids
    // cited below are OFF's own nutrient-taxonomy ids
    // (static.openfoodfacts.org/data/taxonomies/nutrients.json), confirmed
    // live on real products via this app's own search endpoint for
    // vitaminB1/B2/B3/B5/B6/D (2026-09-22 capture, e.g. a Chocapic/Kellogg's
    // fortified-cereal result); the rest are confirmed to exist and to carry
    // these exact ids/units by that same OFF taxonomy file but were not
    // captured live in a real product response this session (OFF's
    // anonymous-request rate limit was hit while researching) -- still real
    // fields Open Food Facts's schema defines, not invented ones, just with
    // a lower live-evidence bar than the ones above. Any of these can be
    // `nil` per-product exactly like every other optional nutrient field in
    // this codebase already works: OFF's per-product data is genuinely
    // incomplete, not every manufacturer declares every nutrient.

    /// mg. OFF field `vitamin-b1` (thiamin). Live-confirmed 2026-09-22.
    public let vitaminB1: Double?
    /// mg. OFF field `vitamin-b2` (riboflavin). Live-confirmed 2026-09-22.
    public let vitaminB2: Double?
    /// mg. OFF field `vitamin-pp` (niacin, Vitamin B3). Live-confirmed 2026-09-22.
    public let vitaminB3: Double?
    /// mg. OFF field `pantothenic-acid` (Vitamin B5). Live-confirmed 2026-09-22.
    public let vitaminB5: Double?
    /// mg. OFF field `vitamin-b6`. Live-confirmed 2026-09-22.
    public let vitaminB6: Double?
    /// µg. OFF field `vitamin-b9` (folate/folic acid). Taxonomy-confirmed only.
    public let vitaminB9: Double?
    /// µg. OFF field `vitamin-b12` (cobalamin). Taxonomy-confirmed only.
    public let vitaminB12: Double?
    /// µg. OFF field `vitamin-d`. Live-confirmed 2026-09-22.
    public let vitaminD: Double?
    /// mg. OFF field `vitamin-e`. Taxonomy-confirmed only.
    public let vitaminE: Double?
    /// µg. OFF field `vitamin-k`. Taxonomy-confirmed only.
    public let vitaminK: Double?
    /// mg. OFF field `magnesium`. Taxonomy-confirmed only.
    public let magnesium: Double?
    /// mg. OFF field `zinc`. Taxonomy-confirmed only.
    public let zinc: Double?
    /// mg. OFF field `phosphorus`. Taxonomy-confirmed only.
    public let phosphorus: Double?
    /// µg. OFF field `selenium`. Taxonomy-confirmed only.
    public let selenium: Double?
    /// mg. OFF field `copper`. Taxonomy-confirmed only.
    public let copper: Double?
    /// mg. OFF field `manganese`. Taxonomy-confirmed only.
    public let manganese: Double?
    /// µg. OFF field `iodine`. Taxonomy-confirmed only.
    public let iodine: Double?
    /// mg. OFF field `omega-3-fat`. Taxonomy-confirmed only.
    public let omega3: Double?
    /// mg. OFF field `omega-6-fat`. Taxonomy-confirmed only.
    public let omega6: Double?

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
        iron: Double? = nil,
        vitaminB1: Double? = nil,
        vitaminB2: Double? = nil,
        vitaminB3: Double? = nil,
        vitaminB5: Double? = nil,
        vitaminB6: Double? = nil,
        vitaminB9: Double? = nil,
        vitaminB12: Double? = nil,
        vitaminD: Double? = nil,
        vitaminE: Double? = nil,
        vitaminK: Double? = nil,
        magnesium: Double? = nil,
        zinc: Double? = nil,
        phosphorus: Double? = nil,
        selenium: Double? = nil,
        copper: Double? = nil,
        manganese: Double? = nil,
        iodine: Double? = nil,
        omega3: Double? = nil,
        omega6: Double? = nil
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
        self.vitaminB1 = vitaminB1
        self.vitaminB2 = vitaminB2
        self.vitaminB3 = vitaminB3
        self.vitaminB5 = vitaminB5
        self.vitaminB6 = vitaminB6
        self.vitaminB9 = vitaminB9
        self.vitaminB12 = vitaminB12
        self.vitaminD = vitaminD
        self.vitaminE = vitaminE
        self.vitaminK = vitaminK
        self.magnesium = magnesium
        self.zinc = zinc
        self.phosphorus = phosphorus
        self.selenium = selenium
        self.copper = copper
        self.manganese = manganese
        self.iodine = iodine
        self.omega3 = omega3
        self.omega6 = omega6
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

    /// Every nutrient this serving actually carries, as `[NutrientAmount]`
    /// (`MealDashboard.swift`) -- reusing that day/meal-total display type
    /// for a single serving instead, since a `NutrientAmount` is just "a
    /// kind plus a value" with no dependency on `DailyNutritionContent`.
    ///
    /// This exists because `MealDashboard.nutrients(content:totals:)` is a
    /// hard ceiling: it can only show what Garmin's own daily/meal log
    /// aggregate returns, and Garmin's confirmed API genuinely has nothing
    /// beyond the ~17 fields already modeled there (see this struct's
    /// header comment) -- an Open Food Facts result's richer per-serving
    /// panel (vitaminB1...omega6) never flows into that Garmin aggregate at
    /// all, so the only honest place to show it is here, against the food
    /// actually being looked at (`LogEntryConfirmView`'s "Nutrition"
    /// section), not pretended into a day total it was never part of.
    ///
    /// Skips anything nil, same "only show what's actually present, never
    /// a fabricated zero" rule `MealDashboard.nutrients` already follows.
    /// In `NutrientKind.allCases` order, so vitamins/minerals group
    /// together the way `NutrientKind.group` expects the UI to render them.
    public var detailedNutrients: [NutrientAmount] {
        NutrientKind.allCases.compactMap { kind in
            guard let value = value(for: kind) else { return nil }
            return NutrientAmount(kind: kind, value: value)
        }
    }

    private func value(for kind: NutrientKind) -> Double? {
        switch kind {
        case .calories: return calories
        case .carbs: return carbs
        case .fiber: return fiber
        case .sugar: return sugar
        case .protein: return protein
        case .fat: return fat
        case .saturatedFat: return saturatedFat
        case .monounsaturatedFat: return monounsaturatedFat
        case .polyunsaturatedFat: return polyunsaturatedFat
        case .cholesterol: return cholesterol
        case .sodium: return sodium
        case .potassium: return potassium
        case .vitaminA: return vitaminA
        case .vitaminC: return vitaminC
        case .calcium: return calcium
        case .iron: return iron
        case .vitaminB1: return vitaminB1
        case .vitaminB2: return vitaminB2
        case .vitaminB3: return vitaminB3
        case .vitaminB5: return vitaminB5
        case .vitaminB6: return vitaminB6
        case .vitaminB9: return vitaminB9
        case .vitaminB12: return vitaminB12
        case .vitaminD: return vitaminD
        case .vitaminE: return vitaminE
        case .vitaminK: return vitaminK
        case .magnesium: return magnesium
        case .zinc: return zinc
        case .phosphorus: return phosphorus
        case .selenium: return selenium
        case .copper: return copper
        case .manganese: return manganese
        case .iodine: return iodine
        case .omega3: return omega3
        case .omega6: return omega6
        }
    }
}

/// A loggable food -- either a real Garmin/FatSecret catalog entry or a
/// locally-created custom food (`source == .custom`), both represented
/// identically per design.md D4 so the rest of the app doesn't need to
/// special-case which kind it's showing.
// `Hashable` so the app layer can use `Food` directly with SwiftUI's
// `navigationDestination(item:)`/`NavigationLink(value:)` APIs without a
// wrapper type.
public struct Food: Codable, Sendable, Equatable, Hashable, Identifiable {
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
