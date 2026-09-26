// SupplementsCatalog.swift
//
// add-supplements D9: the static facts of the supplements feature --
//
//   - BADGES (`supplements.*` ids, `condition: .featureEvaluated`,
//     category `.supplements`, rarity stated explicitly because there is no
//     condition to derive it from; persisted by AchievementStore, so never
//     rename an id): First stack, Stack week (a 7-day supplement streak),
//     Full stack month (30 days), Creatine 30/100 (days with creatine),
//     Sunshine (vitamin D on 60 days of one October-March season), Omega
//     month (omega-3 on 30 days in a row), Never ran out (restocked before
//     empty 3 times), Alphabet 5/10 (distinct vitamins AND minerals: the
//     app knows only five vitamins, so ten needs minerals too);
//   - the VITAMIN ALPHABET collection: every built-in vitamin and mineral
//     ingredient (names come from FoodLogCore's EvidenceCatalog, already
//     localized);
//   - the CREATINE JOURNEY: cumulative creatine grams, milestones 100 g ->
//     500 g -> 1 kg -> 2.5 kg -> 5 kg (at 5 g a day: ~3 weeks, ~3 months,
//     ~7 months, ~16 months, ~2.7 years).
//
// Titles use English-source keys in this package's Localizable.strings
// (CatalogCoverageTests requires a Czech title for every feature badge).
//
// Depends on: AchievementDefinition/Rarity, FoodLogCore (IngredientID).
// Depended on by: SupplementsFeature (`badges`), SupplementsEvaluator, the
// app's Supplements screen. Tests: SupplementsGamificationTests.

import Foundation
import FoodLogCore

public struct SupplementJourneyMilestone: Sendable, Equatable, Identifiable {
    /// Persisted in `SupplementsState.reachedMilestones` and grant keys.
    public let id: String
    /// Cumulative creatine grams.
    public let grams: Double
}

public enum SupplementsCatalog {
    // MARK: - Badge ids

    public static let firstStackBadge = "supplements.first-stack"
    public static let stackWeekBadge = "supplements.stack-week"
    public static let fullStackMonthBadge = "supplements.full-stack-month"
    public static let creatine30Badge = "supplements.creatine-30"
    public static let creatine100Badge = "supplements.creatine-100"
    public static let sunshineBadge = "supplements.sunshine"
    public static let omegaMonthBadge = "supplements.omega-month"
    public static let neverRanOutBadge = "supplements.never-ran-out"
    public static let alphabet5Badge = "supplements.alphabet-5"
    public static let alphabet10Badge = "supplements.alphabet-10"

    // MARK: - Thresholds

    public static let stackWeekDays = 7
    public static let fullStackMonthDays = 30
    public static let creatineDayThresholds = [30, 100]
    public static let sunshineDays = 60
    public static let omegaRunDays = 30
    public static let neverRanOutRefills = 3
    public static let alphabetThresholds = [5, 10]

    // MARK: - Collection

    /// The vitamin alphabet: vitamins first, then minerals.
    public static let alphabet: [IngredientID] = [
        .vitaminD, .vitaminC, .vitaminB6, .vitaminB12, .vitaminK2,
        .magnesium, .zinc, .iron, .selenium, .potassium, .sodium,
    ]

    // MARK: - Journey

    public static let journey: [SupplementJourneyMilestone] = [
        SupplementJourneyMilestone(id: "creatine-100g", grams: 100),
        SupplementJourneyMilestone(id: "creatine-500g", grams: 500),
        SupplementJourneyMilestone(id: "creatine-1kg", grams: 1_000),
        SupplementJourneyMilestone(id: "creatine-2500g", grams: 2_500),
        SupplementJourneyMilestone(id: "creatine-5kg", grams: 5_000),
    ]

    // MARK: - Badges

    public static var badges: [AchievementDefinition] {
        func badge(_ id: String, _ title: String, _ subtitle: String, _ symbol: String, _ rarity: AchievementRarity) -> AchievementDefinition {
            AchievementDefinition(
                id: id,
                title: title,
                subtitle: subtitle,
                category: .supplements,
                badgeSymbol: symbol,
                condition: .featureEvaluated,
                rarityOverride: rarity,
                featureId: SupplementsFeature.id
            )
        }
        return [
            badge(firstStackBadge,
                  String(localized: "First Stack", bundle: .module, comment: "Badge title: the first day every planned supplement was taken."),
                  String(localized: "Take every supplement planned for a day.", bundle: .module, comment: "Badge description: how to earn First Stack."),
                  "pills.fill", .common),
            badge(stackWeekBadge,
                  String(localized: "Stack Week", bundle: .module, comment: "Badge title: a 7-day supplement streak."),
                  String(localized: "Reach a 7-day supplement streak.", bundle: .module, comment: "Badge description."),
                  "calendar.badge.checkmark", .uncommon),
            badge(fullStackMonthBadge,
                  String(localized: "Full Stack Month", bundle: .module, comment: "Badge title: a 30-day supplement streak."),
                  String(localized: "Reach a 30-day supplement streak.", bundle: .module, comment: "Badge description."),
                  "crown.fill", .epic),
            badge(creatine30Badge,
                  String(localized: "Creatine 30", bundle: .module, comment: "Badge title: creatine taken on 30 days."),
                  String(localized: "Take creatine on 30 days.", bundle: .module, comment: "Badge description."),
                  "bolt.fill", .uncommon),
            badge(creatine100Badge,
                  String(localized: "Creatine 100", bundle: .module, comment: "Badge title: creatine taken on 100 days."),
                  String(localized: "Take creatine on 100 days.", bundle: .module, comment: "Badge description."),
                  "bolt.circle.fill", .rare),
            badge(sunshineBadge,
                  String(localized: "Sunshine", bundle: .module, comment: "Badge title: vitamin D through the dark months."),
                  String(localized: "Take vitamin D on 60 days between October and March.", bundle: .module, comment: "Badge description: 60 days within one October-March season."),
                  "sun.max.fill", .rare),
            badge(omegaMonthBadge,
                  String(localized: "Omega Month", bundle: .module, comment: "Badge title: omega-3 every day for a month."),
                  String(localized: "Take omega-3 on 30 days in a row.", bundle: .module, comment: "Badge description."),
                  "fish.fill", .rare),
            badge(neverRanOutBadge,
                  String(localized: "Never Ran Out", bundle: .module, comment: "Badge title: supplements restocked before they ran out."),
                  String(localized: "Restock a supplement before it runs out, 3 times.", bundle: .module, comment: "Badge description."),
                  "shippingbox.fill", .uncommon),
            badge(alphabet5Badge,
                  String(localized: "Alphabet 5", bundle: .module, comment: "Badge title: 5 different vitamins and minerals taken (the vitamin alphabet collection)."),
                  String(localized: "Take 5 different vitamins and minerals.", bundle: .module, comment: "Badge description."),
                  "textformat.abc", .uncommon),
            badge(alphabet10Badge,
                  String(localized: "Alphabet 10", bundle: .module, comment: "Badge title: 10 different vitamins and minerals taken (the vitamin alphabet collection)."),
                  String(localized: "Take 10 different vitamins and minerals.", bundle: .module, comment: "Badge description."),
                  "character.book.closed.fill", .epic),
        ]
    }

    /// The badges the Achievements screen lists: while supplements are off,
    /// a supplement badge shows only once earned (earned ones stay, spec
    /// "Feature disabled"); every other badge is unchanged.
    public static func visibleBadges(
        _ catalog: [AchievementDefinition],
        isEnabled: Bool,
        unlockedIds: Set<String>
    ) -> [AchievementDefinition] {
        guard !isEnabled else { return catalog }
        return catalog.filter { $0.featureId != SupplementsFeature.id || unlockedIds.contains($0.id) }
    }

    // MARK: - Display names

    public static var collectionName: String {
        String(localized: "Vitamin alphabet", bundle: .module, comment: "Collection name: the distinct vitamins and minerals taken.")
    }

    public static var journeyName: String {
        String(localized: "Creatine journey", bundle: .module, comment: "Journey name: cumulative creatine grams taken.")
    }

    /// "100 g", "1 kg", "2,5 kg" (locale decimals).
    public static func gramsText(_ grams: Double) -> String {
        if grams >= 1_000 {
            let kilograms = (grams / 1_000).formatted(.number.precision(.fractionLength(0...1)))
            return "\(kilograms) kg"
        }
        return "\(grams.formatted(.number.precision(.fractionLength(0)))) g"
    }
}
