// FoodTagRules+Seasonal.swift
//
// add-seasonal-events design D3: the phrases that assign the seasonal tags
// (`FoodTag+Seasonal.swift`) the Czech event quests match on. Owned by that
// change; `FoodTagRuleRegistry.all` already lists this set, so nothing
// shared is edited.
//
// Phrase syntax (see FoodTagRule.swift): "ryba" = stem match, "jahod*" =
// folded prefix, "=husa" = exact folded word; words are written without
// diacritics. Prefix and exact forms are preferred here because several
// seasonal words have dangerous neighbours: "kapr" (carp) vs "kapary"
// (capers), "houba" (mushroom) vs "mycí houba" (sponge), "čočka" (lentils)
// vs English "cocktail", "lentils" vs Czech "lentilky" (sweets).
// Flavoured industrial products (jahodový jogurt, pomerančový džus) are
// excluded from the produce rules, as in the core set.
//
// Every rule is exercised by SeasonalTaggerTests (FoodLogCoreTests).
//
// Depends on: FoodTagRule, FoodTag+Seasonal. Depended on by:
// FoodTagRuleRegistry, Gamification's seasonal events feature.

import Foundation

extension FoodTagRuleSet {
    public static let seasonal = FoodTagRuleSet(id: "seasonal", rules: FoodTagRuleSet.seasonalRules)

    private static let flavouredProductExclusions: [String] = [
        "jogurt*", "yogurt*", "yoghurt*", "dzem*", "=jam", "marmelad*", "sirup*", "prichut*", "flavour*",
        "flavor*", "napoj*", "drink*", "dzus*", "juice*", "nektar", "limonad*", "bonbon*", "caj*", "=tea",
        "musli*", "muesli*", "tycink*", "lizatk*", "cokolad*", "chocolate*"
    ]

    static let seasonalRules: [FoodTagRule] = [
        // Masopust (Carnival)
        FoodTagRule(
            tags: [.seasonMasopust],
            anyPhrases: [
                "koblih*", "kobliz*", "donut*", "doughnut*", "jitrnic*", "jelit*", "tlacenk*", "ovar",
                "prejt*", "skvark*", "prdelack*", "zabijack*", "bozi milost*"
            ]
        ),
        // Easter
        FoodTagRule(
            tags: [.seasonHam],
            anyPhrases: ["sunk*", "uzen*", "=ham", "prosciutt*", "prsut*", "=kyta", "=kyty"],
            excludePhrases: ["losos*", "salmon*", "makrel*", "uzenac*", "syr", "cheese*", "tofu", "tresk*", "ryb*"]
        ),
        FoodTagRule(
            tags: [.seasonMazanec],
            anyPhrases: ["mazan*", "=beranek", "=beranka", "=beranky", "velikonoc* beran*"]
        ),
        FoodTagRule(
            tags: [.seasonGreenThursday],
            anyPhrases: [
                "spenat*", "spinach*", "kopriv*", "nettle*", "zelen* salat*", "ledov* salat*", "salat* ledov*",
                "polnick*", "rukol*", "medved* cesnek*", "pazitk*", "zelen* smoothie*", "=kapusta", "=kale"
            ]
        ),
        // Summer
        FoodTagRule(
            tags: [.seasonStrawberry],
            anyPhrases: ["jahod*", "strawberr*"],
            excludePhrases: flavouredProductExclusions
        ),
        FoodTagRule(
            tags: [.seasonGrill],
            anyPhrases: [
                "grilov*", "=gril", "=grilu", "=grill", "grilled", "bbq", "barbecue", "klobas*", "spekac*",
                "steak*", "stejk*", "cevap*", "saslik*", "spiz", "=spizy"
            ],
            excludePhrases: ["polevk*", "soup*"]
        ),
        // Autumn
        FoodTagRule(
            tags: [.seasonMushroom],
            anyPhrases: [
                "houb*", "hrib*", "smazenic*", "kulajd*", "zampion*", "pecark*", "bedl*", "hliv*", "=lisky",
                "=liskami", "=lisek", "smrz*", "mushroom*", "champignon*", "portobell*", "shiitake", "=kozak",
                "=kozaky"
            ],
            excludePhrases: ["myc* houb*", "houbick* na nadobi*", "sponge*", "piskot*"]
        ),
        FoodTagRule(
            tags: [.seasonGoose],
            anyPhrases: [
                "=husa", "=husy", "=husu", "=husou", "=husi", "=husich", "=husim", "=husimi", "husick*",
                "goose"
            ]
        ),
        FoodTagRule(
            tags: [.seasonMartinRohlicek],
            anyPhrases: [
                "svatomartinsk* rohlic*", "svatomartinsk* rohlik*", "martinsk* rohlic*", "martinsk* rohlik*"
            ]
        ),
        // Advent and Christmas
        FoodTagRule(
            tags: [.seasonCitrus],
            anyPhrases: [
                "mandarink*", "mandarin*", "pomeranc*", "=orange", "=oranges", "klementink*", "clementin*"
            ],
            excludePhrases: flavouredProductExclusions
        ),
        FoodTagRule(
            tags: [.seasonChocolate],
            anyPhrases: ["cokolad*", "chocolate*", "=milka", "kinder", "=lindt", "pralink*", "praline*", "trufl*"]
        ),
        FoodTagRule(
            tags: [.seasonCukrovi],
            anyPhrases: [
                "=cukrovi", "=cukrovim", "vanilkov* rohlic*", "lineck*", "pernick*", "vosi* hnizd*", "=pracny",
                "=pracna", "kokosk*", "medved* tlapk*", "rumov* kulick*", "iselsk*", "pusink*",
                "christmas cookie*"
            ]
        ),
        FoodTagRule(
            tags: [.seasonCarp],
            anyPhrases: ["=kapr", "=kapra", "=kapri", "=kaprem", "=kapru", "=kaprovi", "kaprik*", "kaprov*", "carp"],
            excludePhrases: ["kapar*", "caper*"]
        ),
        FoodTagRule(
            tags: [.seasonPotatoSalad],
            anyPhrases: ["bramborov* salat*", "salat* bramborov*", "potato salad*"]
        ),
        FoodTagRule(
            tags: [.seasonFishSoup],
            anyPhrases: ["ryb* polevk*", "polevk* rybi", "polevk* z kapr*", "fish soup*"],
            excludePhrases: ["rybiz*"]
        ),
        FoodTagRule(
            tags: [.seasonVanocka],
            anyPhrases: ["vanock*", "vanocn* housk*"]
        ),
        // Silvestr and New Year
        FoodTagRule(
            tags: [.seasonChlebicek],
            anyPhrases: ["chlebic*"]
        ),
        FoodTagRule(
            tags: [.seasonJednohubky],
            anyPhrases: ["jednohubk*", "canape*", "kanapk*"]
        ),
        FoodTagRule(
            tags: [.seasonLentils],
            anyPhrases: ["=cocka", "=cocky", "=cocku", "=cockou", "cockov*", "=lentil", "=lentils", "=dhal", "=daal"]
        ),
        // Celebrations (name day)
        FoodTagRule(
            tags: [.seasonCake],
            anyPhrases: [
                "dort*", "zakusek", "zakusk*", "=cake", "=cakes", "cheesecake*", "cupcake*", "vetrnik*",
                "laskonk*", "sachr*", "sacher*", "tiramisu", "=rezy", "=rez"
            ]
        ),
        FoodTagRule(
            tags: [.seasonRizek],
            anyPhrases: ["rizek", "=rizek", "rizk*", "rizeck*", "schnitzel*"]
        )
    ]
}
