// FoodTagger.swift
//
// Classifies one food into `FoodTag`s from its name, brand and (when
// known) barcode (design D2). Pure and deterministic -- a hand-authored
// dictionary, golden-tested in FoodTaggerTests, never an ML guess.
//
// Name and brand are tokenized once with `SearchText.tokenize` (the same
// fold + stem food search uses); every registered rule set is evaluated;
// `czechBrand` is decided by `CzechBrands`. An empty/absent name simply
// yields no food-group tags (the entry still counts as an entry upstream).
//
// Macro-derived facts ("≥ 20 g protein") are NOT tags -- they depend on the
// logged quantity, not the food, and live in `DayPredicate` instead.
//
// Callers tag each distinct food once and memoise by food id
// (`DaySignalsBuilder` does), because a food's name does not change.
//
// Depends on: FoodTagRule, FoodTagRuleRegistry, CzechBrands, SearchText.

import Foundation

public enum FoodTagger {
    public static func tags(
        name: String?,
        brand: String?,
        barcode: String?,
        ruleSets: [FoodTagRuleSet] = FoodTagRuleRegistry.all
    ) -> Set<FoodTag> {
        let nameTokens = wordTokens(name)
        let brandTokens = wordTokens(brand)
        var result: Set<FoodTag> = []

        if !nameTokens.isEmpty || !brandTokens.isEmpty {
            for ruleSet in ruleSets {
                for rule in ruleSet.rules {
                    result.formUnion(rule.evaluate(nameTokens: nameTokens, brandTokens: brandTokens))
                }
            }
        }

        let brandKnown = !brandTokens.isEmpty
        if CzechBrands.containsCzechBrand(brandTokens)
            || CzechBrands.containsCzechBrand(nameTokens)
            || (!brandKnown && CzechBrands.isCzechEAN(barcode)) {
            result.insert(.czechBrand)
        }
        return result
    }

    static func wordTokens(_ text: String?) -> [SearchToken] {
        guard let text, !text.isEmpty else { return [] }
        return SearchText.tokenize(text).filter { !$0.isQuantity }
    }
}
