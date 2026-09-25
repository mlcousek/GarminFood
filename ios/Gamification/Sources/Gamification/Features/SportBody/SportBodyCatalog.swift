// SportBodyCatalog.swift
//
// add-sport-and-body-achievements design D2: the badge definitions the
// sport & body feature declares (and alone may unlock -- `FeatureHost`
// drops undeclared ids). Ids: `sport.*` for activity/race badges, `body.*`
// for weight and fasting. Every badge is `.featureEvaluated` with an
// explicit rarity (the table in design D2) and `featureId` =
// `SportAndBodyFeature.id` ("sportBody").
//
// Categories reuse the existing `AchievementCategory` cases (activity and
// weight badges under Goal Hitting, fasting under Streaks) rather than
// adding a new case, so the shared Achievements screen needs no edit.
//
// Tier thresholds live here next to their ids so the feature and the tests
// read one table. Display text is localized from this package's
// Resources/<lang>.lproj (keys = English source text).
//
// Depends on: AchievementDefinition. Depended on by: SportAndBodyFeature,
// BodyRules, the app's SportBodyView.

import Foundation

public enum SportBodyCatalog {
    /// A badge that unlocks when a count reaches `threshold`.
    public struct Tier: Sendable, Equatable {
        public let id: String
        public let threshold: Int

        public init(id: String, threshold: Int) {
            self.id = id
            self.threshold = threshold
        }
    }

    // MARK: Ids and tiers

    public static let fuelTiers: [Tier] = [
        Tier(id: "sport.fuel-1", threshold: 1),
        Tier(id: "sport.fuel-10", threshold: 10),
        Tier(id: "sport.fuel-50", threshold: 50)
    ]
    public static let recoveryTiers: [Tier] = [
        Tier(id: "sport.recovery-1", threshold: 1),
        Tier(id: "sport.recovery-10", threshold: 10),
        Tier(id: "sport.recovery-50", threshold: 50)
    ]
    public static let earnedTiers: [Tier] = [
        Tier(id: "sport.earned-5", threshold: 5),
        Tier(id: "sport.earned-25", threshold: 25),
        Tier(id: "sport.earned-100", threshold: 100)
    ]
    public static let raceDayTiers: [Tier] = [
        Tier(id: "sport.race-day-1", threshold: 1),
        Tier(id: "sport.race-day-5", threshold: 5)
    ]
    public static let fastingTiers: [Tier] = [
        Tier(id: "body.fast-3", threshold: 3),
        Tier(id: "body.fast-7", threshold: 7),
        Tier(id: "body.fast-14", threshold: 14),
        Tier(id: "body.fast-30", threshold: 30)
    ]

    public static let doubleDayId = "sport.double-day"
    public static let gelGuruId = "sport.gel-guru"
    public static let longHaulId = "sport.long-haul"
    public static let carbLoaderId = "sport.carb-loader"
    public static let firstKiloId = "body.first-kilo"
    public static let halfwayId = "body.halfway"
    public static let targetId = "body.target"
    public static let steadyId = "body.steady-30"

    /// The four weight milestones, in display order.
    public static let weightMilestoneIds: [String] = [firstKiloId, halfwayId, targetId, steadyId]

    /// The tier ids unlocked by `count`.
    public static func reached(_ tiers: [Tier], count: Int) -> [String] {
        tiers.filter { count >= $0.threshold }.map(\.id)
    }

    /// The next tier `count` has not reached yet.
    public static func nextTier(_ tiers: [Tier], count: Int) -> Tier? {
        tiers.first { count < $0.threshold }
    }

    public static func badge(id: String) -> AchievementDefinition? {
        badges.first { $0.id == id }
    }

    // MARK: Definitions

    private static func define(
        _ id: String,
        _ title: String,
        _ subtitle: String,
        category: AchievementCategory = .goalHitting,
        symbol: String,
        rarity: AchievementRarity
    ) -> AchievementDefinition {
        AchievementDefinition(
            id: id,
            title: title,
            subtitle: subtitle,
            category: category,
            badgeSymbol: symbol,
            condition: .featureEvaluated,
            rarityOverride: rarity,
            featureId: SportAndBodyFeature.id
        )
    }

    private static func fuelSubtitle(_ count: Int) -> String {
        String(
            format: String(localized: "Fuel up 30–180 min before the start of %lld activities.", bundle: .module, comment: "Sport badge description: count of fuelled activities (10 or 50)."),
            count
        )
    }

    private static func recoverySubtitle(_ count: Int) -> String {
        String(
            format: String(localized: "Refuel 20 g+ protein within 60 min after %lld activities.", bundle: .module, comment: "Sport badge description: count of recovered activities (10 or 50)."),
            count
        )
    }

    private static func earnedSubtitle(_ count: Int) -> String {
        String(
            format: String(localized: "Eat to match your burn on %lld active days (400+ active kcal).", bundle: .module, comment: "Sport badge description: count of days (5, 25 or 100)."),
            count
        )
    }

    public static let badges: [AchievementDefinition] = [
        // Fuel before
        define(
            "sport.fuel-1",
            String(localized: "Fuelled Up", bundle: .module, comment: "Sport badge title: first activity fuelled with carbs beforehand."),
            String(localized: "Log 30 g+ carbs 30–180 min before a run, ride or hike.", bundle: .module, comment: "Sport badge description."),
            symbol: "fuelpump.fill",
            rarity: .common
        ),
        define(
            "sport.fuel-10",
            String(localized: "Pit Crew", bundle: .module, comment: "Sport badge title: 10 activities fuelled."),
            fuelSubtitle(10),
            symbol: "wrench.and.screwdriver.fill",
            rarity: .rare
        ),
        define(
            "sport.fuel-50",
            String(localized: "Race Engineer", bundle: .module, comment: "Sport badge title: 50 activities fuelled."),
            fuelSubtitle(50),
            symbol: "speedometer",
            rarity: .epic
        ),
        // Recover after
        define(
            "sport.recovery-1",
            String(localized: "Recovery Window", bundle: .module, comment: "Sport badge title: protein eaten soon after an activity."),
            String(localized: "Eat 20 g+ protein within 60 min after a run, ride or workout.", bundle: .module, comment: "Sport badge description."),
            symbol: "timer",
            rarity: .common
        ),
        define(
            "sport.recovery-10",
            String(localized: "Protein Timer", bundle: .module, comment: "Sport badge title: 10 activities followed by protein."),
            recoverySubtitle(10),
            symbol: "stopwatch.fill",
            rarity: .rare
        ),
        define(
            "sport.recovery-50",
            String(localized: "Recovery Pro", bundle: .module, comment: "Sport badge title: 50 activities followed by protein."),
            recoverySubtitle(50),
            symbol: "heart.circle.fill",
            rarity: .epic
        ),
        // Eat to match the day
        define(
            "sport.earned-5",
            String(localized: "Earned It", bundle: .module, comment: "Sport badge title: intake matched to an active day."),
            earnedSubtitle(5),
            symbol: "flame.fill",
            rarity: .uncommon
        ),
        define(
            "sport.earned-25",
            String(localized: "Balanced Burner", bundle: .module, comment: "Sport badge title: 25 active days with matched intake."),
            earnedSubtitle(25),
            symbol: "scalemass.fill",
            rarity: .rare
        ),
        define(
            "sport.earned-100",
            String(localized: "Energy Accountant", bundle: .module, comment: "Sport badge title: 100 active days with matched intake."),
            earnedSubtitle(100),
            symbol: "chart.bar.fill",
            rarity: .epic
        ),
        // Big days
        define(
            doubleDayId,
            String(localized: "Double Day", bundle: .module, comment: "Sport badge title: two workouts in one day."),
            String(localized: "Two runs or rides in one day, with the protein goal met.", bundle: .module, comment: "Sport badge description."),
            symbol: "2.circle.fill",
            rarity: .uncommon
        ),
        define(
            gelGuruId,
            String(localized: "Gel Guru", bundle: .module, comment: "Sport badge title: fuelling during a long activity."),
            String(localized: "Log 3 entries during one endurance activity of 90+ min.", bundle: .module, comment: "Sport badge description."),
            symbol: "drop.fill",
            rarity: .rare
        ),
        define(
            longHaulId,
            String(localized: "Long Haul", bundle: .module, comment: "Sport badge title: eating during a 3-hour activity."),
            String(localized: "Log food during an endurance activity of 3+ hours.", bundle: .module, comment: "Sport badge description."),
            symbol: "figure.hiking",
            rarity: .rare
        ),
        // Race days (the "race" day-note tag)
        define(
            "sport.race-day-1",
            String(localized: "Race Day Fuel", bundle: .module, comment: "Sport badge title: food logged on a race day."),
            String(localized: "Log food on a day tagged Race.", bundle: .module, comment: "Sport badge description. 'Race' is the day-note tag."),
            symbol: "flag.checkered",
            rarity: .uncommon
        ),
        define(
            "sport.race-day-5",
            String(localized: "Serial Racer", bundle: .module, comment: "Sport badge title: five race days with food logged."),
            String(localized: "Log food on 5 days tagged Race.", bundle: .module, comment: "Sport badge description. 'Race' is the day-note tag."),
            symbol: "trophy.fill",
            rarity: .epic
        ),
        define(
            carbLoaderId,
            String(localized: "Carb Loader", bundle: .module, comment: "Sport badge title: carb goal met on the two days before a race."),
            String(localized: "Meet your carb goal on both days before a race.", bundle: .module, comment: "Sport badge description."),
            symbol: "fork.knife.circle.fill",
            rarity: .rare
        ),
        // Weight goal
        define(
            firstKiloId,
            String(localized: "First Kilo", bundle: .module, comment: "Body badge title: first kilogram toward the weight goal."),
            String(localized: "Weigh in 1 kg from your start weight, toward your goal.", bundle: .module, comment: "Body badge description."),
            symbol: "scalemass",
            rarity: .common
        ),
        define(
            halfwayId,
            String(localized: "Halfway There", bundle: .module, comment: "Body badge title: halfway to the weight goal."),
            String(localized: "Weigh in halfway from your start weight to your target.", bundle: .module, comment: "Body badge description."),
            symbol: "flag.fill",
            rarity: .rare
        ),
        define(
            targetId,
            String(localized: "Target Reached", bundle: .module, comment: "Body badge title: target weight reached."),
            String(localized: "Weigh in at your target weight.", bundle: .module, comment: "Body badge description."),
            symbol: "target",
            rarity: .epic
        ),
        define(
            steadyId,
            String(localized: "Steady as Sněžka", bundle: .module, comment: "Body badge title: weight held at target for 30 days. Sněžka is the highest Czech mountain."),
            String(localized: "Stay within 1 kg of your target for 30 days (8+ weigh-ins).", bundle: .module, comment: "Body badge description."),
            symbol: "mountain.2.fill",
            rarity: .legendary
        ),
        // Fasting streak
        define(
            "body.fast-3",
            String(localized: "Fast Starter", bundle: .module, comment: "Fasting badge title: 3 kept fasts in a row."),
            String(localized: "Keep your fasting schedule 3 days in a row.", bundle: .module, comment: "Fasting badge description."),
            category: .streak,
            symbol: "moon.fill",
            rarity: .common
        ),
        define(
            "body.fast-7",
            String(localized: "Fasting Week", bundle: .module, comment: "Fasting badge title: 7 kept fasts in a row."),
            String(localized: "Keep your fasting schedule 7 days in a row.", bundle: .module, comment: "Fasting badge description."),
            category: .streak,
            symbol: "moon.stars.fill",
            rarity: .uncommon
        ),
        define(
            "body.fast-14",
            String(localized: "Fasting Fortnight", bundle: .module, comment: "Fasting badge title: 14 kept fasts in a row."),
            String(localized: "Keep your fasting schedule 14 days in a row.", bundle: .module, comment: "Fasting badge description."),
            category: .streak,
            symbol: "hourglass",
            rarity: .rare
        ),
        define(
            "body.fast-30",
            String(localized: "Fasting Master", bundle: .module, comment: "Fasting badge title: 30 kept fasts in a row."),
            String(localized: "Keep your fasting schedule 30 days in a row.", bundle: .module, comment: "Fasting badge description."),
            category: .streak,
            symbol: "crown.fill",
            rarity: .epic
        )
    ]
}
