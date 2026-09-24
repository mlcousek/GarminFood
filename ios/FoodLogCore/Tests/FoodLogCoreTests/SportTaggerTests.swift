// SportTaggerTests.swift
//
// add-sport-and-body-achievements design D3 / tasks 1.2: golden cases for
// `sport.carbRich` (`FoodTagRules+Sport.swift`), including the neighbours it
// must NOT fire on -- a rice drink (milk substitute), a banana yoghurt, wild
// garlic ("medvědí" is not "med"), Ryzlink (wine, not rice). When the owner
// reports a mis-tag, add the fixture here first, then fix the rule.

import XCTest
@testable import FoodLogCore

final class SportTaggerTests: XCTestCase {
    private static let carbRich: [String] = [
        "Banán",
        "Banány",
        "Ovesná kaše",
        "Ovesné vločky",
        "Energetický gel",
        "Rohlík tukový",
        "Chléb kváskový",
        "Těstoviny vařené",
        "Špagety",
        "Rýže basmati",
        "Müsli s ořechy",
        "Iontový nápoj",
        "Datle",
        "Med",
        "Energy bar"
    ]

    private static let notCarbRich: [String] = [
        "Rýžový nápoj",
        "Banánový jogurt",
        "Ovesné mléko",
        "Medvědí česnek",
        "Ryzlink rýnský",
        "Kuřecí prsa",
        "Vepřový řízek"
    ]

    func testCarbRichGoldenCases() {
        for name in Self.carbRich {
            let tags = FoodTagger.tags(name: name, brand: nil, barcode: nil)
            XCTAssertTrue(tags.contains(.sportCarbRich), "\(name): expected sport.carbRich in \(tags.sorted())")
        }
    }

    func testExclusionsAndNeighboursAreNotCarbRich() {
        for name in Self.notCarbRich {
            let tags = FoodTagger.tags(name: name, brand: nil, barcode: nil)
            XCTAssertFalse(tags.contains(.sportCarbRich), "\(name): unexpected sport.carbRich in \(tags.sorted())")
        }
    }

    func testSportRuleSetIsRegisteredAndOnlyAssignsSportTags() {
        XCTAssertEqual(FoodTagRuleSet.sport.id, "sport")
        XCTAssertFalse(FoodTagRuleSet.sport.rules.isEmpty)
        let assigned = FoodTagRuleSet.sport.rules.reduce(into: Set<FoodTag>()) { $0.formUnion($1.tags) }
        XCTAssertEqual(assigned, Set(FoodTag.allSport))
        for tag in FoodTag.allSport {
            XCTAssertTrue(tag.hasPrefix(FoodTag.sportPrefix), tag.rawValue)
        }
    }
}
