// FoodTag+Collections.swift
//
// add-food-collections design D1: every collection entry is a tag. A dish
// (`dish.<id>`) or a brand (`brand.<id>`) is "discovered" the first time a
// logged food carries its tag, so the collections feature reuses the one
// matching engine (`FoodTagger`: fold + Czech stemming + golden tests)
// instead of growing a second one. Rainbow entries reuse the core
// `colour.*` tags and are therefore not declared here.
//
// Declared in this change's own file (not `FoodTag.swift`) per the wave
// plan in add-gamification-signals' design ("tags are declared in its own
// `FoodTag+X.swift`"). The raw values are persisted nowhere by this change
// (the collections store keys by entry id), so renaming one is safe.
//
// Depended on by: FoodTagRules+Collections (the rules that assign them),
// Gamification's FoodCollectionCatalog (entry -> tag), CollectionsTaggerTests.

import Foundation

extension FoodTag {
    public static let dishPrefix = "dish."
    public static let brandPrefix = "brand."

    // MARK: Czech Classics

    public static let dishSvickova = FoodTag("dish.svickova")
    public static let dishGulas = FoodTag("dish.gulas")
    public static let dishRizek = FoodTag("dish.rizek")
    public static let dishSmazenySyr = FoodTag("dish.smazeny-syr")
    public static let dishKnedliky = FoodTag("dish.knedliky")
    public static let dishBramboraky = FoodTag("dish.bramboraky")
    public static let dishKoprovka = FoodTag("dish.koprovka")
    public static let dishKulajda = FoodTag("dish.kulajda")
    public static let dishTrdelnik = FoodTag("dish.trdelnik")
    public static let dishBuchty = FoodTag("dish.buchty")
    public static let dishVeproKnedloZelo = FoodTag("dish.vepro-knedlo-zelo")
    public static let dishTatarak = FoodTag("dish.tatarak")
    public static let dishUtopenci = FoodTag("dish.utopenci")
    public static let dishNakladanyHermelin = FoodTag("dish.nakladany-hermelin")
    public static let dishCesnecka = FoodTag("dish.cesnecka")
    public static let dishRajska = FoodTag("dish.rajska")
    public static let dishOvocneKnedliky = FoodTag("dish.ovocne-knedliky")
    public static let dishPalacinky = FoodTag("dish.palacinky")
    public static let dishChlebicek = FoodTag("dish.chlebicek")
    public static let dishBramboracka = FoodTag("dish.bramboracka")
    public static let dishSegedin = FoodTag("dish.segedin")
    public static let dishSpanelskyPtacek = FoodTag("dish.spanelsky-ptacek")
    public static let dishKolac = FoodTag("dish.kolac")
    public static let dishFrgal = FoodTag("dish.frgal")

    /// Sauerkraut / cabbage as a PART of vepřo-knedlo-zelo logged in pieces
    /// (design D2 special rule) -- not a collection entry of its own.
    public static let dishZeli = FoodTag("dish.zeli")

    // MARK: Around the World

    public static let dishSushi = FoodTag("dish.sushi")
    public static let dishRamen = FoodTag("dish.ramen")
    public static let dishCurry = FoodTag("dish.curry")
    public static let dishTikkaMasala = FoodTag("dish.tikka-masala")
    public static let dishTacos = FoodTag("dish.tacos")
    public static let dishBurrito = FoodTag("dish.burrito")
    public static let dishPho = FoodTag("dish.pho")
    public static let dishPadThai = FoodTag("dish.pad-thai")
    public static let dishPizza = FoodTag("dish.pizza")
    public static let dishLasagne = FoodTag("dish.lasagne")
    public static let dishRisotto = FoodTag("dish.risotto")
    public static let dishGyros = FoodTag("dish.gyros")
    public static let dishSouvlaki = FoodTag("dish.souvlaki")
    public static let dishFalafel = FoodTag("dish.falafel")
    public static let dishHummus = FoodTag("dish.hummus")
    public static let dishKebab = FoodTag("dish.kebab")
    public static let dishPaella = FoodTag("dish.paella")
    public static let dishBibimbap = FoodTag("dish.bibimbap")
    public static let dishDimSum = FoodTag("dish.dim-sum")
    public static let dishCroissant = FoodTag("dish.croissant")
    public static let dishPierogi = FoodTag("dish.pierogi")
    public static let dishBorscht = FoodTag("dish.borscht")

    // MARK: Fermented Friends

    public static let dishKefir = FoodTag("dish.kefir")
    public static let dishKysaneZeli = FoodTag("dish.kysane-zeli")
    public static let dishKimchi = FoodTag("dish.kimchi")
    public static let dishJogurt = FoodTag("dish.jogurt")
    public static let dishKombucha = FoodTag("dish.kombucha")
    public static let dishMiso = FoodTag("dish.miso")
    public static let dishTempeh = FoodTag("dish.tempeh")
    public static let dishZakys = FoodTag("dish.zakys")
    public static let dishTvaruzky = FoodTag("dish.tvaruzky")
    public static let dishKvasaky = FoodTag("dish.kvasaky")
    public static let dishKvaskovyChleb = FoodTag("dish.kvaskovy-chleb")

    // MARK: Czech Brands (one per `CzechBrands.names` entry, same order)

    public static let brandMadeta = FoodTag("brand.madeta")
    public static let brandKunin = FoodTag("brand.kunin")
    public static let brandTatra = FoodTag("brand.tatra")
    public static let brandOlma = FoodTag("brand.olma")
    public static let brandHollandia = FoodTag("brand.hollandia")
    public static let brandPilos = FoodTag("brand.pilos")
    public static let brandAlbertQuality = FoodTag("brand.albert-quality")
    public static let brandPenam = FoodTag("brand.penam")
    public static let brandOpavia = FoodTag("brand.opavia")
    public static let brandOrion = FoodTag("brand.orion")
    public static let brandKofola = FoodTag("brand.kofola")
    public static let brandMattoni = FoodTag("brand.mattoni")
    public static let brandRelax = FoodTag("brand.relax")
    public static let brandHame = FoodTag("brand.hame")
    public static let brandVitana = FoodTag("brand.vitana")
    public static let brandJihlavanka = FoodTag("brand.jihlavanka")
    public static let brandKosteleckeUzeniny = FoodTag("brand.kostelecke-uzeniny")
    public static let brandChocenskaMlekarna = FoodTag("brand.chocenska-mlekarna")
    public static let brandPribinacek = FoodTag("brand.pribinacek")
    public static let brandEmco = FoodTag("brand.emco")
    public static let brandBonavita = FoodTag("brand.bonavita")
    public static let brandSemix = FoodTag("brand.semix")

    /// Brand tag -> the `CzechBrands.names` phrase it is matched with, in
    /// list order. One source for the brand rules and their tests.
    public static let czechBrandTags: [(tag: FoodTag, phrase: String)] = [
        (.brandMadeta, "Madeta"), (.brandKunin, "Kunín"), (.brandTatra, "Tatra"), (.brandOlma, "Olma"),
        (.brandHollandia, "Hollandia"), (.brandPilos, "Pilos"), (.brandAlbertQuality, "Albert Quality"),
        (.brandPenam, "Penam"), (.brandOpavia, "Opavia"), (.brandOrion, "Orion"), (.brandKofola, "Kofola"),
        (.brandMattoni, "Mattoni"), (.brandRelax, "Relax"), (.brandHame, "=Hamé"), (.brandVitana, "Vitana"),
        (.brandJihlavanka, "Jihlavanka"), (.brandKosteleckeUzeniny, "Kostelecké uzeniny"),
        (.brandChocenskaMlekarna, "Choceňská mlékárna"), (.brandPribinacek, "Pribináček"), (.brandEmco, "Emco"),
        (.brandBonavita, "Bonavita"), (.brandSemix, "Semix")
    ]
}
