// CollectionsL10nTests.swift
//
// add-food-collections: the `Collections.strings` table (en + cs) covers
// every catalog entry (name + riddle hint), collection, badge and UI/moment
// key, and each Czech format string keeps the English specifiers. This is
// the job tools/check-localizations.mjs does for `Localizable.strings`,
// which does not look at this separate table (see FoodCollectionCatalog's
// header for why the table exists).

import XCTest
@testable import Gamification

final class CollectionsL10nTests: XCTestCase {
    private static let fixedKeys = [
        "moment.backfill.title", "moment.backfill.message", "moment.single.title", "moment.multi.title",
        "summary.title", "summary.subtitle",
        "ui.title", "ui.intro", "ui.undiscovered", "ui.hint", "ui.foundOn", "ui.foundWith",
        "ui.a11yUndiscovered", "ui.a11yDiscovered", "ui.a11yCollection", "ui.brandsExplored",
        "ui.rainbowDays", "ui.done", "ui.slotHint", "ui.empty",
    ]

    private func bundle(_ language: String) throws -> Bundle {
        let path = try XCTUnwrap(Bundle.module.path(forResource: language, ofType: "lproj"), "\(language).lproj missing")
        return try XCTUnwrap(Bundle(path: path))
    }

    private var requiredKeys: [String] {
        var keys = Self.fixedKeys
        for collection in FoodCollectionCatalog.all {
            keys += ["collection.\(collection.id).title", "collection.\(collection.id).subtitle"]
        }
        for entry in FoodCollectionCatalog.allEntries {
            keys += ["entry.\(entry.id).name", "entry.\(entry.id).hint"]
        }
        for badge in CollectionsBadges.all() {
            keys += ["badge.\(badge.id).title", "badge.\(badge.id).subtitle"]
        }
        return keys
    }

    private func specifiers(_ text: String) -> [String] {
        let pattern = try? NSRegularExpression(pattern: "%(\\d+\\$)?(lld|ld|d|@)")
        let range = NSRange(text.startIndex..., in: text)
        return (pattern?.matches(in: text, range: range) ?? []).compactMap { match in
            Range(match.range, in: text).map { String(text[$0]) }
        }
    }

    func testEveryKeyIsTranslatedInEnglishAndCzech() throws {
        let english = try bundle("en")
        let czech = try bundle("cs")
        for key in requiredKeys {
            let en = english.localizedString(forKey: key, value: "<missing>", table: CollectionsL10n.table)
            let cs = czech.localizedString(forKey: key, value: "<missing>", table: CollectionsL10n.table)
            XCTAssertNotEqual(en, "<missing>", "en: \(key)")
            XCTAssertNotEqual(cs, "<missing>", "cs: \(key)")
            XCTAssertFalse(en.isEmpty, "en: \(key)")
            XCTAssertFalse(cs.isEmpty, "cs: \(key)")
            XCTAssertEqual(specifiers(en), specifiers(cs), "format specifiers differ: \(key)")
        }
    }

    func testHintsAreShort() throws {
        let english = try bundle("en")
        for entry in FoodCollectionCatalog.allEntries {
            let hint = english.localizedString(forKey: "entry.\(entry.id).hint", value: "", table: CollectionsL10n.table)
            XCTAssertLessThanOrEqual(hint.count, 110, "hint too long: \(entry.id)")
        }
    }
}
