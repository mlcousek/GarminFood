// FoodTagRules+Collections.swift
//
// add-food-collections design D1/D2: one `FoodTagRule` per collection entry
// (dishes by NAME, brands by BRAND text only), so "discovered" is just "a
// logged food carries this tag". Registered in `FoodTagRuleRegistry.all`
// by add-gamification-signals as the `.collections` slot.
//
// Written mostly with PREFIX ("svickov*") and EXACT ("=pho") word patterns
// rather than stems: they are predictable by eye, which matters with no
// local compiler to run the golden suite (CollectionsTaggerTests) before
// CI. Exclusions veto a rule for the risky look-alikes the design calls out
// (spice mixes, sauces, fruit dumplings vs. bread dumplings, pork shoulder
// "rameno" vs. ramen, tartar sauce vs. tatarák).
//
// Brands match `brand` text only (design D2), so "Jogurt s příchutí Kofoly"
// never counts as Kofola; the phrases are `CzechBrands.names`, via
// `FoodTag.czechBrandTags`.
//
// Depends on: FoodTagRule, FoodTag+Collections. Depended on by:
// FoodTagRuleRegistry, CollectionsTaggerTests.

import Foundation

extension FoodTagRuleSet {
    public static let collections = FoodTagRuleSet(
        id: "collections",
        rules: CollectionTagRules.dishes + CollectionTagRules.brands
    )
}

enum CollectionTagRules {
    static let dishes: [FoodTagRule] = czechClassics + world + fermented

    static let brands: [FoodTagRule] = FoodTag.czechBrandTags.map { pair in
        FoodTagRule(tags: [pair.tag], anyBrands: [pair.phrase])
    }

    private static let spiceWords = ["koren*", "spice*", "seasoning*", "ochucov*", "powder*", "prasek*"]

    static let czechClassics: [FoodTagRule] = [
        FoodTagRule(tags: [.dishSvickova], anyPhrases: ["svickov*", "sirloin in cream*"]),
        FoodTagRule(
            tags: [.dishGulas],
            anyPhrases: ["gulas*", "goulash*"],
            excludePhrases: ["segedin*", "szeged*"] + spiceWords
        ),
        FoodTagRule(tags: [.dishRizek], anyPhrases: ["rizek", "rizk*", "rizeck*", "schnitzel*"]),
        FoodTagRule(tags: [.dishSmazenySyr], anyPhrases: ["smazen* syr*", "smazak*", "fried cheese"]),
        FoodTagRule(
            tags: [.dishKnedliky],
            anyPhrases: ["knedl*", "bread dumpling*", "potato dumpling*"],
            excludePhrases: [
                "ovocn*", "svestkov*", "merunkov*", "jahodov*", "boruvkov*", "tvarohov* knedl*", "fruit*", "plum*",
                "apricot*"
            ]
        ),
        FoodTagRule(tags: [.dishBramboraky], anyPhrases: ["bramborak*", "potato pancake*"]),
        FoodTagRule(tags: [.dishKoprovka], anyPhrases: ["koprovk*", "koprov* omack*", "dill sauce*"]),
        FoodTagRule(tags: [.dishKulajda], anyPhrases: ["kulajd*"]),
        FoodTagRule(tags: [.dishTrdelnik], anyPhrases: ["trdeln*", "chimney cake*"]),
        FoodTagRule(tags: [.dishBuchty], anyPhrases: ["bucht*", "=buchet"]),
        FoodTagRule(tags: [.dishVeproKnedloZelo], anyPhrases: ["=vepro =knedlo zel*", "=veproknedlozelo"]),
        FoodTagRule(
            tags: [.dishTatarak],
            anyPhrases: ["tatarak*", "tatarsk* biftek*", "steak tartar*", "beef tartar*", "=tartare"],
            // Fish tartares are not tatarák (beef).
            excludePhrases: ["omack*", "sauce*", "losos*", "salmon*", "tuna*", "tunak*"]
        ),
        FoodTagRule(tags: [.dishUtopenci], anyPhrases: ["utopen*"]),
        FoodTagRule(tags: [.dishNakladanyHermelin], anyPhrases: ["nakladan* hermelin*", "pickled camembert*"]),
        FoodTagRule(tags: [.dishCesnecka], anyPhrases: ["cesneck*", "cesnekov* polevk*", "garlic soup*"]),
        FoodTagRule(
            tags: [.dishRajska],
            anyPhrases: ["rajsk* omack*", "=rajska", "=rajskou"],
            // Tomato soup ("rajská polévka") and tomatoes ("rajská
            // jablíčka") are not the rajská omáčka dish.
            excludePhrases: ["polevk*", "soup*", "jablic*"]
        ),
        FoodTagRule(
            tags: [.dishOvocneKnedliky],
            anyPhrases: [
                "ovocn* knedl*", "svestkov* knedl*", "merunkov* knedl*", "jahodov* knedl*", "boruvkov* knedl*",
                "tvarohov* knedl*", "fruit dumpling*", "plum dumpling*", "apricot dumpling*"
            ]
        ),
        FoodTagRule(
            tags: [.dishPalacinky],
            anyPhrases: ["palacink*", "crepe*", "=pancake", "=pancakes"],
            excludePhrases: ["potato*", "bramborov*"]
        ),
        FoodTagRule(tags: [.dishChlebicek], anyPhrases: ["chlebic*"]),
        FoodTagRule(tags: [.dishBramboracka], anyPhrases: ["bramborack*", "bramborov* polevk*", "potato soup*"]),
        FoodTagRule(tags: [.dishSegedin], anyPhrases: ["segedin*", "szeged*"]),
        FoodTagRule(tags: [.dishSpanelskyPtacek], anyPhrases: ["spanelsk* ptac*", "=ptacek", "=ptacky"]),
        FoodTagRule(tags: [.dishKolac], anyPhrases: ["kolac*", "kolach*"], excludePhrases: ["frgal*"]),
        FoodTagRule(tags: [.dishFrgal], anyPhrases: ["frgal*"]),
        // A PART of vepřo-knedlo-zelo logged in pieces (stem "zel": zelí,
        // zelím, zelo -- but not zelený/zelenina).
        FoodTagRule(tags: [.dishZeli], anyPhrases: ["zeli", "sauerkraut*", "cabbage*"])
    ]

    static let world: [FoodTagRule] = [
        FoodTagRule(tags: [.dishSushi], anyPhrases: ["sushi*", "=susi", "nigiri*", "=maki", "sashimi*"]),
        // "=ramen" exact: Czech "rameno" (pork shoulder) must not count.
        FoodTagRule(tags: [.dishRamen], anyPhrases: ["=ramen"]),
        FoodTagRule(
            tags: [.dishCurry],
            anyPhrases: ["=curry", "=kari"],
            excludePhrases: spiceWords + ["ketchup*", "kecup*"]
        ),
        FoodTagRule(
            tags: [.dishTikkaMasala],
            anyPhrases: ["tikka*", "masala*"],
            // "Masala chai" is spiced tea, not tikka masala.
            excludePhrases: ["garam*", "chai*", "caj*"] + spiceWords
        ),
        FoodTagRule(tags: [.dishTacos], anyPhrases: ["=taco", "=tacos", "=tako"]),
        FoodTagRule(tags: [.dishBurrito], anyPhrases: ["burrit*"]),
        FoodTagRule(tags: [.dishPho], anyPhrases: ["=pho"]),
        FoodTagRule(tags: [.dishPadThai], anyPhrases: ["=pad =thai", "=padthai"]),
        FoodTagRule(
            tags: [.dishPizza],
            anyPhrases: ["pizz*"],
            excludePhrases: spiceWords + ["omack*", "sauce*"]
        ),
        FoodTagRule(tags: [.dishLasagne], anyPhrases: ["lasagn*", "lazan*"]),
        FoodTagRule(tags: [.dishRisotto], anyPhrases: ["risott*", "rizot*"]),
        FoodTagRule(tags: [.dishGyros], anyPhrases: ["gyros*", "=gyro"], excludePhrases: spiceWords),
        FoodTagRule(tags: [.dishSouvlaki], anyPhrases: ["souvlak*", "suvlak*"]),
        FoodTagRule(tags: [.dishFalafel], anyPhrases: ["falafel*"]),
        FoodTagRule(tags: [.dishHummus], anyPhrases: ["hummus*", "humus*", "hommus*"]),
        FoodTagRule(tags: [.dishKebab], anyPhrases: ["kebab*", "kebap*", "=doner"], excludePhrases: spiceWords),
        FoodTagRule(tags: [.dishPaella], anyPhrases: ["paell*", "paej*"]),
        FoodTagRule(tags: [.dishBibimbap], anyPhrases: ["bibimbap*"]),
        FoodTagRule(
            tags: [.dishDimSum],
            anyPhrases: ["=dim =sum", "=dimsum", "jiaozi*", "gyoz*", "wonton*", "baozi*", "=bao", "dumpling*"],
            excludePhrases: [
                "czech", "potato*", "bread*", "fruit*", "plum*", "apricot*", "strawberr*", "houskov*", "bramborov*"
            ]
        ),
        FoodTagRule(tags: [.dishCroissant], anyPhrases: ["croissant*", "kroasan*", "=croisant"]),
        FoodTagRule(tags: [.dishPierogi], anyPhrases: ["pierog*", "pirog*", "piroh*", "varenyk*"]),
        FoodTagRule(tags: [.dishBorscht], anyPhrases: ["borsc*", "borsch*"])
    ]

    static let fermented: [FoodTagRule] = [
        FoodTagRule(tags: [.dishKefir], anyPhrases: ["kefir*"]),
        // Stem "zeli" (zelí, zelím), not "zel*": "kysaná zelenina" is not
        // sauerkraut.
        FoodTagRule(tags: [.dishKysaneZeli], anyPhrases: ["kysan* zeli", "sauerkraut*"]),
        FoodTagRule(tags: [.dishKimchi], anyPhrases: ["kimchi*", "=kimci", "=kimchee"]),
        FoodTagRule(
            tags: [.dishJogurt],
            anyPhrases: ["jogurt*", "yogurt*", "yoghurt*"],
            excludePhrases: ["cokolad*", "chocolate*", "polev*", "coating*"]
        ),
        FoodTagRule(tags: [.dishKombucha], anyPhrases: ["kombuc*"]),
        FoodTagRule(tags: [.dishMiso], anyPhrases: ["=miso", "misoshiru*"]),
        FoodTagRule(tags: [.dishTempeh], anyPhrases: ["tempeh*", "=tempe"]),
        FoodTagRule(tags: [.dishZakys], anyPhrases: ["zakys*", "acidofil*", "acidophil*"]),
        FoodTagRule(tags: [.dishTvaruzky], anyPhrases: ["tvaruzk*", "olomouck* syr*"]),
        FoodTagRule(
            tags: [.dishKvasaky],
            anyPhrases: ["kvasak*", "kvasen* okurk*", "fermented cucumber*", "fermented pickle*"]
        ),
        FoodTagRule(tags: [.dishKvaskovyChleb], anyPhrases: ["kvaskov*", "sourdough*"])
    ]
}
