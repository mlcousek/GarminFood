// CollectionsBadges.swift
//
// add-food-collections design D4: every badge the collections feature can
// unlock, as static `AchievementDefinition`s (`featureId: "collections"`,
// `condition: .featureEvaluated`, rarity stated explicitly because there is
// no condition to derive it from):
//   - `collection.<collectionId>.<25|50|100>` per collection (common / rare /
//     epic; Rainbow has 50 % and 100 % only -- see `badgePercents`);
//   - `collection.rainbow-day` / `collection.rainbow-day-10` (rare / epic);
//   - `collection.brand-explorer-10|25|50` (uncommon / rare / epic);
//   - `collection.pokedex-50|100` across all entries (epic / legendary).
// Ids are persisted by `AchievementStore`, so never rename one. Titles come
// from the `Collections.strings` table as `badge.<id>.title|subtitle`.
//
// Depends on: FoodCollectionCatalog, CollectionsL10n, AchievementDefinition.
// Depended on by: CollectionsEvaluator (ids), FoodCollectionsFeature
// (`badges`), CollectionsBadgesTests.

import Foundation

public enum CollectionsBadges {
    public static let rainbowDayThresholds = [1, 10]
    public static let brandExplorerThresholds = [10, 25, 50]
    public static let pokedexPercents = [50, 100]

    public static func completionId(collectionId: String, percent: Int) -> String {
        "collection.\(collectionId).\(percent)"
    }

    public static func rainbowDayId(_ threshold: Int) -> String {
        threshold <= 1 ? "collection.rainbow-day" : "collection.rainbow-day-\(threshold)"
    }

    public static func brandExplorerId(_ threshold: Int) -> String {
        "collection.brand-explorer-\(threshold)"
    }

    public static func pokedexId(_ percent: Int) -> String {
        "collection.pokedex-\(percent)"
    }

    static func completionRarity(percent: Int) -> AchievementRarity {
        switch percent {
        case ..<50: return .common
        case 50..<100: return .rare
        default: return .epic
        }
    }

    static func brandExplorerRarity(_ threshold: Int) -> AchievementRarity {
        switch threshold {
        case ..<25: return .uncommon
        case 25..<50: return .rare
        default: return .epic
        }
    }

    /// Every collections badge, in display order.
    public static func all(collections: [FoodCollection] = FoodCollectionCatalog.all) -> [AchievementDefinition] {
        var result: [AchievementDefinition] = []
        for collection in collections {
            for percent in collection.badgePercents {
                result.append(definition(
                    id: completionId(collectionId: collection.id, percent: percent),
                    symbol: collection.symbol,
                    rarity: completionRarity(percent: percent)
                ))
            }
        }
        for threshold in rainbowDayThresholds {
            result.append(definition(
                id: rainbowDayId(threshold),
                symbol: "rainbow",
                rarity: threshold <= 1 ? .rare : .epic
            ))
        }
        for threshold in brandExplorerThresholds {
            result.append(definition(
                id: brandExplorerId(threshold),
                symbol: "cart.badge.plus",
                rarity: brandExplorerRarity(threshold)
            ))
        }
        for percent in pokedexPercents {
            result.append(definition(
                id: pokedexId(percent),
                symbol: percent >= 100 ? "crown.fill" : "books.vertical.fill",
                rarity: percent >= 100 ? .legendary : .epic
            ))
        }
        return result
    }

    private static func definition(id: String, symbol: String, rarity: AchievementRarity) -> AchievementDefinition {
        AchievementDefinition(
            id: id,
            title: CollectionsL10n.string("badge.\(id).title"),
            subtitle: CollectionsL10n.string("badge.\(id).subtitle"),
            category: .variety,
            badgeSymbol: symbol,
            condition: .featureEvaluated,
            rarityOverride: rarity,
            featureId: FoodCollectionsFeature.id
        )
    }
}

/// Finished, localized strings for the app's collections screens (the
/// `Collections` table is internal to the package).
public enum CollectionsText {
    public static var title: String { CollectionsL10n.string("ui.title") }
    public static var intro: String { CollectionsL10n.string("ui.intro") }
    public static var undiscovered: String { CollectionsL10n.string("ui.undiscovered") }
    public static var hint: String { CollectionsL10n.string("ui.hint") }
    public static var done: String { CollectionsL10n.string("ui.done") }
    public static var slotHint: String { CollectionsL10n.string("ui.slotHint") }
    public static var empty: String { CollectionsL10n.string("ui.empty") }

    /// "Found on 12 September" -- `dateText` already formatted.
    public static func foundOn(_ dateText: String) -> String {
        CollectionsL10n.format("ui.foundOn", dateText)
    }

    public static func foundWith(_ foodName: String) -> String {
        CollectionsL10n.format("ui.foundWith", foodName)
    }

    public static func a11yUndiscovered(hint: String) -> String {
        CollectionsL10n.format("ui.a11yUndiscovered", hint)
    }

    public static func a11yDiscovered(name: String) -> String {
        CollectionsL10n.format("ui.a11yDiscovered", name)
    }

    public static func a11yCollection(title: String, found: Int, total: Int) -> String {
        CollectionsL10n.format("ui.a11yCollection", title, found, total)
    }

    public static func brandsExplored(_ count: Int) -> String {
        CollectionsL10n.format("ui.brandsExplored", count)
    }

    public static func rainbowDays(_ count: Int) -> String {
        CollectionsL10n.format("ui.rainbowDays", count)
    }

    public static func progress(found: Int, total: Int) -> String {
        CollectionsL10n.format("summary.subtitle", found, total)
    }
}
