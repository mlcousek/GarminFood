import Foundation

// Achievements.swift
//
// achievements spec's "permanent, one-time unlocks from a large, paced
// catalog" requirement (expand-gamification-depth design.md D5): 120+
// definitions across eleven categories, each a locally-evaluable
// condition against an `AchievementContext` snapshot. Evaluation itself
// lives in `AchievementEngine.swift`; persistence in `AchievementStore.swift`.

public enum AchievementCategory: String, Sendable, Equatable, CaseIterable {
    case streak, level, volume, variety, challenges, dailyChallenges, goalHitting, extreme, funnyFacts, calendar, meta
}

/// A locally-evaluable achievement condition, each case reading exactly
/// the `AchievementContext` fields its evaluation needs.
public enum AchievementCondition: Sendable, Equatable {
    /// The longest streak ever reached is at least `days`.
    case streakAtLeast(days: Int)
    case levelAtLeast(level: Int)
    case totalLogsAtLeast(count: Int)
    /// Distinct foods within the RETAINED usage history (design.md D4's
    /// documented scope -- see `ChallengeKind.newFoodsTried`'s identical
    /// limitation).
    case distinctFoodsAtLeast(count: Int)
    case challengesCompletedAtLeast(count: Int)
    /// Every template in the (at-evaluation-time) challenge catalog has
    /// been completed at least once.
    case allChallengesCompleted
    case dailyChallengesCompletedAtLeast(count: Int)
    case goalHitDaysAtLeast(macro: GoalMacro, count: Int)
    /// The single highest-calorie nutrition-day ever reaches this total.
    case singleDayCaloriesAtLeast(calories: Double)
    /// Lifetime cumulative calories reach this total -- the "funny
    /// comparison" achievements.
    case totalCaloriesAtLeast(calories: Double)
    case perfectCalendarMonth
    case loggedOnLeapDay
    case loggedOnNewYearsDay
    case loggedAtMidnight
    case anniversaryYears(years: Int)
    /// Meta/completionist only: at least `fraction` of every OTHER
    /// (non-meta) achievement is unlocked. Evaluated in a second pass by
    /// `AchievementEngine`, never by the generic per-condition check.
    case unlockedFractionOfOthers(fraction: Double)
}

public struct AchievementDefinition: Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let category: AchievementCategory
    public let badgeSymbol: String
    public let condition: AchievementCondition
    /// Meta achievements are excluded from their own denominator and from
    /// every OTHER meta achievement's denominator -- see `AchievementEngine`.
    public let isMeta: Bool

    /// How hard this achievement is to unlock, purely derived from
    /// `condition` -- see `AchievementRarity.derive(from:)`'s header for why
    /// this is computed rather than a stored field. Used by
    /// `BadgeMedallion` (GarminFood/DesignSystem/) to pick the badge's
    /// rim/fill treatment; not persisted anywhere.
    public var rarity: AchievementRarity { AchievementRarity.derive(from: condition) }

    public init(id: String, title: String, subtitle: String, category: AchievementCategory, badgeSymbol: String, condition: AchievementCondition, isMeta: Bool = false) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.category = category
        self.badgeSymbol = badgeSymbol
        self.condition = condition
        self.isMeta = isMeta
    }
}

/// The already-computed snapshot `AchievementEngine.evaluate` checks every
/// condition against -- built once per refresh by `GamificationEngine`
/// from data it already holds (usage history, `LifetimeStatsStore`,
/// `ChallengeHistoryStore`, `DailyChallengeStore`, `LevelCurve.Progress`,
/// `StreakHistory.Summary`) plus the small `AchievementSignals` helpers.
public struct AchievementContext: Sendable, Equatable {
    public let level: Int
    public let longestStreak: Int
    public let totalLogsEver: Int
    public let distinctFoodsInRetainedHistory: Int
    public let challengeCompletionCount: Int
    public let distinctCompletedChallengeTemplateCount: Int
    public let totalChallengeCatalogCount: Int
    public let dailyChallengeCompletionCount: Int
    /// Keyed by `GoalMacro.rawValue`.
    public let goalHitDaysEver: [String: Int]
    public let maxSingleDayCalories: Double
    public let totalCaloriesEver: Double
    public let hasPerfectCalendarMonth: Bool
    public let hasLoggedOnLeapDay: Bool
    public let hasLoggedOnNewYearsDay: Bool
    public let hasLoggedAtMidnight: Bool
    public let yearsSinceFirstLog: Int

    public init(
        level: Int,
        longestStreak: Int,
        totalLogsEver: Int,
        distinctFoodsInRetainedHistory: Int,
        challengeCompletionCount: Int,
        distinctCompletedChallengeTemplateCount: Int,
        totalChallengeCatalogCount: Int,
        dailyChallengeCompletionCount: Int,
        goalHitDaysEver: [String: Int],
        maxSingleDayCalories: Double,
        totalCaloriesEver: Double,
        hasPerfectCalendarMonth: Bool,
        hasLoggedOnLeapDay: Bool,
        hasLoggedOnNewYearsDay: Bool,
        hasLoggedAtMidnight: Bool,
        yearsSinceFirstLog: Int
    ) {
        self.level = level
        self.longestStreak = longestStreak
        self.totalLogsEver = totalLogsEver
        self.distinctFoodsInRetainedHistory = distinctFoodsInRetainedHistory
        self.challengeCompletionCount = challengeCompletionCount
        self.distinctCompletedChallengeTemplateCount = distinctCompletedChallengeTemplateCount
        self.totalChallengeCatalogCount = totalChallengeCatalogCount
        self.dailyChallengeCompletionCount = dailyChallengeCompletionCount
        self.goalHitDaysEver = goalHitDaysEver
        self.maxSingleDayCalories = maxSingleDayCalories
        self.totalCaloriesEver = totalCaloriesEver
        self.hasPerfectCalendarMonth = hasPerfectCalendarMonth
        self.hasLoggedOnLeapDay = hasLoggedOnLeapDay
        self.hasLoggedOnNewYearsDay = hasLoggedOnNewYearsDay
        self.hasLoggedAtMidnight = hasLoggedAtMidnight
        self.yearsSinceFirstLog = yearsSinceFirstLog
    }
}

/// design.md D5: 120+ definitions across eleven categories, paced with
/// real long-tail thresholds (365/730/1000-day streaks, 10000+ lifetime
/// logs, multi-year anniversaries) so a 2-3 year user keeps discovering
/// new ones rather than unlocking the whole catalog in month one.
public enum AchievementCatalog {
    public static let all: [AchievementDefinition] = streakFamily
        + levelFamily
        + lifetimeLogsFamily
        + distinctFoodsFamily
        + challengesFamily
        + dailyChallengesFamily
        + goalHitDaysFamily
        + extremeFamily
        + funnyComparisonFamily
        + calendarFamily
        + metaFamily

    private static func macroDisplayName(_ macro: GoalMacro) -> String {
        switch macro {
        case .calories: return "Calorie"
        case .protein: return "Protein"
        case .carbs: return "Carb"
        case .fat: return "Fat"
        }
    }

    private static let streakFamily: [AchievementDefinition] = {
        let thresholds = [1, 3, 7, 14, 21, 30, 45, 60, 90, 120, 180, 270, 365, 500, 730, 1000]
        let titles = ["First Flame", "Three in a Row", "One Week Strong", "Two-Week Warrior", "Three Weeks Running", "One Month Milestone", "Six Weeks In", "Two-Month Titan", "Quarter-Year Flame", "Four-Month Fire", "Half-Year Hero", "Nine Months Strong", "One Full Year", "500-Day Legend", "Two-Year Inferno", "The Thousand-Day Flame"]
        return thresholds.indices.map { i in
            let n = thresholds[i]
            return AchievementDefinition(
                id: "achv-streak-\(n)",
                title: titles[i],
                subtitle: "Reach a \(n)-day streak.",
                category: .streak,
                badgeSymbol: "flame.fill",
                condition: .streakAtLeast(days: n)
            )
        }
    }()

    private static let levelFamily: [AchievementDefinition] = {
        let thresholds = [5, 10, 20, 30, 50, 75, 100, 125, 150, 175, 200]
        let titles = ["Off the Ground", "Double Digits", "Twenty Strong", "Level Thirty", "Half-Century", "Level Seventy-Five", "Century Club", "Level 125", "Level 150", "Level 175", "Max Level"]
        return thresholds.indices.map { i in
            let n = thresholds[i]
            return AchievementDefinition(
                id: "achv-level-\(n)",
                title: titles[i],
                subtitle: "Reach level \(n).",
                category: .level,
                badgeSymbol: "star.fill",
                condition: .levelAtLeast(level: n)
            )
        }
    }()

    private static let lifetimeLogsFamily: [AchievementDefinition] = {
        let thresholds = [1, 10, 50, 100, 250, 500, 1000, 2500, 5000, 10000, 100_000]
        let titles = ["First Bite", "Ten Logged", "Fifty Strong", "Century of Logs", "Quarter-K Club", "Five Hundred Logged", "One Thousand Logged", "2,500 Logged", "Five Thousand Logged", "Ten Thousand Logged", "The Immortal Logger"]
        return thresholds.indices.map { i in
            let n = thresholds[i]
            return AchievementDefinition(
                id: "achv-logs-\(n)",
                title: titles[i],
                subtitle: "Log \(n) entries in total.",
                category: .volume,
                badgeSymbol: "fork.knife",
                condition: .totalLogsAtLeast(count: n)
            )
        }
    }()

    private static let distinctFoodsFamily: [AchievementDefinition] = {
        let thresholds = [5, 10, 25, 50, 100, 200, 500, 1000]
        let titles = ["Getting Curious", "Ten Different Foods", "Quarter-Century Palate", "Fifty Flavors", "Century of Foods", "Foodie", "Connoisseur", "The Encyclopedia"]
        return thresholds.indices.map { i in
            let n = thresholds[i]
            return AchievementDefinition(
                id: "achv-foods-\(n)",
                title: titles[i],
                subtitle: "Log \(n) different foods.",
                category: .variety,
                badgeSymbol: "leaf.fill",
                condition: .distinctFoodsAtLeast(count: n)
            )
        }
    }()

    private static let challengesFamily: [AchievementDefinition] = {
        let thresholds = [1, 5, 10, 25, 50, 100]
        let titles = ["First Challenge", "Five Down", "Ten Completed", "Quarter-Century of Challenges", "Fifty Challenges Beaten", "Century of Challenges"]
        var result = thresholds.indices.map { i -> AchievementDefinition in
            let n = thresholds[i]
            return AchievementDefinition(
                id: "achv-challenges-\(n)",
                title: titles[i],
                subtitle: "Complete \(n) challenges.",
                category: .challenges,
                badgeSymbol: "target",
                condition: .challengesCompletedAtLeast(count: n)
            )
        }
        result.append(AchievementDefinition(
            id: "achv-challenges-all",
            title: "The Completionist's Challenge",
            subtitle: "Complete every challenge in the catalog.",
            category: .challenges,
            badgeSymbol: "target",
            condition: .allChallengesCompleted
        ))
        return result
    }()

    private static let dailyChallengesFamily: [AchievementDefinition] = {
        let thresholds = [1, 10, 50, 100, 250, 500, 1000]
        let titles = ["First Daily Win", "Ten Daily Wins", "Fifty Daily Wins", "Century of Daily Wins", "250 Daily Wins", "500 Daily Wins", "1,000 Daily Wins"]
        return thresholds.indices.map { i in
            let n = thresholds[i]
            return AchievementDefinition(
                id: "achv-daily-\(n)",
                title: titles[i],
                subtitle: "Complete \(n) daily challenges in total.",
                category: .dailyChallenges,
                badgeSymbol: "checkmark.circle.fill",
                condition: .dailyChallengesCompletedAtLeast(count: n)
            )
        }
    }()

    private static let goalHitDaysFamily: [AchievementDefinition] = {
        let thresholds = [10, 50, 100, 365, 730]
        let suffixes = ["Getting Started", "Building Habits", "Century Club", "One Full Year", "Two Full Years"]
        return GoalMacro.allCases.flatMap { macro -> [AchievementDefinition] in
            thresholds.indices.map { i in
                let n = thresholds[i]
                return AchievementDefinition(
                    id: "achv-goal-\(macro.rawValue)-\(n)",
                    title: "\(macroDisplayName(macro)) \(suffixes[i])",
                    subtitle: "Hit your \(macro.rawValue) goal on \(n) days, total.",
                    category: .goalHitting,
                    badgeSymbol: "checkmark.seal.fill",
                    condition: .goalHitDaysAtLeast(macro: macro, count: n)
                )
            }
        }
    }()

    private static let extremeFamily: [AchievementDefinition] = {
        let thresholds = [3000, 4000, 5000, 6000, 7000, 8000, 10000]
        let titles = ["Big Appetite", "Feast Mode", "Thanksgiving Tier", "Holiday Feast", "Legendary Feast", "Feast of Legends", "The Ultimate Feast"]
        return thresholds.indices.map { i in
            let n = thresholds[i]
            return AchievementDefinition(
                id: "achv-extreme-\(n)",
                title: titles[i],
                subtitle: "Log \(n)+ kcal in a single day. Every feast deserves a badge.",
                category: .extreme,
                badgeSymbol: "bolt.fill",
                condition: .singleDayCaloriesAtLeast(calories: Double(n))
            )
        }
    }()

    private static let funnyComparisonFamily: [AchievementDefinition] = {
        struct Anchor {
            let idSlug: String
            let kcalPerUnit: Double
            let multiples: [Int]
            let titles: [String]
            let describe: (Int) -> String
        }
        let anchors: [Anchor] = [
            Anchor(idSlug: "banana", kcalPerUnit: 105, multiples: [50, 200, 1000, 5000],
                   titles: ["50 Bananas Worth", "200 Bananas Worth", "1,000 Bananas Worth", "5,000 Bananas Worth"],
                   describe: { "\($0) bananas (very roughly!)" }),
            Anchor(idSlug: "bigmac", kcalPerUnit: 550, multiples: [10, 50, 200, 1000],
                   titles: ["10 Burgers Worth", "50 Burgers Worth", "200 Burgers Worth", "1,000 Burgers Worth"],
                   describe: { "\($0) fast-food burgers (give or take)" }),
            Anchor(idSlug: "pizza", kcalPerUnit: 2000, multiples: [3, 10, 50, 200],
                   titles: ["3 Pizzas Worth", "10 Pizzas Worth", "50 Pizzas Worth", "200 Pizzas Worth"],
                   describe: { "\($0) whole pizzas (roughly)" }),
            Anchor(idSlug: "marathon", kcalPerUnit: 2600, multiples: [5, 20, 100, 500],
                   titles: ["5 Marathons Worth", "20 Marathons Worth", "100 Marathons Worth", "500 Marathons Worth"],
                   describe: { "\($0) marathons' worth of energy burned (very roughly)" }),
            Anchor(idSlug: "elephant", kcalPerUnit: 150_000, multiples: [1, 5, 20, 50],
                   titles: ["Fed an Elephant for a Day", "Fed an Elephant for Five Days", "Fed an Elephant for Three Weeks", "Fed an Elephant for 50 Days"],
                   describe: { $0 == 1 ? "one elephant's daily food intake (roughly!)" : "\($0) days of an elephant's food intake (roughly!)" }),
            Anchor(idSlug: "whale", kcalPerUnit: 1_500_000, multiples: [1, 3, 10, 30],
                   titles: ["Out-Ate a Blue Whale (For a Day)", "Out-Ate a Blue Whale for 3 Days", "Out-Ate a Blue Whale for 10 Days", "Out-Ate a Blue Whale for a Month"],
                   describe: { $0 == 1 ? "a blue whale's daily food intake (extremely roughly!)" : "\($0) days of a blue whale's food intake (extremely roughly!)" })
        ]
        return anchors.flatMap { anchor -> [AchievementDefinition] in
            anchor.multiples.indices.map { i in
                let multiple = anchor.multiples[i]
                let totalKcal = anchor.kcalPerUnit * Double(multiple)
                return AchievementDefinition(
                    id: "achv-funny-\(anchor.idSlug)-\(multiple)",
                    title: anchor.titles[i],
                    subtitle: "You've logged about \(anchor.describe(multiple)) in total calories.",
                    category: .funnyFacts,
                    badgeSymbol: "party.popper.fill",
                    condition: .totalCaloriesAtLeast(calories: totalKcal)
                )
            }
        }
    }()

    private static let calendarFamily: [AchievementDefinition] = [
        AchievementDefinition(id: "achv-perfect-month", title: "Perfect Month", subtitle: "Log every single day of a full calendar month.", category: .calendar, badgeSymbol: "calendar", condition: .perfectCalendarMonth),
        AchievementDefinition(id: "achv-leap-day", title: "Leap Day Logger", subtitle: "Log something on February 29th -- only possible once every four years.", category: .calendar, badgeSymbol: "calendar", condition: .loggedOnLeapDay),
        AchievementDefinition(id: "achv-new-year", title: "New Year, New Log", subtitle: "Log something on New Year's Day.", category: .calendar, badgeSymbol: "calendar", condition: .loggedOnNewYearsDay),
        AchievementDefinition(id: "achv-midnight", title: "Midnight Snack Club", subtitle: "Log something at exactly midnight.", category: .calendar, badgeSymbol: "moon.stars.fill", condition: .loggedAtMidnight),
        AchievementDefinition(id: "achv-anniversary-1", title: "One Year In", subtitle: "You've been using this app for a full year.", category: .calendar, badgeSymbol: "gift.fill", condition: .anniversaryYears(years: 1)),
        AchievementDefinition(id: "achv-anniversary-2", title: "Two Years Strong", subtitle: "Two full years of logging.", category: .calendar, badgeSymbol: "gift.fill", condition: .anniversaryYears(years: 2)),
        AchievementDefinition(id: "achv-anniversary-3", title: "Three-Year Veteran", subtitle: "Three full years -- exactly what you set out to do.", category: .calendar, badgeSymbol: "gift.fill", condition: .anniversaryYears(years: 3))
    ]

    private static let metaFamily: [AchievementDefinition] = [
        AchievementDefinition(id: "achv-meta-25", title: "Quarter Collector", subtitle: "Unlock 25% of all other achievements.", category: .meta, badgeSymbol: "crown.fill", condition: .unlockedFractionOfOthers(fraction: 0.25), isMeta: true),
        AchievementDefinition(id: "achv-meta-50", title: "Halfway There", subtitle: "Unlock 50% of all other achievements.", category: .meta, badgeSymbol: "crown.fill", condition: .unlockedFractionOfOthers(fraction: 0.5), isMeta: true),
        AchievementDefinition(id: "achv-meta-75", title: "Almost Everything", subtitle: "Unlock 75% of all other achievements.", category: .meta, badgeSymbol: "crown.fill", condition: .unlockedFractionOfOthers(fraction: 0.75), isMeta: true),
        AchievementDefinition(id: "achv-meta-100", title: "Completionist", subtitle: "Unlock every other achievement in the catalog.", category: .meta, badgeSymbol: "crown.fill", condition: .unlockedFractionOfOthers(fraction: 1.0), isMeta: true)
    ]
}
