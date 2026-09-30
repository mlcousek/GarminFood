// IngredientCatalog.swift
//
// add-custom-ingredients-and-owner-supplements: every ingredient the app
// can name without the user typing it, and the search the product editor's
// ingredient picker runs over them plus the user's own
// (`CustomIngredient`).
//
// Two tiers of "known" ingredient:
//   - `IngredientID.builtIn`: each has an evidence card with a cited limit
//     (EvidenceCatalog) -- unchanged here;
//   - `IngredientCatalog.extra`: ingredients printed on real labels the
//     app ships (the owner's branded products, SupplementCatalog+Branded)
//     that have NO evidence card -- copper, turmeric, MSM, glucosamine...
//     They get a display name (en + cs) and search aliases only. No limit,
//     range or health text is invented for them (design D3); the label
//     score says "no reference range" as it does for any other ingredient
//     without a card.
//
// `suggestedForms` lists common chemical forms per ingredient as they are
// written on labels ("bisglycinate", "MK-7"). Forms are label text and
// stay untranslated, like the magnesium forms before them.
//
// Depends on: SupplementModels, EvidenceCatalog (built-in names),
// CustomIngredients, SearchText (folding). Depended on by: the app's
// ingredient picker, SupplementPlan.ingredientName. Tests:
// CustomIngredientTests.

import Foundation

extension IngredientID {
    public static let copper: IngredientID = "copper"
    public static let calcium: IngredientID = "calcium"
    public static let turmeric: IngredientID = "turmeric"
    public static let rosehipExtract: IngredientID = "rosehipExtract"
    public static let citrusBioflavonoids: IngredientID = "citrusBioflavonoids"
    public static let tartCherry: IngredientID = "tartCherry"
    public static let valerian: IngredientID = "valerian"
    public static let gaba: IngredientID = "gaba"
    public static let lTheanine: IngredientID = "lTheanine"
    public static let greenTeaExtract: IngredientID = "greenTeaExtract"
    public static let msm: IngredientID = "msm"
    public static let glucosamine: IngredientID = "glucosamine"
    public static let chondroitin: IngredientID = "chondroitin"
    public static let collagenTypeI: IngredientID = "collagenTypeI"
    public static let collagenTypeII: IngredientID = "collagenTypeII"
}

public enum IngredientCatalog {
    /// Known ingredients without an evidence card, all counted in mg.
    public static let extra: [IngredientID] = [
        .copper, .calcium, .turmeric, .rosehipExtract, .citrusBioflavonoids, .tartCherry, .valerian,
        .gaba, .lTheanine, .greenTeaExtract, .msm, .glucosamine, .chondroitin, .collagenTypeI, .collagenTypeII
    ]

    /// Every known ingredient: evidence-card ones first, then the extras.
    public static var known: [IngredientID] { IngredientID.builtIn + extra }

    public static func isKnown(_ ingredient: IngredientID) -> Bool {
        known.contains(ingredient)
    }

    /// Display name of a known ingredient, `nil` for any other id.
    public static func knownName(of ingredient: IngredientID) -> String? {
        if IngredientID.builtIn.contains(ingredient) { return EvidenceCatalog.name(of: ingredient) }
        return extraName(of: ingredient)
    }

    /// Names of the extras (EvidenceCatalog.name falls back to these).
    static func extraName(of ingredient: IngredientID) -> String? {
        switch ingredient {
        case .copper: return String(localized: "Copper", bundle: .module, comment: "Nutrient name.")
        case .calcium: return String(localized: "Calcium", bundle: .module, comment: "Nutrient name.")
        case .turmeric: return String(localized: "Turmeric", bundle: .module, comment: "Supplement ingredient name (Curcuma longa root powder).")
        case .rosehipExtract: return String(localized: "Rosehip extract", bundle: .module, comment: "Supplement ingredient name.")
        case .citrusBioflavonoids: return String(localized: "Citrus bioflavonoids", bundle: .module, comment: "Supplement ingredient name.")
        case .tartCherry: return String(localized: "Tart cherry juice", bundle: .module, comment: "Supplement ingredient name (Prunus cerasus).")
        case .valerian: return String(localized: "Valerian root", bundle: .module, comment: "Supplement ingredient name (herb).")
        case .gaba: return String(localized: "GABA", bundle: .module, comment: "Supplement ingredient name (gamma-aminobutyric acid).")
        case .lTheanine: return String(localized: "L-theanine", bundle: .module, comment: "Supplement ingredient name (amino acid).")
        case .greenTeaExtract: return String(localized: "Green tea extract", bundle: .module, comment: "Supplement ingredient name.")
        case .msm: return String(localized: "MSM (methylsulfonylmethane)", bundle: .module, comment: "Supplement ingredient name.")
        case .glucosamine: return String(localized: "Glucosamine", bundle: .module, comment: "Supplement ingredient name.")
        case .chondroitin: return String(localized: "Chondroitin", bundle: .module, comment: "Supplement ingredient name.")
        case .collagenTypeI: return String(localized: "Collagen type I", bundle: .module, comment: "Supplement ingredient name.")
        case .collagenTypeII: return String(localized: "Collagen type II", bundle: .module, comment: "Supplement ingredient name.")
        default: return nil
        }
    }

    /// Extra words a search matches in both languages, whatever language
    /// the app runs in ("hořčík" finds magnesium in English too).
    static func aliases(of ingredient: IngredientID) -> [String] {
        switch ingredient {
        case .creatine: return ["creatine", "kreatin"]
        case .magnesium: return ["magnesium", "hořčík", "magnézium", "Mg"]
        case .vitaminD: return ["vitamin D", "vitamín D", "D3", "cholecalciferol", "cholekalciferol"]
        case .vitaminC: return ["vitamin C", "vitamín C", "ascorbic", "askorbová"]
        case .zinc: return ["zinc", "zinek", "Zn"]
        case .omega3EPA_DHA: return ["omega-3", "EPA", "DHA", "fish oil", "rybí olej"]
        case .vitaminB12: return ["vitamin B12", "vitamín B12", "cobalamin", "kobalamin"]
        case .iron: return ["iron", "železo", "Fe"]
        case .selenium: return ["selenium", "selen", "Se"]
        case .vitaminB6: return ["vitamin B6", "vitamín B6", "pyridoxine", "P5P", "pyridoxal"]
        case .caffeine: return ["caffeine", "kofein"]
        case .betaAlanine: return ["beta-alanine", "beta-alanin"]
        case .sodium: return ["sodium", "sodík", "Na"]
        case .potassium: return ["potassium", "draslík", "K"]
        case .vitaminK2: return ["vitamin K2", "vitamín K2", "menaquinone", "menachinon", "MK-7"]
        case .copper: return ["copper", "měď", "Cu"]
        case .calcium: return ["calcium", "vápník", "Ca"]
        case .turmeric: return ["turmeric", "kurkuma", "curcuma", "curcumin"]
        case .rosehipExtract: return ["rosehip", "šípek", "šípky"]
        case .citrusBioflavonoids: return ["bioflavonoids", "bioflavonoidy", "citrus"]
        case .tartCherry: return ["tart cherry", "višně", "višeň"]
        case .valerian: return ["valerian", "kozlík"]
        case .gaba: return ["GABA", "gamma-aminobutyric", "gama-aminomáselná"]
        case .lTheanine: return ["L-theanine", "L-theanin", "theanine"]
        case .greenTeaExtract: return ["green tea", "zelený čaj"]
        case .msm: return ["MSM", "methylsulfonylmethane", "methylsulfonylmethan"]
        case .glucosamine: return ["glucosamine", "glukosamin"]
        case .chondroitin: return ["chondroitin"]
        case .collagenTypeI: return ["collagen", "kolagen", "type I"]
        case .collagenTypeII: return ["collagen", "kolagen", "type II"]
        default: return []
        }
    }

    /// Common label forms of `ingredient`, most common first. A custom
    /// ingredient offers the forms the user typed before.
    public static func suggestedForms(of ingredient: IngredientID, custom: CustomIngredient? = nil) -> [String] {
        if let custom { return custom.forms }
        switch ingredient {
        case .magnesium:
            return [MagnesiumForm.citrate, .bisglycinate, .malate, .oxide, .lactate, .chloride, .carbonate, .glycerophosphate, .threonate, .aspartate]
                .map(\.rawValue)
        case .zinc: return ["bisglycinate", "citrate", "gluconate", "picolinate", "oxide"]
        case .selenium: return ["L-selenomethionine", "sodium selenite"]
        case .copper: return ["citrate", "bisglycinate", "gluconate"]
        case .calcium: return ["carbonate", "citrate"]
        case .vitaminD: return ["cholecalciferol", "ergocalciferol"]
        case .vitaminK2: return ["MK-7", "MK-4"]
        case .vitaminB6: return ["pyridoxal-5-phosphate", "pyridoxine hydrochloride"]
        case .vitaminB12: return ["methylcobalamin", "cyanocobalamin", "adenosylcobalamin", "hydroxocobalamin"]
        case .vitaminC: return ["ascorbic acid", "liposomal", "calcium ascorbate"]
        case .iron: return ["bisglycinate", "fumarate", "sulfate"]
        case .omega3EPA_DHA: return ["triglyceride", "re-esterified triglyceride", "ethyl ester"]
        case .creatine: return ["monohydrate"]
        case .glucosamine: return ["sulfate"]
        case .chondroitin: return ["sulfate"]
        default: return []
        }
    }
}

/// One entry of the ingredient picker.
public struct IngredientChoice: Sendable, Equatable, Identifiable {
    public let id: IngredientID
    public let name: String
    /// The unit a new row starts in.
    public let unit: DoseUnit
    public let isCustom: Bool
    /// Has an evidence card (limits, ranges).
    public let hasEvidence: Bool

    public init(id: IngredientID, name: String, unit: DoseUnit, isCustom: Bool, hasEvidence: Bool) {
        self.id = id
        self.name = name
        self.unit = unit
        self.isCustom = isCustom
        self.hasEvidence = hasEvidence
    }
}

public enum IngredientSearch {
    /// The picker's list for `query`: the user's own ingredients first,
    /// then known ones, each group ranked "name starts with" before
    /// "contains"; an empty query lists everything (custom first, then
    /// known in catalog order, then A-Z).
    public static func choices(for query: String, custom: [CustomIngredient]) -> [IngredientChoice] {
        let folded = SearchText.fold(CustomIngredient.clean(query))
        let customChoices = custom.map {
            IngredientChoice(id: $0.id, name: $0.name, unit: $0.unit, isCustom: true, hasEvidence: false)
        }
        let knownChoices = IngredientCatalog.known.map { id in
            IngredientChoice(
                id: id,
                name: IngredientCatalog.knownName(of: id) ?? id.rawValue,
                unit: id.canonicalUnit,
                isCustom: false,
                hasEvidence: EvidenceCatalog.card(for: id) != nil
            )
        }
        guard !folded.isEmpty else {
            return customChoices.sorted(by: byName) + knownChoices
        }
        func rank(_ choice: IngredientChoice) -> Int? {
            let names = [choice.name] + (choice.isCustom ? [] : IngredientCatalog.aliases(of: choice.id))
            let foldedNames = names.map { SearchText.fold($0) }
            if foldedNames.contains(where: { $0.hasPrefix(folded) }) { return 0 }
            if foldedNames.contains(where: { $0.contains(folded) }) { return 1 }
            return nil
        }
        func ranked(_ list: [IngredientChoice]) -> [IngredientChoice] {
            list.compactMap { choice in rank(choice).map { (choice, $0) } }
                .sorted { $0.1 != $1.1 ? $0.1 < $1.1 : byName($0.0, $1.0) }
                .map(\.0)
        }
        return ranked(customChoices) + ranked(knownChoices)
    }

    /// Whether `query` should offer "Add … as your own ingredient": it is
    /// not blank and no choice already has exactly that name.
    public static func canCreate(_ query: String, custom: [CustomIngredient]) -> Bool {
        let folded = SearchText.fold(CustomIngredient.clean(query))
        guard !folded.isEmpty else { return false }
        return !choices(for: query, custom: custom).contains { SearchText.fold($0.name) == folded }
    }

    private static func byName(_ lhs: IngredientChoice, _ rhs: IngredientChoice) -> Bool {
        lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
}
