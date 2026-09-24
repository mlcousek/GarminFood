// FoodTag+Seasonal.swift
//
// add-seasonal-events design D3: the seasonal food tags the Czech event
// quests match on (koblihy at Masopust, goose at St Martin, carp or řízek
// with potato salad on Štědrý den, lentils on New Year's Day, ...). Declared
// here rather than in the shared `FoodTag.swift` (add-gamification-signals
// D1: each wave-2 change owns its own tags); the phrases that assign them
// live in `FoodTagRules+Seasonal.swift`.
//
// Static names carry a `season` prefix so they can never collide with a tag
// constant another wave-2 change declares in its own extension. Raw values
// use the `season.` namespace; core tags (`egg`, `fish`, `nuts`, `sweets`,
// `colour.green`) are reused by the quests where they already fit.
//
// Depends on: FoodTag. Depended on by: FoodTagRules+Seasonal,
// Gamification's SeasonalEventCatalog.

import Foundation

extension FoodTag {
    public static let seasonalPrefix = "season."

    /// Koblihy, jitrnice, jelito, tlačenka, ovar, prejt, škvarky, prdelačka.
    public static let seasonMasopust = FoodTag("season.masopust")
    /// Šunka, uzené (Easter ham).
    public static let seasonHam = FoodTag("season.ham")
    /// Mazanec or an Easter lamb cake (beránek).
    public static let seasonMazanec = FoodTag("season.mazanec")
    /// The Zelený čtvrtek greens: špenát, kopřivy, zelený salát, ...
    public static let seasonGreenThursday = FoodTag("season.greenThursday")
    public static let seasonStrawberry = FoodTag("season.strawberry")
    /// Klobása, špekáček, steak, grilovaný ..., čevapčiči, grilovací sýr.
    public static let seasonGrill = FoodTag("season.grill")
    /// Houby, hříbky, smaženice, kulajda, žampiony, bedla, hlíva, ...
    public static let seasonMushroom = FoodTag("season.mushroom")
    public static let seasonGoose = FoodTag("season.goose")
    public static let seasonMartinRohlicek = FoodTag("season.martinRohlicek")
    /// Mandarinky, pomeranče, klementinky (Mikuláš).
    public static let seasonCitrus = FoodTag("season.citrus")
    public static let seasonChocolate = FoodTag("season.chocolate")
    /// Vanilkové rohlíčky, linecké, perníčky, vosí hnízda, pracny, kokosky, ...
    public static let seasonCukrovi = FoodTag("season.cukrovi")
    public static let seasonCarp = FoodTag("season.carp")
    public static let seasonPotatoSalad = FoodTag("season.potatoSalad")
    public static let seasonFishSoup = FoodTag("season.fishSoup")
    public static let seasonVanocka = FoodTag("season.vanocka")
    public static let seasonChlebicek = FoodTag("season.chlebicek")
    public static let seasonJednohubky = FoodTag("season.jednohubky")
    public static let seasonLentils = FoodTag("season.lentils")
    /// Dort, zákusek, a celebration cake (name-day bonus).
    public static let seasonCake = FoodTag("season.cake")
    /// Řízek (schnitzel) -- the other Štědrý den tradition.
    public static let seasonRizek = FoodTag("season.rizek")

    /// Every seasonal tag, for tests and diagnostics.
    public static let allSeasonal: [FoodTag] = [
        .seasonMasopust, .seasonHam, .seasonMazanec, .seasonGreenThursday, .seasonStrawberry, .seasonGrill,
        .seasonMushroom, .seasonGoose, .seasonMartinRohlicek, .seasonCitrus, .seasonChocolate, .seasonCukrovi,
        .seasonCarp, .seasonPotatoSalad, .seasonFishSoup, .seasonVanocka, .seasonChlebicek, .seasonJednohubky,
        .seasonLentils, .seasonCake, .seasonRizek
    ]
}
