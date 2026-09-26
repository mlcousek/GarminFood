import Foundation

// CatalogL10n.swift
//
// add-localization Wave 4 (task 4.1): how the generated core catalogs --
// `AchievementCatalog`, `ChallengeCatalog` (its classic families),
// `DailyChallengeCatalog` and `LevelTiers` -- get their Czech text.
//
// WHY PER-ID KEYS, NOT ENGLISH-SOURCE KEYS (design.md D4 allows semantic
// keys "only where one English string needs two Czech ones"): these
// catalogs are generated from (count, title) ladders, and their English
// subtitles insert a number and a macro/meal-slot name ("Hit your protein
// goal on 7 days."). Czech can't be assembled that way (D5): the noun after
// a number changes form (1 den / 2 dny / 5 dní), the preposition changes
// with the spoken number ("ve 3 dnech" / "v 5 dnech" / "ve 12 dnech"), and
// every macro and meal slot has its own case ending. Since every template's
// number is FIXED per id, the Czech is written out once per id, already in
// the right form, in `Resources/cs.lproj/Catalog.strings`:
//
//     "achv-streak-7.title" = "Silný týden";
//     "achv-streak-7.subtitle" = "Dosáhni série dlouhé 7 dní.";
//     "tier.1.title" = "Nováček";            // LevelTier, keyed by its first level
//
// Ids are what the stores persist (D6), so they are stable keys by
// construction; the text is resolved at render time (these catalogs are
// built on first access in the running process's language).
//
// English stays in the Swift tables (the `english` fallback below), so the
// catalogs still read as plain data here and every existing English string
// is byte-for-byte unchanged. There is deliberately no en.lproj/Catalog.strings:
// with English in code a second English copy could only drift. A phone in
// English (or any language other than Czech) looks the key up in
// en.lproj, finds no Catalog table, and gets the `english` value.
//
// `CatalogCoverageTests` fails when an id has no Czech title/subtitle, and
// when Catalog.strings has a key for an id that no longer exists -- add the
// Czech line there whenever a family gains a tier.
//
// The hand-written catalogs (signal challenges, secrets, seasonal, bingo,
// boss, journeys, records, sport & body) use `String(localized:bundle:)`
// with English-source keys instead: they have no count ladders. Collections
// has its own `Collections` table (`CollectionsL10n`).
//
// Depends on: nothing. Depended on by: Achievements.swift,
// ChallengeTemplates.swift, DailyChallenges.swift, LevelTier.swift.
enum CatalogL10n {
    static let table = "Catalog"

    static func title(_ id: String, _ english: String) -> String {
        text("\(id).title", english: english)
    }

    static func subtitle(_ id: String, _ english: String) -> String {
        text("\(id).subtitle", english: english)
    }

    static func text(_ key: String, english: String) -> String {
        Bundle.module.localizedString(forKey: key, value: english, table: table)
    }

    /// The ENGLISH fallback's singular/plural pick ("1 more day" / "3 more
    /// days"). English has exactly these two forms; every other language
    /// gets its sentence per id from the Catalog table above, already in
    /// the right plural form, so this never builds non-English text.
    static func englishCount(_ count: Int, one: String, other: String) -> String {
        switch count {
        case 1: return one
        default: return other
        }
    }
}
