// CatalogCoverageTests.swift
//
// add-localization task 4.3: every achievement, challenge, daily challenge
// and level tier has a non-empty Czech title (and description), looked up
// through the cs.lproj bundle exactly as a Czech phone would, so a new tier
// added to a Swift ladder without its Czech line fails here instead of
// silently showing English on the owner's phone.
//
// Two lookups, matching how the text is resolved (CatalogL10n.swift):
//   - the generated core catalogs (`AchievementCatalog`, the classic
//     `ChallengeCatalog` families, `DailyChallengeCatalog`, `LevelTiers`)
//     by id in the `Catalog` table ("<id>.title" / "<id>.subtitle");
//   - the hand-written catalogs (signal challenges and every feature's
//     badges) by their English-source key in `Localizable`, or, for food
//     collections, in the `Collections` table.
// Also: no key in Catalog.strings points at an id that no longer exists
// (a renamed tier would otherwise leave a dead translation behind), and a
// few representative sentences are pinned so a grammar regression in the
// generated Czech is visible.

import XCTest
@testable import Gamification

final class CatalogCoverageTests: XCTestCase {
    private let missing = "<missing>"

    private func czechBundle() throws -> Bundle {
        let path = try XCTUnwrap(Bundle.module.path(forResource: "cs", ofType: "lproj"), "cs.lproj missing")
        return try XCTUnwrap(Bundle(path: path))
    }

    private func catalogText(_ key: String, _ bundle: Bundle) -> String {
        bundle.localizedString(forKey: key, value: missing, table: CatalogL10n.table)
    }

    private func assertCzech(_ key: String, _ bundle: Bundle, file: StaticString = #filePath, line: UInt = #line) {
        let text = catalogText(key, bundle)
        XCTAssertNotEqual(text, missing, "no Czech text for \(key) in cs.lproj/Catalog.strings", file: file, line: line)
        XCTAssertFalse(text.trimmingCharacters(in: .whitespaces).isEmpty, "empty Czech text for \(key)", file: file, line: line)
        XCTAssertFalse(text.contains("%"), "Catalog text is final, it takes no format arguments: \(key)", file: file, line: line)
    }

    /// Classic challenge families are in the Catalog table; the signal
    /// challenges (ChallengeTemplates+Signals.swift) use English-source keys.
    private var catalogChallenges: [ChallengeTemplate] { ChallengeCatalog.all.filter { !$0.kind.isSignalBased } }
    private var signalChallenges: [ChallengeTemplate] { ChallengeCatalog.all.filter { $0.kind.isSignalBased } }

    func testEveryAchievementHasCzechTitleAndDescription() throws {
        let czech = try czechBundle()
        XCTAssertFalse(AchievementCatalog.all.isEmpty)
        for definition in AchievementCatalog.all {
            assertCzech("\(definition.id).title", czech)
            assertCzech("\(definition.id).subtitle", czech)
        }
    }

    func testEveryChallengeHasCzechTitleAndDescription() throws {
        let czech = try czechBundle()
        XCTAssertFalse(catalogChallenges.isEmpty)
        for template in catalogChallenges {
            assertCzech("\(template.id).title", czech)
            assertCzech("\(template.id).subtitle", czech)
        }
        XCTAssertFalse(signalChallenges.isEmpty)
        for template in signalChallenges {
            // English process: the title IS the English-source key.
            for key in [template.title, template.subtitle] {
                XCTAssertNotEqual(czech.localizedString(forKey: key, value: missing, table: nil), missing, "\(template.id): no Czech for \(key)")
            }
        }
    }

    func testEveryDailyChallengeHasCzechTitleAndDescription() throws {
        let czech = try czechBundle()
        XCTAssertFalse(DailyChallengeCatalog.all.isEmpty)
        for template in DailyChallengeCatalog.all {
            assertCzech("\(template.id).title", czech)
            assertCzech("\(template.id).subtitle", czech)
        }
    }

    func testEveryLevelTierHasCzechTitleAndFlavor() throws {
        let czech = try czechBundle()
        for tier in LevelTiers.all {
            assertCzech("tier.\(tier.levelRange.lowerBound).title", czech)
            assertCzech("tier.\(tier.levelRange.lowerBound).flavor", czech)
        }
    }

    /// Every badge a feature adds (bingo, boss, journeys, records, seasonal,
    /// secrets, sport & body, collections) has a Czech title.
    func testEveryFeatureBadgeHasCzechTitle() throws {
        let czech = try czechBundle()
        let featureBadges = BadgeRegistry.all.filter { !$0.isCoreCatalogBadge }
        XCTAssertFalse(featureBadges.isEmpty)
        for badge in featureBadges {
            let localizable = czech.localizedString(forKey: badge.title, value: missing, table: nil)
            let collections = czech.localizedString(forKey: "badge.\(badge.id).title", value: missing, table: CollectionsL10n.table)
            XCTAssertTrue(localizable != missing || collections != missing, "\(badge.id): no Czech title for \(badge.title)")
        }
    }

    /// The reverse direction: a Catalog key whose id no longer exists.
    func testCatalogTableHasNoKeysForUnknownIds() throws {
        let czech = try czechBundle()
        let path = try XCTUnwrap(czech.path(forResource: CatalogL10n.table, ofType: "strings"), "cs.lproj/Catalog.strings missing")
        // Keys only (every entry is one `"key" = "value";` line, keys are
        // plain ids without quotes or escapes).
        let contents = try String(contentsOfFile: path, encoding: .utf8)
        let keys = contents.split(whereSeparator: \.isNewline).compactMap { line -> String? in
            guard line.hasPrefix("\""), let end = line.dropFirst().firstIndex(of: "\"") else { return nil }
            return String(line[line.index(after: line.startIndex)..<end])
        }
        XCTAssertEqual(keys.count, Set(keys).count, "duplicate keys in Catalog.strings")
        var known = Set<String>()
        for id in AchievementCatalog.all.map(\.id) + catalogChallenges.map(\.id) + DailyChallengeCatalog.all.map(\.id) {
            known.insert("\(id).title")
            known.insert("\(id).subtitle")
        }
        for tier in LevelTiers.all {
            known.insert("tier.\(tier.levelRange.lowerBound).title")
            known.insert("tier.\(tier.levelRange.lowerBound).flavor")
        }
        XCTAssertEqual(Set(keys).subtracting(known).sorted(), [], "Catalog.strings keys with no catalog id")
        XCTAssertEqual(Set(keys).count, known.count)
    }

    /// Pins the generated Czech grammar: noun forms after a number and the
    /// v/ve preposition, which is why these are written per id.
    func testRepresentativeCzechSentences() throws {
        let czech = try czechBundle()
        let expected: [String: String] = [
            "achv-streak-1.subtitle": "Dosáhni série dlouhé 1 den.",
            "achv-streak-3.subtitle": "Dosáhni série dlouhé 3 dny.",
            "achv-streak-7.subtitle": "Dosáhni série dlouhé 7 dní.",
            "extend-streak-1.subtitle": "Prodluž svou sérii o další den.",
            "extend-streak-2.subtitle": "Prodluž svou sérii o další 2 dny.",
            "extend-streak-5.subtitle": "Prodluž svou sérii o dalších 5 dní.",
            "goal-days-protein-4.subtitle": "Splň cíl bílkovin ve 4 dnech.",
            "goal-days-protein-5.subtitle": "Splň cíl bílkovin v 5 dnech.",
            "goal-days-calories-12.subtitle": "Splň kalorický cíl ve 12 dnech.",
            "new-foods-1.subtitle": "Zapiš jídlo, které v deníku ještě nemáš.",
            "daily-log-1-0.subtitle": "Zapiš dnes aspoň 1 záznam.",
            "daily-log-3-0.subtitle": "Zapiš dnes aspoň 3 záznamy.",
            "daily-log-5-0.subtitle": "Zapiš dnes aspoň 5 záznamů.",
            "tier.1.title": "Nováček",
        ]
        for (key, value) in expected {
            XCTAssertEqual(catalogText(key, czech), value, key)
        }
    }

    /// English is still the Swift source text: an English process never
    /// sees a Catalog key or Czech (no en.lproj/Catalog.strings on purpose).
    func testEnglishTextIsUnchanged() {
        XCTAssertEqual(AchievementCatalog.all.first { $0.id == "achv-streak-7" }?.subtitle, "Reach a 7-day streak.")
        XCTAssertEqual(ChallengeCatalog.all.first { $0.id == "extend-streak-1" }?.subtitle, "Extend your streak by 1 more day.")
        XCTAssertEqual(ChallengeCatalog.all.first { $0.id == "extend-streak-2" }?.subtitle, "Extend your streak by 2 more days.")
        XCTAssertEqual(DailyChallengeCatalog.all.first { $0.id == "daily-log-1-0" }?.subtitle, "Log at least 1 entry today.")
        XCTAssertEqual(ChallengeCatalog.all.first { $0.id == "goal-days-protein-7" }?.title, "Protein Steady")
        XCTAssertEqual(GoalMacro.allCases.map(\.displayName), ["Calories", "Protein", "Carbs", "Fat"])
    }
}
