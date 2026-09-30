// SupplementCatalog.swift
//
// The built-in products a user can add in two taps (add-supplements D2,
// proposal "My stack", spec "Products are added from a catalog..."): each
// with a default serving, per-serving ingredients that link to an
// `EvidenceCard`, and a suggested slot. `makeProduct()` only PROPOSES a
// product -- the editor lets the user change every amount before saving.
//
// Doses are common label amounts, chosen to sit inside each card's
// effective range and under its default limit, not a recommendation.
// Vitamin D is entered in IU as most labels print it; totals convert
// (`DoseUnit.convert`).
//
// Serving descriptions use `ProductForm.servingText(count:)`, whose Czech
// plurals ("1 kapsle / 2 kapsle / 5 kapslí", design D12) live in
// Resources/*.lproj/Localizable.stringsdict.
//
// Branded products with their real labels (add-custom-ingredients-and-
// owner-supplements) are a separate list, `SupplementCatalog.branded`
// (SupplementCatalog+Branded.swift): their ingredients need not have a
// card, so the invariant above holds for `all` only.
//
// Depended on by: onboarding and the product editor (wave 3).
// Tests: EvidenceCatalogTests (every catalog ingredient has a card),
// BrandedSupplementCatalogTests.

import Foundation

extension ProductForm {
    /// "2 capsules" / "2 kapsle", pluralised per language. Forms without a
    /// countable unit say "servings".
    public func servingText(count: Int) -> String {
        switch self {
        case .capsule:
            return String(localized: "\(count) capsules", bundle: .module, comment: "Supplement serving size: a number of capsules (plural in Localizable.stringsdict).")
        case .tablet:
            return String(localized: "\(count) tablets", bundle: .module, comment: "Supplement serving size: a number of tablets (plural in Localizable.stringsdict).")
        case .gummy:
            return String(localized: "\(count) gummies", bundle: .module, comment: "Supplement serving size: a number of gummies (plural in Localizable.stringsdict).")
        default:
            return String(localized: "\(count) servings", bundle: .module, comment: "Supplement serving size or dose count: a number of servings (plural in Localizable.stringsdict).")
        }
    }
}

public struct CatalogProduct: Sendable, Identifiable {
    public enum Serving: Sendable, Equatable {
        /// `count` capsules/tablets/gummies.
        case units(Int)
        /// A powder scoop of `grams` g.
        case scoop(grams: Int)
        /// A measure of powder whose weight may have decimals ("4,5 g"),
        /// as a branded label states it (SupplementCatalog+Branded).
        case measure(grams: Double)
        /// One sachet of `grams` g (granules or powder to dissolve).
        case sachet(grams: Double)
    }

    /// Stable id, stored in `ProductSource.catalog(_:)`.
    public let id: String
    public let form: ProductForm
    public let serving: Serving
    public let ingredients: [IngredientAmount]
    public let suggestedSlot: TimeSlot
    /// A branded product's pack facts and sources; `nil` for the generic
    /// entries of `SupplementCatalog.all`.
    public var label: CatalogLabel? = nil

    /// The generic name, or a branded product's name as printed on the pack
    /// (never translated).
    public var name: String { label?.productName ?? SupplementCatalog.name(of: id) }

    public var servingDescription: String {
        switch serving {
        case .units(let count):
            return form.servingText(count: count)
        case .scoop(let grams):
            return String(localized: "\(grams) g scoop", bundle: .module, comment: "Supplement serving size: one powder scoop of %lld grams.")
        case .measure(let grams):
            let text = NumberDisplay.trimmed(grams, maxFractionDigits: 2)
            return String(localized: "\(text) g measure", bundle: .module, comment: "Supplement serving size: one measure (scoop) of powder; %@ is the weight in grams, may have decimals.")
        case .sachet(let grams):
            let text = NumberDisplay.trimmed(grams, maxFractionDigits: 2)
            return String(localized: "\(text) g sachet", bundle: .module, comment: "Supplement serving size: one sachet; %@ is its weight in grams, may have decimals.")
        }
    }

    /// The proposed product, ready for the editor. A branded product also
    /// brings its brand, barcode and servings per pack.
    public func makeProduct(id productId: UUID = UUID()) -> SupplementProduct {
        SupplementProduct(
            id: productId,
            name: name,
            brand: label?.brand,
            barcode: label?.barcode,
            form: form,
            servingDescription: servingDescription,
            ingredients: ingredients,
            packServings: label?.packServings,
            source: .catalog(id)
        )
    }

    /// A schedule proposal: one serving daily in the suggested slot.
    public var suggestedSchedule: SupplementSchedule {
        SupplementSchedule(slots: [suggestedSlot], servingsPerSlot: 1, pattern: .daily)
    }
}

public enum SupplementCatalog {
    private static func row(_ ingredient: IngredientID, _ amount: Double, _ unit: DoseUnit, form: MagnesiumForm? = nil) -> IngredientAmount {
        IngredientAmount(ingredient: ingredient, amount: amount, unit: unit, form: form?.rawValue)
    }

    public static let all: [CatalogProduct] = [
        CatalogProduct(id: "creatineMonohydrate", form: .powder, serving: .scoop(grams: 5),
                       ingredients: [row(.creatine, 5, .g)], suggestedSlot: .morning),
        CatalogProduct(id: "magnesiumCitrate", form: .capsule, serving: .units(2),
                       ingredients: [row(.magnesium, 200, .mg, form: .citrate)], suggestedSlot: .evening),
        CatalogProduct(id: "magnesiumBisglycinate", form: .capsule, serving: .units(2),
                       ingredients: [row(.magnesium, 200, .mg, form: .bisglycinate)], suggestedSlot: .evening),
        CatalogProduct(id: "magnesiumOxide", form: .tablet, serving: .units(1),
                       ingredients: [row(.magnesium, 200, .mg, form: .oxide)], suggestedSlot: .evening),
        CatalogProduct(id: "vitaminD3", form: .capsule, serving: .units(1),
                       ingredients: [row(.vitaminD, 1000, .iu)], suggestedSlot: .withBreakfast),
        CatalogProduct(id: "vitaminD3K2", form: .capsule, serving: .units(1),
                       ingredients: [row(.vitaminD, 1000, .iu), row(.vitaminK2, 75, .ug)], suggestedSlot: .withBreakfast),
        CatalogProduct(id: "vitaminC", form: .tablet, serving: .units(1),
                       ingredients: [row(.vitaminC, 500, .mg)], suggestedSlot: .morning),
        CatalogProduct(id: "zinc", form: .tablet, serving: .units(1),
                       ingredients: [row(.zinc, 15, .mg)], suggestedSlot: .evening),
        CatalogProduct(id: "omega3Fish", form: .capsule, serving: .units(2),
                       ingredients: [row(.omega3EPA_DHA, 600, .mg)], suggestedSlot: .withBreakfast),
        CatalogProduct(id: "omega3Algae", form: .capsule, serving: .units(2),
                       ingredients: [row(.omega3EPA_DHA, 500, .mg)], suggestedSlot: .withBreakfast),
        CatalogProduct(id: "vitaminB12", form: .tablet, serving: .units(1),
                       ingredients: [row(.vitaminB12, 250, .ug)], suggestedSlot: .morning),
        CatalogProduct(id: "iron", form: .tablet, serving: .units(1),
                       ingredients: [row(.iron, 14, .mg)], suggestedSlot: .morning),
        CatalogProduct(id: "selenium", form: .tablet, serving: .units(1),
                       ingredients: [row(.selenium, 100, .ug)], suggestedSlot: .morning),
        CatalogProduct(id: "electrolytes", form: .tablet, serving: .units(1),
                       ingredients: [row(.sodium, 500, .mg), row(.potassium, 150, .mg), row(.magnesium, 50, .mg, form: .citrate)],
                       suggestedSlot: .preWorkout),
        CatalogProduct(id: "caffeine", form: .tablet, serving: .units(1),
                       ingredients: [row(.caffeine, 100, .mg)], suggestedSlot: .preWorkout),
        CatalogProduct(id: "betaAlanine", form: .capsule, serving: .units(2),
                       ingredients: [row(.betaAlanine, 3.2, .g)], suggestedSlot: .morning)
    ]

    /// A generic entry or a branded one (SupplementCatalog+Branded).
    public static func product(id: String) -> CatalogProduct? {
        all.first { $0.id == id } ?? branded.first { $0.id == id }
    }

    static func name(of id: String) -> String {
        switch id {
        case "creatineMonohydrate": return String(localized: "Creatine monohydrate", bundle: .module, comment: "Built-in supplement product name.")
        case "magnesiumCitrate": return String(localized: "Magnesium citrate", bundle: .module, comment: "Built-in supplement product name.")
        case "magnesiumBisglycinate": return String(localized: "Magnesium bisglycinate", bundle: .module, comment: "Built-in supplement product name.")
        case "magnesiumOxide": return String(localized: "Magnesium oxide", bundle: .module, comment: "Built-in supplement product name.")
        case "vitaminD3": return String(localized: "Vitamin D3", bundle: .module, comment: "Built-in supplement product name.")
        case "vitaminD3K2": return String(localized: "Vitamin D3 + K2", bundle: .module, comment: "Built-in supplement product name.")
        case "vitaminC": return String(localized: "Vitamin C", bundle: .module, comment: "Nutrient name.")
        case "zinc": return String(localized: "Zinc", bundle: .module, comment: "Nutrient name.")
        case "omega3Fish": return String(localized: "Omega-3 fish oil", bundle: .module, comment: "Built-in supplement product name.")
        case "omega3Algae": return String(localized: "Omega-3 algae oil", bundle: .module, comment: "Built-in supplement product name (vegan omega-3 from algae).")
        case "vitaminB12": return String(localized: "Vitamin B12", bundle: .module, comment: "Nutrient name.")
        case "iron": return String(localized: "Iron", bundle: .module, comment: "Nutrient name.")
        case "selenium": return String(localized: "Selenium", bundle: .module, comment: "Nutrient name.")
        case "electrolytes": return String(localized: "Electrolytes", bundle: .module, comment: "Built-in supplement product name (electrolyte tablet: sodium, potassium, magnesium).")
        case "caffeine": return String(localized: "Caffeine", bundle: .module, comment: "Supplement ingredient name.")
        case "betaAlanine": return String(localized: "Beta-alanine", bundle: .module, comment: "Supplement ingredient name.")
        default: return id
        }
    }
}
