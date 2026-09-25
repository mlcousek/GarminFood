// FoodTagRules+Sport.swift
//
// add-sport-and-body-achievements design D3: the phrases that assign
// `sport.carbRich` (`FoodTag+Sport.swift`), the fallback "Fuelled Up" uses
// when an entry's carbohydrate grams are unknown. Owned by that change;
// `FoodTagRuleRegistry.all` already lists this set, so nothing shared is
// edited.
//
// Phrase syntax (see FoodTagRule.swift): "ryba" = stem match, "banan*" =
// folded prefix, "=med" = exact folded word; words are written without
// diacritics. Exact forms guard the dangerous neighbours: "med" (honey) vs
// "medvědí česnek", "rýže" vs "Ryzlink" (wine). Drinks and dairy made FROM a
// carb food (rýžový nápoj -- a milk substitute --, banánový jogurt, ovesné
// mléko) are excluded: they are not a pre-run carb snack. The ionic/sports
// drink is its own rule precisely so that exclusion does not veto it.
//
// Every rule is exercised by SportTaggerTests (FoodLogCoreTests).
//
// Depends on: FoodTagRule, FoodTag+Sport. Depended on by:
// FoodTagRuleRegistry, Gamification's sport & body feature.

import Foundation

extension FoodTagRuleSet {
    public static let sport = FoodTagRuleSet(id: "sport", rules: FoodTagRuleSet.sportRules)

    static let sportRules: [FoodTagRule] = [
        // Carb staples and pre-run snacks.
        FoodTagRule(
            tags: [.sportCarbRich],
            anyPhrases: [
                // Fruit and sweet
                "banan*", "datl*", "=med", "=medu", "=honey",
                // Porridge, muesli
                "ovesn* kas*", "ovesn* vlock*", "porridge*", "oatmeal*", "=oats", "musli*", "muesli*", "granol*",
                // Bread and rolls
                "rohlik*", "rohlick*", "chleb*", "=bread", "baget*", "housk*",
                // Pasta and rice
                "testovin*", "spaget*", "=penne", "fusill*", "makaron*", "nudl*",
                "=ryze", "=ryzi", "ryzov*", "=rice", "rizot*", "risott*",
                // Sports nutrition
                "energ* gel*", "=gel", "=gely", "carb* gel*", "energ* tycink*", "energ* bar*"
            ],
            excludePhrases: [
                "napoj*", "drink*", "jogurt*", "yogurt*", "yoghurt*", "mlek*", "=milk", "shake*", "prichut*",
                "flavour*", "flavor*", "=ocet", "=octem", "vinegar*"
            ]
        ),
        // Ionic / isotonic sports drinks (a "nápoj" the rule above excludes).
        FoodTagRule(
            tags: [.sportCarbRich],
            anyPhrases: ["ionto* napoj*", "iont*", "isoton*", "izoton*", "=ionak", "sportovn* napoj*", "sport* drink*"]
        )
    ]
}
