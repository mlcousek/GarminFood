// CzechBrands.swift
//
// Decides the `czechBrand` tag (design D2): "Czech Supermarket Safari"
// (a creative challenge) and the collections feature both reward trying
// Czech-made products, which a food's name alone cannot tell.
//
// Two signals, strongest first:
//   1. The brand (or, since Garmin often folds the brand into the food's
//      name -- "Kofola Original" -- the name) contains a brand on `all`.
//      Slovak brands such as Rajec are deliberately NOT on the list.
//   2. Only when the brand is unknown: a 13-digit EAN starting "859", the
//      GS1 prefix for Czech registrants. Weaker, because it marks who
//      registered the code, not where it was made -- so a known foreign
//      brand with an 859 barcode is not tagged.
//
// Brand words match with the same whole-token rules as `FoodTagRule`
// phrases. "Hamé" is an exact match because its light stem ("ham") would
// otherwise match English "ham".
//
// Depended on by: FoodTagger. Extend the list freely (design open
// question 3).

import Foundation

public enum CzechBrands {
    /// The brand phrases, in `FoodTagPhrase` syntax.
    public static let names: [String] = [
        "Madeta", "Kunín", "Tatra", "Olma", "Hollandia", "Pilos", "Albert Quality", "Penam", "Opavia",
        "Orion", "Kofola", "Mattoni", "Relax", "=Hamé", "Vitana", "Jihlavanka", "Kostelecké uzeniny",
        "Choceňská mlékárna", "Pribináček", "Emco", "Bonavita", "Semix"
    ]

    /// `names`, compiled once.
    public static let all: [FoodTagPhrase] = names.map(FoodTagPhrase.init)

    /// Whether any listed brand appears in `tokens` (word tokens of a brand
    /// or a food name).
    public static func containsCzechBrand(_ tokens: [SearchToken]) -> Bool {
        all.contains { $0.matches(tokens) }
    }

    /// A 13-digit EAN whose GS1 prefix is 859 (Czech Republic).
    public static func isCzechEAN(_ barcode: String?) -> Bool {
        guard let barcode else { return false }
        let trimmed = barcode.trimmingCharacters(in: .whitespaces)
        return trimmed.count == 13
            && trimmed.allSatisfy { $0.isASCII && $0.isNumber }
            && trimmed.hasPrefix("859")
    }
}
