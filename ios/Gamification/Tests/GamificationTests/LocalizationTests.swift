// LocalizationTests.swift
//
// Proves Gamification's localized resources ship and resolve
// (add-localization design.md D3/D9.3), using `AchievementRarity` as the
// Wave 1 smoke string. Translations live in Resources/<lang>.lproj so that
// plain `swift test` can load them (it can't compile .xcstrings catalogs).
// Wave 4 extends this file with a coverage test over the whole achievement/
// challenge catalog.
//
// Czech is looked up through the cs.lproj sub-bundle explicitly, because the
// test process runs in English on CI.

import XCTest
@testable import Gamification

final class LocalizationTests: XCTestCase {
    private func czechBundle() throws -> Bundle {
        let path = try XCTUnwrap(
            Bundle.module.path(forResource: "cs", ofType: "lproj"),
            "cs.lproj missing from Gamification's resource bundle -- check Package.swift's resources/defaultLocalization"
        )
        return try XCTUnwrap(Bundle(path: path))
    }

    func testPackageDeclaresEnglishAndCzech() {
        let localizations = Bundle.module.localizations
        XCTAssertTrue(localizations.contains("en"), "found: \(localizations)")
        XCTAssertTrue(localizations.contains("cs"), "found: \(localizations)")
    }

    func testEveryRarityHasACzechName() throws {
        let czech = try czechBundle()
        let expected: [AchievementRarity: String] = [
            .common: "Běžný",
            .uncommon: "Neobvyklý",
            .rare: "Vzácný",
            .epic: "Epický",
            .legendary: "Legendární",
        ]
        for rarity in AchievementRarity.allCases {
            // `displayName` resolves in the test process's language
            // (English), which is also the key -- keys are English source
            // text (design.md D4).
            let key = rarity.displayName
            XCTAssertEqual(czech.localizedString(forKey: key, value: "<missing>", table: nil), expected[rarity], "\(rarity)")
        }
    }

    func testEnglishNamesAreUnchanged() {
        XCTAssertEqual(AchievementRarity.allCases.map(\.displayName), ["Common", "Uncommon", "Rare", "Epic", "Legendary"])
    }
}
