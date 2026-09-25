// CollectionsTaggerTests.swift
//
// add-food-collections design D6: the golden suite for the collection tag
// rules (`FoodTagRules+Collections.swift`). Every dish and brand entry has
// at least one positive fixture; the risky ones (spice mixes, sauces, fruit
// vs. bread dumplings, pork shoulder vs. ramen, tartar sauce vs. tatarák,
// brand-in-name vs. brand) also have a negative one. Like FoodTaggerTests,
// fixtures assert what MUST and MUST NOT be present, not the exact set.
//
// When the owner reports a missed or wrong discovery: add the fixture here.

import XCTest
@testable import FoodLogCore

final class CollectionsTaggerTests: XCTestCase {
    private struct Fixture {
        let name: String
        var brand: String?
        let mustInclude: Set<FoodTag>
        var mustExclude: Set<FoodTag> = []
    }

    private static let dishFixtures: [Fixture] = [
        // Czech Classics
        Fixture(name: "Svíčková na smetaně s knedlíkem", mustInclude: [.dishSvickova, .dishKnedliky]),
        Fixture(name: "Gulášová polévka", mustInclude: [.dishGulas]),
        Fixture(name: "Hovězí guláš", mustInclude: [.dishGulas]),
        Fixture(name: "Segedínský guláš", mustInclude: [.dishSegedin], mustExclude: [.dishGulas]),
        Fixture(name: "Guláš koření", mustInclude: [], mustExclude: [.dishGulas]),
        Fixture(name: "Kuřecí řízek", mustInclude: [.dishRizek]),
        Fixture(name: "Wiener Schnitzel", mustInclude: [.dishRizek]),
        Fixture(name: "Rizoto s houbami", mustInclude: [.dishRisotto], mustExclude: [.dishRizek]),
        Fixture(name: "Smažený sýr s hranolky", mustInclude: [.dishSmazenySyr]),
        Fixture(name: "Houskový knedlík", mustInclude: [.dishKnedliky], mustExclude: [.dishOvocneKnedliky, .dishDimSum]),
        Fixture(name: "Bramborové knedlíky", mustInclude: [.dishKnedliky]),
        Fixture(name: "Bramboráky", mustInclude: [.dishBramboraky], mustExclude: [.dishBramboracka]),
        Fixture(name: "Koprová omáčka s vejcem", mustInclude: [.dishKoprovka]),
        Fixture(name: "Kulajda", mustInclude: [.dishKulajda]),
        Fixture(name: "Trdelník s nutellou", mustInclude: [.dishTrdelnik]),
        Fixture(name: "Buchty s povidly", mustInclude: [.dishBuchty]),
        Fixture(name: "Vepřo knedlo zelo", mustInclude: [.dishVeproKnedloZelo]),
        Fixture(name: "Vepřo-knedlo-zelo", mustInclude: [.dishVeproKnedloZelo]),
        Fixture(name: "Tatarák s topinkami", mustInclude: [.dishTatarak]),
        Fixture(name: "Tatarská omáčka", mustInclude: [], mustExclude: [.dishTatarak]),
        Fixture(name: "Tartar sauce", mustInclude: [], mustExclude: [.dishTatarak]),
        Fixture(name: "Utopenci", mustInclude: [.dishUtopenci]),
        Fixture(name: "Nakládaný hermelín", mustInclude: [.dishNakladanyHermelin]),
        Fixture(name: "Česnečka se sýrem", mustInclude: [.dishCesnecka]),
        Fixture(name: "Rajská omáčka s knedlíkem", mustInclude: [.dishRajska]),
        Fixture(name: "Rajská polévka", mustInclude: [], mustExclude: [.dishRajska]),
        Fixture(name: "Rajská jablíčka", mustInclude: [], mustExclude: [.dishRajska]),
        Fixture(name: "Beef tartare", mustInclude: [.dishTatarak]),
        Fixture(name: "Salmon tartare", mustInclude: [], mustExclude: [.dishTatarak]),
        Fixture(name: "Tuňákový tartare", mustInclude: [], mustExclude: [.dishTatarak]),
        Fixture(name: "Švestkové knedlíky", mustInclude: [.dishOvocneKnedliky], mustExclude: [.dishKnedliky]),
        Fixture(name: "Ovocné knedlíky jahodové", mustInclude: [.dishOvocneKnedliky], mustExclude: [.dishKnedliky]),
        Fixture(name: "Palačinky s marmeládou", mustInclude: [.dishPalacinky]),
        Fixture(name: "Potato pancakes", mustInclude: [.dishBramboraky], mustExclude: [.dishPalacinky]),
        Fixture(name: "Chlebíček s vlašákem", mustInclude: [.dishChlebicek]),
        Fixture(name: "Bramboračka", mustInclude: [.dishBramboracka], mustExclude: [.dishBramboraky]),
        Fixture(name: "Španělský ptáček s rýží", mustInclude: [.dishSpanelskyPtacek]),
        Fixture(name: "Tvarohový koláč", mustInclude: [.dishKolac]),
        Fixture(name: "Valašský frgál hruškový", mustInclude: [.dishFrgal], mustExclude: [.dishKolac]),
        Fixture(name: "Dušené zelí", mustInclude: [.dishZeli]),
        Fixture(name: "Zelený čaj", mustInclude: [], mustExclude: [.dishZeli]),
        Fixture(name: "Zeleninový salát", mustInclude: [], mustExclude: [.dishZeli]),
        // Around the World
        Fixture(name: "Sushi maki losos", mustInclude: [.dishSushi]),
        Fixture(name: "Ramen s vepřovým", mustInclude: [.dishRamen]),
        Fixture(name: "Vepřové rameno", mustInclude: [], mustExclude: [.dishRamen]),
        Fixture(name: "Kuřecí kari s rýží", mustInclude: [.dishCurry]),
        Fixture(name: "Kari koření", mustInclude: [], mustExclude: [.dishCurry]),
        Fixture(name: "Chicken tikka masala", mustInclude: [.dishTikkaMasala]),
        Fixture(name: "Garam masala koření", mustInclude: [], mustExclude: [.dishTikkaMasala]),
        Fixture(name: "Tacos s hovězím", mustInclude: [.dishTacos]),
        Fixture(name: "Burrito bowl", mustInclude: [.dishBurrito]),
        Fixture(name: "Phở bò", mustInclude: [.dishPho]),
        Fixture(name: "Pad Thai s krevetami", mustInclude: [.dishPadThai]),
        Fixture(name: "Pizza Margherita", mustInclude: [.dishPizza]),
        Fixture(name: "Pizza ochucovadlo", mustInclude: [], mustExclude: [.dishPizza]),
        Fixture(name: "Lasagne bolognese", mustInclude: [.dishLasagne]),
        Fixture(name: "Houbové rizoto", mustInclude: [.dishRisotto]),
        Fixture(name: "Gyros pita", mustInclude: [.dishGyros]),
        Fixture(name: "Souvlaki", mustInclude: [.dishSouvlaki]),
        Fixture(name: "Falafel wrap", mustInclude: [.dishFalafel]),
        Fixture(name: "Cizrnový hummus", mustInclude: [.dishHummus]),
        Fixture(name: "Döner kebab", mustInclude: [.dishKebab]),
        Fixture(name: "Paella s mořskými plody", mustInclude: [.dishPaella]),
        Fixture(name: "Bibimbap", mustInclude: [.dishBibimbap]),
        Fixture(name: "Dim sum", mustInclude: [.dishDimSum]),
        Fixture(name: "Gyoza s vepřovým", mustInclude: [.dishDimSum]),
        Fixture(name: "Potato dumplings", mustInclude: [.dishKnedliky], mustExclude: [.dishDimSum]),
        Fixture(name: "Máslový croissant", mustInclude: [.dishCroissant]),
        Fixture(name: "Pierogi ruskie", mustInclude: [.dishPierogi]),
        Fixture(name: "Boršč", mustInclude: [.dishBorscht]),
        Fixture(name: "Borscht", mustInclude: [.dishBorscht]),
        // Fermented Friends
        Fixture(name: "Kefírové mléko", mustInclude: [.dishKefir]),
        Fixture(name: "Kysané zelí", mustInclude: [.dishKysaneZeli, .dishZeli]),
        Fixture(name: "Kimchi", mustInclude: [.dishKimchi]),
        Fixture(name: "Bílý jogurt", mustInclude: [.dishJogurt]),
        Fixture(name: "Mléčná čokoláda s jogurtovou náplní", mustInclude: [], mustExclude: [.dishJogurt]),
        Fixture(name: "Kombucha zázvor", mustInclude: [.dishKombucha]),
        Fixture(name: "Miso polévka", mustInclude: [.dishMiso]),
        Fixture(name: "Tempeh uzený", mustInclude: [.dishTempeh]),
        Fixture(name: "Acidofilní mléko", mustInclude: [.dishZakys]),
        Fixture(name: "Zákys", mustInclude: [.dishZakys]),
        Fixture(name: "Olomoucké tvarůžky", mustInclude: [.dishTvaruzky]),
        Fixture(name: "Kvašáky", mustInclude: [.dishKvasaky]),
        Fixture(name: "Kváskový chléb", mustInclude: [.dishKvaskovyChleb])
    ]

    func testDishFixtures() {
        for fixture in Self.dishFixtures {
            assert(fixture)
        }
    }

    func testEveryDishTagHasAPositiveFixture() {
        let covered = Self.dishFixtures.reduce(into: Set<FoodTag>()) { $0.formUnion($1.mustInclude) }
        let declared = CollectionTagRules.dishes.reduce(into: Set<FoodTag>()) { $0.formUnion($1.tags) }
        XCTAssertEqual(declared.subtracting(covered).sorted(), [])
        XCTAssertEqual(declared.count, 24 + 22 + 11 + 1) // + dish.zeli (a part, not an entry)
    }

    func testEveryCzechBrandMatchesByBrandText() {
        XCTAssertEqual(FoodTag.czechBrandTags.count, CzechBrands.names.count)
        XCTAssertEqual(FoodTag.czechBrandTags.map(\.phrase), CzechBrands.names)
        for pair in FoodTag.czechBrandTags {
            let display = pair.phrase.hasPrefix("=") ? String(pair.phrase.dropFirst()) : pair.phrase
            let tags = FoodTagger.tags(name: "Výrobek", brand: display, barcode: nil)
            XCTAssertTrue(tags.contains(pair.tag), "\(display) -> \(tags.sorted())")
            XCTAssertTrue(tags.contains(.czechBrand), display)
        }
    }

    func testBrandMatchedByBrandNotName() {
        let madeta = FoodTagger.tags(name: "Tvaroh", brand: "Madeta", barcode: nil)
        XCTAssertTrue(madeta.contains(.brandMadeta))
        let hollandia = FoodTagger.tags(name: "Selský jogurt", brand: "Hollandia", barcode: nil)
        XCTAssertTrue(hollandia.contains(.brandHollandia))
        let inName = FoodTagger.tags(name: "Jogurt s příchutí Kofoly", brand: nil, barcode: nil)
        XCTAssertFalse(inName.contains(.brandKofola))
        let otherBrand = FoodTagger.tags(name: "Kofola", brand: "Pepsi", barcode: nil)
        XCTAssertFalse(otherBrand.contains(.brandKofola))
    }

    func testHameIsNotHam() {
        XCTAssertFalse(FoodTagger.tags(name: "Ham", brand: "Ham", barcode: nil).contains(.brandHame))
        XCTAssertTrue(FoodTagger.tags(name: "Paštika", brand: "Hamé", barcode: nil).contains(.brandHame))
    }

    func testVeproKnedloZeloPartsAreTagged() {
        XCTAssertTrue(FoodTagger.tags(name: "Vepřová pečeně", brand: nil, barcode: nil).contains(.meat))
        XCTAssertTrue(FoodTagger.tags(name: "Houskový knedlík", brand: nil, barcode: nil).contains(.knedlik))
        XCTAssertTrue(FoodTagger.tags(name: "Dušené zelí", brand: nil, barcode: nil).contains(.dishZeli))
    }

    private func assert(_ fixture: Fixture, file: StaticString = #filePath, line: UInt = #line) {
        let tags = FoodTagger.tags(name: fixture.name, brand: fixture.brand, barcode: nil)
        let missing = fixture.mustInclude.subtracting(tags)
        let unexpected = fixture.mustExclude.intersection(tags)
        XCTAssertTrue(missing.isEmpty, "\(fixture.name): missing \(missing.sorted()) in \(tags.sorted())", file: file, line: line)
        XCTAssertTrue(unexpected.isEmpty, "\(fixture.name): unexpected \(unexpected.sorted())", file: file, line: line)
    }
}
