// SeasonalTaggerTests.swift
//
// add-seasonal-events design D3/D7: golden cases for the seasonal tag rules
// (`FoodTagRules+Seasonal.swift`), with the dangerous neighbours each rule
// must NOT fire on -- kapr/kapary, houby/mycí houba, čočka/cocktail,
// lentils/lentilky, jahody/jahodový jogurt. When the owner reports a
// seasonal mis-tag, add the fixture here first, then fix the rule.

import XCTest
@testable import FoodLogCore

final class SeasonalTaggerTests: XCTestCase {
    private struct Case {
        let name: String
        let mustInclude: Set<FoodTag>
        let mustExclude: Set<FoodTag>
    }

    private static let cases: [Case] = [
        // Masopust
        Case(name: "Koblihy s marmeládou", mustInclude: [.seasonMasopust], mustExclude: []),
        Case(name: "Jitrnice", mustInclude: [.seasonMasopust], mustExclude: []),
        Case(name: "Tlačenka s cibulí", mustInclude: [.seasonMasopust], mustExclude: []),
        Case(name: "Škvarky", mustInclude: [.seasonMasopust], mustExclude: []),
        // Easter
        Case(name: "Šunka od kosti", mustInclude: [.seasonHam], mustExclude: []),
        Case(name: "Uzené maso", mustInclude: [.seasonHam], mustExclude: []),
        Case(name: "Uzený losos", mustInclude: [], mustExclude: [.seasonHam]),
        Case(name: "Vejce natvrdo", mustInclude: [.egg], mustExclude: [.seasonHam]),
        Case(name: "Velikonoční mazanec", mustInclude: [.seasonMazanec], mustExclude: []),
        Case(name: "Beránek", mustInclude: [.seasonMazanec], mustExclude: []),
        Case(name: "Špenát s bramborem", mustInclude: [.seasonGreenThursday], mustExclude: []),
        Case(name: "Kopřivová polévka", mustInclude: [.seasonGreenThursday], mustExclude: []),
        // Summer
        Case(name: "Jahody", mustInclude: [.seasonStrawberry], mustExclude: []),
        Case(name: "Jahodové knedlíky", mustInclude: [.seasonStrawberry], mustExclude: []),
        Case(name: "Jahodový jogurt", mustInclude: [], mustExclude: [.seasonStrawberry]),
        Case(name: "Špekáček", mustInclude: [.seasonGrill], mustExclude: []),
        Case(name: "Grilovaná klobása", mustInclude: [.seasonGrill], mustExclude: []),
        Case(name: "Hovězí steak", mustInclude: [.seasonGrill], mustExclude: []),
        Case(name: "Čevapčiči", mustInclude: [.seasonGrill], mustExclude: []),
        Case(name: "Grilovací hermelín", mustInclude: [.seasonGrill], mustExclude: []),
        // Autumn
        Case(name: "Houbová polévka", mustInclude: [.seasonMushroom], mustExclude: []),
        Case(name: "Houby na smetaně", mustInclude: [.seasonMushroom], mustExclude: []),
        Case(name: "Smaženice", mustInclude: [.seasonMushroom], mustExclude: []),
        Case(name: "Kulajda", mustInclude: [.seasonMushroom], mustExclude: []),
        Case(name: "Žampiony", mustInclude: [.seasonMushroom], mustExclude: []),
        Case(name: "Hříbky sušené", mustInclude: [.seasonMushroom], mustExclude: []),
        Case(name: "Mycí houba", mustInclude: [], mustExclude: [.seasonMushroom]),
        Case(name: "Pečená husa", mustInclude: [.seasonGoose], mustExclude: []),
        Case(name: "Husí stehno se zelím", mustInclude: [.seasonGoose], mustExclude: []),
        Case(name: "Svatomartinský rohlíček", mustInclude: [.seasonMartinRohlicek], mustExclude: [.seasonGoose]),
        // Advent and Christmas
        Case(name: "Mandarinka", mustInclude: [.seasonCitrus], mustExclude: []),
        Case(name: "Pomerančový džus", mustInclude: [], mustExclude: [.seasonCitrus]),
        Case(name: "Hořká čokoláda", mustInclude: [.seasonChocolate], mustExclude: []),
        Case(name: "Vanilkové rohlíčky", mustInclude: [.seasonCukrovi], mustExclude: []),
        Case(name: "Vosí hnízda", mustInclude: [.seasonCukrovi], mustExclude: []),
        Case(name: "Linecké cukroví", mustInclude: [.seasonCukrovi], mustExclude: []),
        Case(name: "Perníčky", mustInclude: [.seasonCukrovi], mustExclude: []),
        Case(name: "Cukr krystal", mustInclude: [], mustExclude: [.seasonCukrovi]),
        Case(name: "Smažený kapr", mustInclude: [.seasonCarp, .fish], mustExclude: []),
        Case(name: "Kapr na kmíně", mustInclude: [.seasonCarp], mustExclude: []),
        Case(name: "Kapary", mustInclude: [], mustExclude: [.seasonCarp, .fish]),
        Case(name: "Bramborový salát s majonézou", mustInclude: [.seasonPotatoSalad], mustExclude: []),
        Case(name: "Bramborový salát", mustInclude: [.seasonPotatoSalad], mustExclude: []),
        Case(name: "Rybí polévka", mustInclude: [.seasonFishSoup], mustExclude: []),
        Case(name: "Vánočka", mustInclude: [.seasonVanocka], mustExclude: []),
        Case(name: "Vepřový řízek", mustInclude: [.seasonRizek], mustExclude: []),
        Case(name: "Kuřecí řízky", mustInclude: [.seasonRizek], mustExclude: []),
        // Silvestr and New Year
        Case(name: "Chlebíček se šunkou", mustInclude: [.seasonChlebicek], mustExclude: []),
        Case(name: "Pražské chlebíčky", mustInclude: [.seasonChlebicek], mustExclude: []),
        Case(name: "Jednohubky", mustInclude: [.seasonJednohubky], mustExclude: []),
        Case(name: "Čočka na kyselo", mustInclude: [.seasonLentils], mustExclude: []),
        Case(name: "Čočková polévka", mustInclude: [.seasonLentils], mustExclude: []),
        Case(name: "Čočkový salát", mustInclude: [.seasonLentils], mustExclude: []),
        Case(name: "Cocktail sauce", mustInclude: [], mustExclude: [.seasonLentils]),
        Case(name: "Lentilky", mustInclude: [], mustExclude: [.seasonLentils]),
        // Celebrations
        Case(name: "Čokoládový dort", mustInclude: [.seasonCake, .seasonChocolate], mustExclude: []),
        Case(name: "Zákusek", mustInclude: [.seasonCake], mustExclude: [])
    ]

    func testSeasonalGoldenCases() {
        for fixture in Self.cases {
            let tags = FoodTagger.tags(name: fixture.name, brand: nil, barcode: nil)
            let missing = fixture.mustInclude.subtracting(tags)
            let unexpected = fixture.mustExclude.intersection(tags)
            XCTAssertTrue(missing.isEmpty, "\(fixture.name): missing \(missing.sorted()) in \(tags.sorted())")
            XCTAssertTrue(unexpected.isEmpty, "\(fixture.name): unexpected \(unexpected.sorted())")
        }
    }

    func testSeasonalRuleSetIsRegisteredAndNonEmpty() {
        XCTAssertEqual(FoodTagRuleSet.seasonal.id, "seasonal")
        XCTAssertFalse(FoodTagRuleSet.seasonal.rules.isEmpty)
        let assigned = FoodTagRuleSet.seasonal.rules.reduce(into: Set<FoodTag>()) { $0.formUnion($1.tags) }
        XCTAssertEqual(assigned, Set(FoodTag.allSeasonal))
    }

    func testSeasonalTagsShareOneNamespace() {
        for tag in FoodTag.allSeasonal {
            XCTAssertTrue(tag.hasPrefix(FoodTag.seasonalPrefix), tag.rawValue)
        }
        XCTAssertEqual(Set(FoodTag.allSeasonal).count, FoodTag.allSeasonal.count)
    }
}
