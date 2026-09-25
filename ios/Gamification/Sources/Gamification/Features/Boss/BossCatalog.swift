// BossCatalog.swift
//
// add-weekly-boss-and-streak-freezes design D1: the ten weekly-boss
// archetypes, one per habit the owner can be weakest at, plus the boss and
// freeze badges. Each archetype names
//   - `goodDay`: when a day of the fight is a hit (a shared `DayPredicate`,
//     so the rule means exactly what the same rule means in bingo), and
//   - `isConsidered`: which days count toward its adherence at all (a
//     feature-local filter over `DaySignals`, per the foundation's "wave-2
//     changes must not add DayPredicate cases" rule) -- e.g. water adherence
//     is measured only over days with water data, so missing data never
//     reads as a weak habit.
// `requirement` is the data source the archetype needs before it can be
// chosen at all (`DataRequirement`).
//
// Names are Czech-flavoured: in Czech they are the Czech names from the
// design ("Snídaňový skřet"), in English their English twins. All display
// text is localized here (`bundle: .module`), nothing is persisted.
//
// Depends on: DayPredicate, SignalEvaluator, FoodLogCore (DaySignals,
// FoodTag), AchievementDefinition.
// Depended on by: BossPicker, BossFight, WeeklyBossFeature, the app's boss
// screens (names, symbols, lines).

import Foundation
import FoodLogCore

/// The ten boss archetypes; the raw value is the persisted id.
public enum BossKind: String, Sendable, Equatable, Hashable, Codable, CaseIterable {
    case breakfastGoblin = "breakfast-goblin"
    case desertDragon = "desert-dragon"
    case beigeBeast = "beige-beast"
    case proteinPoltergeist = "protein-poltergeist"
    case calorieKraken = "calorie-kraken"
    case midnightMuncher = "midnight-muncher"
    case sodaLich = "soda-lich"
    case fibrePhantom = "fibre-phantom"
    case scurvyPirate = "scurvy-pirate"
    case forgetfulGhost = "forgetful-ghost"
}

/// One archetype's static facts plus its localized text.
public struct BossArchetype: Sendable, Equatable, Identifiable {
    public let kind: BossKind
    public let name: String
    public let flavour: String
    /// Imperative habit line: "Log breakfast".
    public let goal: String
    public let symbol: String
    public let requirement: DataRequirement
    /// Midnight muncher / soda lich: an evening entry could still spoil
    /// today, so only completed days count (design D3).
    public let judgesCompletedDaysOnly: Bool
    public let goodDay: DayPredicate

    public var id: String { kind.rawValue }

    /// "Breakfast: 42 % of logged days" -- why this boss was chosen.
    public func adherenceLine(percent: String) -> String {
        switch kind {
        case .breakfastGoblin:
            return String(localized: "Breakfast: \(percent) of logged days", bundle: .module, comment: "Why this boss: share of logged days with breakfast. The value is a percentage like 42 %.")
        case .desertDragon:
            return String(localized: "Water goal: \(percent) of days with water data", bundle: .module, comment: "Why this boss: share of days the water goal was met. The value is a percentage.")
        case .beigeBeast:
            return String(localized: "Two vegetables: \(percent) of logged days", bundle: .module, comment: "Why this boss: share of logged days with at least two vegetable entries. The value is a percentage.")
        case .proteinPoltergeist:
            return String(localized: "Protein goal: \(percent) of days", bundle: .module, comment: "Why this boss: share of days the protein goal was met. The value is a percentage.")
        case .calorieKraken:
            return String(localized: "Calorie goal: \(percent) of days", bundle: .module, comment: "Why this boss: share of days the calorie goal was met. The value is a percentage.")
        case .midnightMuncher:
            return String(localized: "Nothing after 21:00: \(percent) of logged days", bundle: .module, comment: "Why this boss: share of logged days with no entry at or after 21:00. The value is a percentage.")
        case .sodaLich:
            return String(localized: "No sugary drink: \(percent) of logged days", bundle: .module, comment: "Why this boss: share of logged days without a sugary drink. The value is a percentage.")
        case .fibrePhantom:
            return String(localized: "25 g fibre: \(percent) of days with nutrients", bundle: .module, comment: "Why this boss: share of days with at least 25 g fibre. The value is a percentage.")
        case .scurvyPirate:
            return String(localized: "Fruit: \(percent) of logged days", bundle: .module, comment: "Why this boss: share of logged days with fruit. The value is a percentage.")
        case .forgetfulGhost:
            return String(localized: "Logged: \(percent) of the last 28 days", bundle: .module, comment: "Why this boss: share of the last 28 days with any entry. The value is a percentage.")
        }
    }

    /// Design D1's "considered days" filter: whether `day` counts toward
    /// this archetype's adherence. Days with no data at all are absent from
    /// the snapshot and only the forgetful ghost counts those (as misses).
    public func isConsidered(_ day: DaySignals) -> Bool {
        switch kind {
        case .breakfastGoblin, .beigeBeast, .midnightMuncher, .scurvyPirate:
            return day.hasEntries
        case .desertDragon:
            return day.availability.hasWater && day.waterML != nil && (day.waterGoalML ?? 0) > 0
        case .proteinPoltergeist, .calorieKraken:
            return day.goalStatus != nil
        case .sodaLich:
            return day.entries.count >= 2
        case .fibrePhantom:
            return day.hasEntries && day.totals.fiber != nil
        case .forgetfulGhost:
            return true
        }
    }

    /// A considered day on which the habit was met.
    public func isGood(_ day: DaySignals, history: SignalsSnapshot, calendar: Calendar) -> Bool {
        isConsidered(day) && SignalEvaluator.holds(goodDay, on: day, history: history, calendar: calendar)
    }
}

public enum BossCatalog {
    /// Coverage rule (design D2): an archetype needs at least this many
    /// considered days out of the 28 to be chosen.
    public static let minimumConsideredDays = 14
    /// Fewer logged days than this in the window = a new user: the ghost.
    public static let newUserLoggedDays = 7

    public static var all: [BossArchetype] { BossKind.allCases.map(archetype) }

    public static func archetype(_ kind: BossKind) -> BossArchetype {
        switch kind {
        case .breakfastGoblin:
            return BossArchetype(
                kind: kind,
                name: String(localized: "Breakfast Goblin", bundle: .module, comment: "Weekly boss name (Czech: Snídaňový skřet)."),
                flavour: String(localized: "Steals the first meal of the day.", bundle: .module, comment: "Weekly boss flavour line."),
                goal: String(localized: "Log breakfast", bundle: .module, comment: "Weekly boss habit: log a breakfast entry."),
                symbol: "sunrise.fill", requirement: [], judgesCompletedDaysOnly: false,
                goodDay: .mealLogged(.breakfast)
            )
        case .desertDragon:
            return BossArchetype(
                kind: kind,
                name: String(localized: "Desert Dragon", bundle: .module, comment: "Weekly boss name (Czech: Pouštní drak)."),
                flavour: String(localized: "Dries you out, one skipped sip at a time.", bundle: .module, comment: "Weekly boss flavour line."),
                goal: String(localized: "Reach your water goal", bundle: .module, comment: "Weekly boss habit: meet the daily water goal."),
                symbol: "drop.fill", requirement: .water, judgesCompletedDaysOnly: false,
                goodDay: .waterGoalMet
            )
        case .beigeBeast:
            return BossArchetype(
                kind: kind,
                name: String(localized: "The Beige Beast", bundle: .module, comment: "Weekly boss name (Czech: Béžová bestie)."),
                flavour: String(localized: "Feeds on plates without a single green thing.", bundle: .module, comment: "Weekly boss flavour line."),
                goal: String(localized: "Eat vegetables twice", bundle: .module, comment: "Weekly boss habit: at least two vegetable entries in a day."),
                symbol: "leaf.fill", requirement: [], judgesCompletedDaysOnly: false,
                goodDay: .tagCountAtLeast(.vegetable, 2)
            )
        case .proteinPoltergeist:
            return BossArchetype(
                kind: kind,
                name: String(localized: "Protein Poltergeist", bundle: .module, comment: "Weekly boss name (Czech: Proteinový poltergeist)."),
                flavour: String(localized: "Makes your protein vanish without a trace.", bundle: .module, comment: "Weekly boss flavour line."),
                goal: String(localized: "Hit your protein goal", bundle: .module, comment: "Weekly boss habit: meet the protein goal."),
                symbol: "bolt.fill", requirement: [], judgesCompletedDaysOnly: false,
                goodDay: .goalMet(.protein)
            )
        case .calorieKraken:
            return BossArchetype(
                kind: kind,
                name: String(localized: "Calorie Kraken", bundle: .module, comment: "Weekly boss name (Czech: Kalorický kraken)."),
                flavour: String(localized: "Drags your calorie target out to sea.", bundle: .module, comment: "Weekly boss flavour line."),
                goal: String(localized: "Hit your calorie goal", bundle: .module, comment: "Weekly boss habit: meet the calorie goal."),
                symbol: "water.waves", requirement: [], judgesCompletedDaysOnly: false,
                goodDay: .goalMet(.calories)
            )
        case .midnightMuncher:
            return BossArchetype(
                kind: kind,
                name: String(localized: "Midnight Muncher", bundle: .module, comment: "Weekly boss name (Czech: Půlnoční mlsoun)."),
                flavour: String(localized: "Lurks by the fridge after dark.", bundle: .module, comment: "Weekly boss flavour line."),
                goal: String(localized: "Eat nothing after 21:00", bundle: .module, comment: "Weekly boss habit: no entry at or after 21:00."),
                symbol: "moon.stars.fill", requirement: [], judgesCompletedDaysOnly: true,
                goodDay: .lastLogBefore(hour: 21, minute: 0)
            )
        case .sodaLich:
            return BossArchetype(
                kind: kind,
                name: String(localized: "Soda Lich", bundle: .module, comment: "Weekly boss name (Czech: Limonádový lich)."),
                flavour: String(localized: "Grows stronger with every sweet fizzy drink.", bundle: .module, comment: "Weekly boss flavour line."),
                goal: String(localized: "Skip sugary drinks", bundle: .module, comment: "Weekly boss habit: no sugary drink on a day with at least two entries."),
                symbol: "takeoutbag.and.cup.and.straw.fill", requirement: [], judgesCompletedDaysOnly: true,
                goodDay: .noTag(.sugaryDrink, minEntries: 2)
            )
        case .fibrePhantom:
            return BossArchetype(
                kind: kind,
                name: String(localized: "Fibre Phantom", bundle: .module, comment: "Weekly boss name (Czech: Vlákninový fantom)."),
                flavour: String(localized: "Haunts every meal without fibre.", bundle: .module, comment: "Weekly boss flavour line."),
                goal: String(localized: "Eat 25 g of fibre", bundle: .module, comment: "Weekly boss habit: at least 25 g fibre in a day."),
                symbol: "circle.hexagongrid.fill", requirement: .macros, judgesCompletedDaysOnly: false,
                goodDay: .macroAtLeast(.fiber, grams: 25)
            )
        case .scurvyPirate:
            return BossArchetype(
                kind: kind,
                name: String(localized: "Scurvy Pirate", bundle: .module, comment: "Weekly boss name (Czech: Kurdějový pirát)."),
                flavour: String(localized: "Sails off with all your fruit.", bundle: .module, comment: "Weekly boss flavour line."),
                goal: String(localized: "Eat a piece of fruit", bundle: .module, comment: "Weekly boss habit: at least one fruit entry."),
                symbol: "sailboat.fill", requirement: [], judgesCompletedDaysOnly: false,
                goodDay: .hasTag(.fruit)
            )
        case .forgetfulGhost:
            return BossArchetype(
                kind: kind,
                name: String(localized: "Forgetful Ghost", bundle: .module, comment: "Weekly boss name (Czech: Zapomnětlivý duch)."),
                flavour: String(localized: "Makes whole days vanish from your log.", bundle: .module, comment: "Weekly boss flavour line."),
                goal: String(localized: "Log any food", bundle: .module, comment: "Weekly boss habit: log at least one entry."),
                symbol: "eye.slash.fill", requirement: [], judgesCompletedDaysOnly: false,
                goodDay: .distinctFoodsAtLeast(1)
            )
        }
    }

    // MARK: - Badges

    public static let firstDefeatBadge = "boss.first"
    public static let tenDefeatsBadge = "boss.10"
    public static let twentyFiveDefeatsBadge = "boss.25"
    public static let perfectBadge = "boss.perfect"
    public static let bestiaryBadge = "boss.bestiary"
    public static let firstFreezeBadge = "freeze.first"
    public static let freezeSaved100Badge = "freeze.saved-100"

    /// Boss badges and the two streak-freeze badges (design D3/D6); both
    /// sets are declared by the boss feature, so the host lets it unlock them.
    public static var badges: [AchievementDefinition] {
        func badge(
            _ id: String, _ title: String, _ subtitle: String, _ symbol: String,
            _ category: AchievementCategory, _ rarity: AchievementRarity
        ) -> AchievementDefinition {
            AchievementDefinition(
                id: id,
                title: title,
                subtitle: subtitle,
                category: category,
                badgeSymbol: symbol,
                condition: .featureEvaluated,
                rarityOverride: rarity,
                featureId: WeeklyBossFeature.id
            )
        }
        return [
            badge(firstDefeatBadge, String(localized: "Boss Slayer", bundle: .module, comment: "Badge title: first weekly boss defeated."),
                  String(localized: "Defeat your first weekly boss.", bundle: .module, comment: "Badge subtitle."), "shield.lefthalf.filled", .challenges, .common),
            badge(tenDefeatsBadge, String(localized: "Monster Hunter", bundle: .module, comment: "Badge title: 10 weekly bosses defeated."),
                  String(localized: "Defeat 10 weekly bosses.", bundle: .module, comment: "Badge subtitle."), "scope", .challenges, .rare),
            badge(twentyFiveDefeatsBadge, String(localized: "Legend of the Realm", bundle: .module, comment: "Badge title: 25 weekly bosses defeated."),
                  String(localized: "Defeat 25 weekly bosses.", bundle: .module, comment: "Badge subtitle."), "crown.fill", .challenges, .epic),
            badge(perfectBadge, String(localized: "Flawless Victory", bundle: .module, comment: "Badge title: defeated a boss whose target was all 7 days."),
                  String(localized: "Defeat a boss with a 7-day target.", bundle: .module, comment: "Badge subtitle."), "star.circle.fill", .challenges, .rare),
            badge(bestiaryBadge, String(localized: "Bestiary Complete", bundle: .module, comment: "Badge title: every boss archetype defeated at least once."),
                  String(localized: "Defeat every kind of boss at least once.", bundle: .module, comment: "Badge subtitle."), "books.vertical.fill", .challenges, .legendary),
            badge(firstFreezeBadge, String(localized: "Cool Head", bundle: .module, comment: "Badge title: a streak freeze saved the streak for the first time."),
                  String(localized: "Let a streak freeze save your streak.", bundle: .module, comment: "Badge subtitle."), "snowflake", .streak, .common),
            badge(freezeSaved100Badge, String(localized: "Ice Age", bundle: .module, comment: "Badge title: a streak freeze saved a streak of at least 100 days."),
                  String(localized: "Let a freeze save a streak of 100 days or more.", bundle: .module, comment: "Badge subtitle."), "snowflake.circle.fill", .streak, .epic),
        ]
    }
}
