import Foundation

// ChallengeTemplates.swift
//
// Challenges spec's "curated, hand-authored set" requirement (design.md D4,
// task 25.1): 13 templates, a plain data table (`ChallengeCatalog.all`)
// plus a shared, parameterised evaluation function (`ChallengeEngine`,
// separate file) -- deliberately NOT an authoring engine, per D4's explicit
// scope line.
//
// MEAL-TIME BUCKETS ARE A TIME-OF-DAY HEURISTIC, NOT THE REAL MEAL TYPE --
// worth being very explicit about, since a couple of these templates are
// styled directly on the proposal's own "log breakfast 5 days this week"
// example: `UsageEvent` (FoodLogCore/UsageHistory.swift) does NOT persist
// the `MealType` the user actually picked on the confirm screen -- only
// `foodId`/`servingId`/`numberOfUnits`/`timestamp`. The real, user-chosen
// meal type only ever reaches `GarminKit.Outbox`/Garmin's own log, neither
// of which this package reads. So "breakfast" here means "logged within
// the same generic time-of-day window `FoodLogCore.MealTypeDefaulting`
// itself defaults new entries from" -- intentionally mirroring those exact
// hour boundaries (rather than inventing different ones) so this package's
// idea of "breakfast time" agrees with the app's own default meal-type
// picker, even though the two are computed independently (this package
// does not depend on GarminKit, so it cannot name `GarminKit.MealType`
// itself -- see Package.swift's header for why that dependency was left
// out). If the user overrides the suggested meal type on the confirm
// screen (logs a 7am snack instead of breakfast, say), these templates
// will not know that. Accepted as a real, named limitation, not an
// oversight.
public enum MealTimeBucket: String, Sendable, Equatable, Codable, CaseIterable {
    case breakfast, lunch, snack, dinner

    /// Mirrors `FoodLogCore.MealTypeDefaulting.defaultMealType(for:calendar:)`'s
    /// windows exactly -- see this file's header for why they are
    /// duplicated here rather than shared.
    public static func bucket(for date: Date, calendar: Calendar = .current) -> MealTimeBucket {
        switch calendar.component(.hour, from: date) {
        case 4..<11: return .breakfast
        case 11..<15: return .lunch
        case 15..<18: return .snack
        default: return .dinner
        }
    }
}

public enum ChallengeCategory: String, Sendable, Equatable, Codable {
    case streakExtension, goalHitting, varietySeeking
}

/// A locally-evaluable completion condition (challenges spec's own
/// wording). Each case carries exactly the parameters its evaluation needs
/// -- see `ChallengeEngine.progress(for:...)`'s `switch` for how each is
/// read.
public enum ChallengeKind: Sendable, Equatable {
    /// Log on at least `minCount` distinct nutrition-days within the
    /// template's window (no grace -- unlike the streak itself, "Perfect
    /// Week" means every day, by design).
    case logOnDistinctDays(minCount: Int)
    /// Extend the streak (`StreakEngine`) by at least `byDays` beyond
    /// whatever it was when the challenge was activated.
    case extendStreakBy(days: Int)
    /// Meet `macro`'s goal on at least `minCount` days within the window
    /// (not necessarily consecutive).
    case goalHitDays(macro: GoalMacro, minCount: Int)
    /// Meet `macro`'s goal (or ANY goal, if `macro` is `nil`) on `minCount`
    /// CONSECUTIVE nutrition-days.
    case goalHitStreak(macro: GoalMacro?, minCount: Int)
    /// Log at least `minCount` foods that have never appeared anywhere
    /// else in the retained usage history before the window started.
    case newFoodsTried(minCount: Int)
    /// Log something in `bucket`'s time-of-day window on at least
    /// `minCount` distinct days within the window.
    case mealTimeOnDistinctDays(bucket: MealTimeBucket, minCount: Int)
    /// On at least `minDays` distinct days, log something in at least
    /// `minBucketsPerDay` different time-of-day buckets that same day.
    case multiMealDays(minBucketsPerDay: Int, minDays: Int)
    /// Log at least `minEntriesPerDay` entries on at least `minDays`
    /// distinct days.
    case busyDays(minEntriesPerDay: Int, minDays: Int)
    /// Log on both Saturday and Sunday of the same weekend, within the
    /// window.
    case weekendBothDays
    /// expand-gamification-depth design.md D2: on at least `minDays` days
    /// that had at least one entry logged, NOTHING was logged in `bucket`'s
    /// time-of-day window (a fully empty day never counts -- see
    /// `ChallengeEngine`'s evaluation).
    case mealSlotAbsent(bucket: MealTimeBucket, minDays: Int)
    /// All four tracked goals (calories, protein, carbs, fat) met the same
    /// day, on at least `minCount` days within the window.
    case allGoalsHitDays(minCount: Int)
    /// All four `MealTimeBucket` values logged in a single day, on at least
    /// `minDays` days -- stronger than `multiMealDays`, which only requires
    /// SOME N buckets.
    case allFourMealSlotsDays(minDays: Int)
    /// The identical `foodId` logged on at least `minDays` CONSECUTIVE
    /// nutrition-days.
    case sameFoodConsecutiveDays(minDays: Int)
    /// Generalizes `weekendBothDays` to at least `weekends` CONSECUTIVE
    /// weekends (Saturday AND Sunday both logged each time) within the
    /// window.
    case consecutiveWeekendsBothDays(weekends: Int)
}

public struct ChallengeTemplate: Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let category: ChallengeCategory
    /// How many days from activation the challenge has to be completed in
    /// before it rotates out uncompleted (challenges spec's "also rotates
    /// after a time window").
    public let windowDays: Int
    public let xpReward: Int
    public let kind: ChallengeKind

    public init(id: String, title: String, subtitle: String, category: ChallengeCategory, windowDays: Int, xpReward: Int, kind: ChallengeKind) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.category = category
        self.windowDays = windowDays
        self.xpReward = xpReward
        self.kind = kind
    }
}

/// The curated set (design.md D4: "V1 ships perhaps 10-15 challenge
/// templates"). Extending this is the expected "add-on" path (D4's own
/// closing line: "add a row + an evaluation function") -- not a rewrite.
///
/// expand-gamification-depth design.md D2: expanded from the original 13 to
/// 220+ by keeping every original template's id and content byte-for-byte
/// (ids are persisted on disk by `ChallengeStore`/`ChallengeHistoryStore`),
/// and adding a set of "blueprint" difficulty ladders below -- each family
/// is a small hand-written table of (count, title, subtitle) tiers, applied
/// once per relevant `GoalMacro`/`MealTimeBucket` where that axis applies,
/// rather than 200+ individually bespoke struct literals. Every generated
/// template still goes through the exact same `ChallengeEngine.progress`
/// evaluation as the original 13.
public enum ChallengeCatalog {
    public static let all: [ChallengeTemplate] =
        handAuthored
        + logStreakFamily
        + extendStreakFamily
        + goalHitDaysFamily
        + anyGoalStreakFamily
        + macroGoalStreakFamily
        + newFoodsFamily
        + mealTimeFamily
        + multiMealFamily
        + busyDaysFamily
        + mealSlotAbsentFamily
        + allGoalsFamily
        + fullCourseFamily
        + sameFoodFamily
        + weekendStreakFamily

    private static func macroDisplayName(_ macro: GoalMacro) -> String {
        switch macro {
        case .calories: return "Calorie"
        case .protein: return "Protein"
        case .carbs: return "Carb"
        case .fat: return "Fat"
        }
    }

    private static func bucketDisplayName(_ bucket: MealTimeBucket) -> String {
        switch bucket {
        case .breakfast: return "Breakfast"
        case .lunch: return "Lunch"
        case .snack: return "Snack"
        case .dinner: return "Dinner"
        }
    }

    private static let handAuthored: [ChallengeTemplate] = [
        ChallengeTemplate(
            id: "perfect-week",
            title: "Perfect Week",
            subtitle: "Log something every day for the next 7 days.",
            category: .streakExtension,
            windowDays: 7,
            xpReward: XPAward.challengeCompletionBonus,
            kind: .logOnDistinctDays(minCount: 7)
        ),
        ChallengeTemplate(
            id: "keep-the-flame-alive",
            title: "Keep the Flame Alive",
            subtitle: "Extend your streak by 3 more days.",
            category: .streakExtension,
            windowDays: 10,
            xpReward: XPAward.challengeCompletionBonus,
            kind: .extendStreakBy(days: 3)
        ),
        ChallengeTemplate(
            id: "protein-push",
            title: "Protein Push",
            subtitle: "Hit your protein goal on 4 of the next 5 days.",
            category: .goalHitting,
            windowDays: 5,
            xpReward: XPAward.challengeCompletionBonus,
            kind: .goalHitDays(macro: .protein, minCount: 4)
        ),
        ChallengeTemplate(
            id: "calorie-control",
            title: "Calorie Control",
            subtitle: "Hit your calorie goal on 5 of the next 7 days.",
            category: .goalHitting,
            windowDays: 7,
            xpReward: XPAward.challengeCompletionBonus,
            kind: .goalHitDays(macro: .calories, minCount: 5)
        ),
        ChallengeTemplate(
            id: "goal-getter",
            title: "Goal Getter",
            subtitle: "Hit any nutrition goal 3 days running.",
            category: .goalHitting,
            windowDays: 6,
            xpReward: XPAward.challengeCompletionBonus,
            kind: .goalHitStreak(macro: nil, minCount: 3)
        ),
        ChallengeTemplate(
            id: "carb-cutback",
            title: "Carb Cutback",
            subtitle: "Hit your carb goal on 4 of the next 6 days.",
            category: .goalHitting,
            windowDays: 6,
            xpReward: XPAward.challengeCompletionBonus,
            kind: .goalHitDays(macro: .carbs, minCount: 4)
        ),
        ChallengeTemplate(
            id: "try-something-new",
            title: "Try Something New",
            subtitle: "Log 3 foods you haven't logged before.",
            category: .varietySeeking,
            windowDays: 7,
            xpReward: XPAward.challengeCompletionBonus,
            kind: .newFoodsTried(minCount: 3)
        ),
        ChallengeTemplate(
            id: "explorer",
            title: "Explorer",
            subtitle: "Log 5 foods you haven't logged before.",
            category: .varietySeeking,
            windowDays: 10,
            xpReward: XPAward.challengeCompletionBonus,
            kind: .newFoodsTried(minCount: 5)
        ),
        ChallengeTemplate(
            id: "breakfast-club",
            title: "Breakfast Club",
            subtitle: "Log a breakfast-time entry 5 days this week.",
            category: .varietySeeking,
            windowDays: 7,
            xpReward: XPAward.challengeCompletionBonus,
            kind: .mealTimeOnDistinctDays(bucket: .breakfast, minCount: 5)
        ),
        ChallengeTemplate(
            id: "dinner-discipline",
            title: "Dinner Discipline",
            subtitle: "Log a dinner-time entry 4 days this week.",
            category: .varietySeeking,
            windowDays: 7,
            xpReward: XPAward.challengeCompletionBonus,
            kind: .mealTimeOnDistinctDays(bucket: .dinner, minCount: 4)
        ),
        ChallengeTemplate(
            id: "full-plate",
            title: "Full Plate",
            subtitle: "Log 3 different times of day, on 3 separate days.",
            category: .varietySeeking,
            windowDays: 7,
            xpReward: XPAward.challengeCompletionBonus,
            kind: .multiMealDays(minBucketsPerDay: 3, minDays: 3)
        ),
        ChallengeTemplate(
            id: "triple-threat",
            title: "Triple Threat",
            subtitle: "Log at least 3 entries in a day, on 3 separate days.",
            category: .varietySeeking,
            windowDays: 7,
            xpReward: XPAward.challengeCompletionBonus,
            kind: .busyDays(minEntriesPerDay: 3, minDays: 3)
        ),
        ChallengeTemplate(
            id: "weekend-warrior",
            title: "Weekend Warrior",
            subtitle: "Log on both Saturday and Sunday this weekend.",
            category: .varietySeeking,
            windowDays: 9,
            xpReward: XPAward.challengeCompletionBonus,
            kind: .weekendBothDays
        )
    ]

    private static let logStreakFamily: [ChallengeTemplate] = {
        let counts = [2, 3, 4, 5, 6, 8, 10, 12, 14, 18, 21, 25, 28, 30]
        let titles = ["Two's a Trend", "Three's Company", "Four-Day Foundation", "High Five", "Six and Steady", "Great Eight", "Perfect Ten", "Dozen Days", "Fortnight Focus", "Eighteen and Strong", "Three-Week Wonder", "Twenty-Five Club", "Twenty-Eight and Counting", "Thirty-Day Titan"]
        return counts.indices.map { i in
            let count = counts[i]
            return ChallengeTemplate(
                id: "log-streak-\(count)",
                title: titles[i],
                subtitle: "Log something on \(count) different days.",
                category: .streakExtension,
                windowDays: count + 2,
                xpReward: 20 + count * 6,
                kind: .logOnDistinctDays(minCount: count)
            )
        }
    }()

    private static let extendStreakFamily: [ChallengeTemplate] = {
        let days = [1, 2, 3, 5, 7, 10, 12, 14, 18, 21, 25, 30, 45, 60]
        let titles = ["Spark Starter", "Ember Grower", "Flame Fanner", "High Five Streak", "Week of Fire", "Double Digits", "Dozen of Days", "Fortnight Flame", "Eighteen Embers", "Three-Week Blaze", "Twenty-Five Alight", "Monthlong Inferno", "Six-Week Wildfire", "Two-Month Bonfire"]
        return days.indices.map { i in
            let day = days[i]
            return ChallengeTemplate(
                id: "extend-streak-\(day)",
                title: titles[i],
                subtitle: "Extend your streak by \(day) more day\(day == 1 ? "" : "s").",
                category: .streakExtension,
                windowDays: day * 2 + 2,
                xpReward: 25 + day * 7,
                kind: .extendStreakBy(days: day)
            )
        }
    }()

    private static let goalHitDaysFamily: [ChallengeTemplate] = {
        let counts = [3, 4, 5, 6, 7, 8, 9, 10, 12, 14]
        let titles = ["Starter", "Builder", "Climber", "Streak", "Steady", "Strong", "Sustained", "Marathon", "Champion", "Legend"]
        return GoalMacro.allCases.flatMap { macro -> [ChallengeTemplate] in
            counts.indices.map { i in
                let count = counts[i]
                return ChallengeTemplate(
                    id: "goal-days-\(macro.rawValue)-\(count)",
                    title: "\(macroDisplayName(macro)) \(titles[i])",
                    subtitle: "Hit your \(macro.rawValue) goal on \(count) days.",
                    category: .goalHitting,
                    windowDays: count + 3,
                    xpReward: 25 + count * 7,
                    kind: .goalHitDays(macro: macro, minCount: count)
                )
            }
        }
    }()

    private static let anyGoalStreakFamily: [ChallengeTemplate] = {
        let counts = [2, 3, 4, 5, 6, 7, 9, 14]
        let titles = ["Any-Goal Novice", "Any-Goal Apprentice", "Any-Goal Adept", "Any-Goal Expert", "Any-Goal Veteran", "Any-Goal Master", "Any-Goal Grandmaster", "Any-Goal Legend"]
        return counts.indices.map { i in
            let count = counts[i]
            return ChallengeTemplate(
                id: "goal-any-streak-\(count)",
                title: titles[i],
                subtitle: "Hit any nutrition goal \(count) days running.",
                category: .goalHitting,
                windowDays: count + 3,
                xpReward: 25 + count * 8,
                kind: .goalHitStreak(macro: nil, minCount: count)
            )
        }
    }()

    private static let macroGoalStreakFamily: [ChallengeTemplate] = {
        let counts = [2, 3, 4, 5, 6, 7, 9]
        let titles = ["Discipline I", "Discipline II", "Discipline III", "Discipline IV", "Discipline V", "Discipline VI", "Discipline VII"]
        return GoalMacro.allCases.flatMap { macro -> [ChallengeTemplate] in
            counts.indices.map { i in
                let count = counts[i]
                return ChallengeTemplate(
                    id: "goal-\(macro.rawValue)-streak-\(count)",
                    title: "\(macroDisplayName(macro)) \(titles[i])",
                    subtitle: "Hit your \(macro.rawValue) goal \(count) days running.",
                    category: .goalHitting,
                    windowDays: count + 3,
                    xpReward: 25 + count * 8,
                    kind: .goalHitStreak(macro: macro, minCount: count)
                )
            }
        }
    }()

    private static let newFoodsFamily: [ChallengeTemplate] = {
        let counts = [1, 2, 3, 4, 6, 8, 10, 12, 15, 20, 25, 30]
        let titles = ["First Taste", "Curious Palate", "Culinary Wanderer", "Flavor Scout", "Menu Explorer", "Globe Trotter", "Flavor Hunter", "Palate Pioneer", "Menu Maverick", "Connoisseur", "Gastronaut", "Omnivore Extraordinaire"]
        return counts.indices.map { i in
            let count = counts[i]
            return ChallengeTemplate(
                id: "new-foods-\(count)",
                title: titles[i],
                subtitle: "Log \(count) food\(count == 1 ? "" : "s") you haven't logged before.",
                category: .varietySeeking,
                windowDays: count * 2 + 3,
                xpReward: 20 + count * 8,
                kind: .newFoodsTried(minCount: count)
            )
        }
    }()

    private static let mealTimeFamily: [ChallengeTemplate] = {
        let counts = [2, 3, 4, 5, 7, 9, 12, 14]
        let titles = ["Casual", "Consistent", "Committed", "Devoted", "Disciplined", "Dedicated", "Relentless", "Unbreakable"]
        return MealTimeBucket.allCases.flatMap { bucket -> [ChallengeTemplate] in
            counts.indices.map { i in
                let count = counts[i]
                return ChallengeTemplate(
                    id: "meal-\(bucket.rawValue)-\(count)",
                    title: "\(bucketDisplayName(bucket)) Ritual: \(titles[i])",
                    subtitle: "Log a \(bucket.rawValue)-time entry on \(count) days.",
                    category: .varietySeeking,
                    windowDays: count + 2,
                    xpReward: 20 + count * 6,
                    kind: .mealTimeOnDistinctDays(bucket: bucket, minCount: count)
                )
            }
        }
    }()

    private static let multiMealFamily: [ChallengeTemplate] = [
        ChallengeTemplate(id: "multi-meal-2-4", title: "Two-a-Day", subtitle: "Log 2 different times of day, on 4 separate days.", category: .varietySeeking, windowDays: 6, xpReward: 60, kind: .multiMealDays(minBucketsPerDay: 2, minDays: 4)),
        ChallengeTemplate(id: "multi-meal-2-7", title: "Two-a-Day Week", subtitle: "Log 2 different times of day, on 7 separate days.", category: .varietySeeking, windowDays: 10, xpReward: 90, kind: .multiMealDays(minBucketsPerDay: 2, minDays: 7)),
        ChallengeTemplate(id: "multi-meal-3-5", title: "Full Plate Plus", subtitle: "Log 3 different times of day, on 5 separate days.", category: .varietySeeking, windowDays: 8, xpReward: 100, kind: .multiMealDays(minBucketsPerDay: 3, minDays: 5)),
        ChallengeTemplate(id: "multi-meal-3-7", title: "Full Plate Week", subtitle: "Log 3 different times of day, on 7 separate days.", category: .varietySeeking, windowDays: 10, xpReward: 130, kind: .multiMealDays(minBucketsPerDay: 3, minDays: 7)),
        ChallengeTemplate(id: "multi-meal-4-3", title: "Full House", subtitle: "Log all 4 times of day in one day, on 3 separate days.", category: .varietySeeking, windowDays: 6, xpReward: 110, kind: .multiMealDays(minBucketsPerDay: 4, minDays: 3)),
        ChallengeTemplate(id: "multi-meal-4-7", title: "Full House Week", subtitle: "Log all 4 times of day in one day, on 7 separate days.", category: .varietySeeking, windowDays: 10, xpReward: 180, kind: .multiMealDays(minBucketsPerDay: 4, minDays: 7))
    ]

    private static let busyDaysFamily: [ChallengeTemplate] = [
        ChallengeTemplate(id: "busy-days-2-5", title: "Double Up", subtitle: "Log at least 2 entries in a day, on 5 separate days.", category: .varietySeeking, windowDays: 7, xpReward: 70, kind: .busyDays(minEntriesPerDay: 2, minDays: 5)),
        ChallengeTemplate(id: "busy-days-2-7", title: "Double Up Week", subtitle: "Log at least 2 entries in a day, on 7 separate days.", category: .varietySeeking, windowDays: 9, xpReward: 95, kind: .busyDays(minEntriesPerDay: 2, minDays: 7)),
        ChallengeTemplate(id: "busy-days-4-3", title: "Quad Squad", subtitle: "Log at least 4 entries in a day, on 3 separate days.", category: .varietySeeking, windowDays: 6, xpReward: 90, kind: .busyDays(minEntriesPerDay: 4, minDays: 3)),
        ChallengeTemplate(id: "busy-days-4-5", title: "Quad Squad Week", subtitle: "Log at least 4 entries in a day, on 5 separate days.", category: .varietySeeking, windowDays: 8, xpReward: 130, kind: .busyDays(minEntriesPerDay: 4, minDays: 5)),
        ChallengeTemplate(id: "busy-days-5-4", title: "High Volume", subtitle: "Log at least 5 entries in a day, on 4 separate days.", category: .varietySeeking, windowDays: 8, xpReward: 120, kind: .busyDays(minEntriesPerDay: 5, minDays: 4)),
        ChallengeTemplate(id: "busy-days-6-3", title: "Power Days", subtitle: "Log at least 6 entries in a day, on 3 separate days.", category: .varietySeeking, windowDays: 7, xpReward: 130, kind: .busyDays(minEntriesPerDay: 6, minDays: 3))
    ]

    private static let mealSlotAbsentFamily: [ChallengeTemplate] = {
        let counts = [2, 3, 4, 5, 7, 9, 12]
        let titles = ["Willpower I", "Willpower II", "Willpower III", "Willpower IV", "Willpower V", "Willpower VI", "Willpower VII"]
        return MealTimeBucket.allCases.flatMap { bucket -> [ChallengeTemplate] in
            counts.indices.map { i in
                let count = counts[i]
                return ChallengeTemplate(
                    id: "absent-\(bucket.rawValue)-\(count)",
                    title: "\(bucketDisplayName(bucket))-Free: \(titles[i])",
                    subtitle: "Log something, but nothing in the \(bucket.rawValue) window, on \(count) days.",
                    category: .varietySeeking,
                    windowDays: count + 3,
                    xpReward: 25 + count * 7,
                    kind: .mealSlotAbsent(bucket: bucket, minDays: count)
                )
            }
        }
    }()

    private static let allGoalsFamily: [ChallengeTemplate] = {
        let counts = [1, 2, 3, 5, 7, 10, 14]
        let titles = ["Fully Dialed In", "All Green Twice", "Nutrition Perfectionist", "All-Star Week", "Dialed-In Week Plus", "Goal Machine", "Precision Fortnight"]
        return counts.indices.map { i in
            let count = counts[i]
            return ChallengeTemplate(
                id: "all-goals-\(count)",
                title: titles[i],
                subtitle: "Hit calories, protein, carbs AND fat the same day, \(count) time\(count == 1 ? "" : "s").",
                category: .goalHitting,
                windowDays: count + 3,
                xpReward: 30 + count * 9,
                kind: .allGoalsHitDays(minCount: count)
            )
        }
    }()

    private static let fullCourseFamily: [ChallengeTemplate] = {
        let counts = [1, 2, 3, 5, 7, 10]
        let titles = ["Full Course", "Full Course Duo", "Full Course Trio", "Full Course Week", "Full Course Fortnight", "Full Course Marathon"]
        return counts.indices.map { i in
            let count = counts[i]
            return ChallengeTemplate(
                id: "full-course-\(count)",
                title: titles[i],
                subtitle: "Log breakfast, lunch, snack AND dinner in one day, \(count) time\(count == 1 ? "" : "s").",
                category: .varietySeeking,
                windowDays: count + 3,
                xpReward: 30 + count * 10,
                kind: .allFourMealSlotsDays(minDays: count)
            )
        }
    }()

    private static let sameFoodFamily: [ChallengeTemplate] = {
        let counts = [2, 3, 4, 5, 7, 10, 14]
        let titles = ["Creature of Habit", "Comfort Food Streak", "Signature Dish", "On Repeat", "The Regular", "Same Old, Same Gold", "Ritual Eater"]
        return counts.indices.map { i in
            let count = counts[i]
            return ChallengeTemplate(
                id: "same-food-\(count)",
                title: titles[i],
                subtitle: "Log the identical food \(count) days running.",
                category: .varietySeeking,
                windowDays: count + 3,
                xpReward: 25 + count * 8,
                kind: .sameFoodConsecutiveDays(minDays: count)
            )
        }
    }()

    private static let weekendStreakFamily: [ChallengeTemplate] = {
        let counts = [2, 3, 4, 5, 6]
        let titles = ["Weekend Duo", "Weekend Trio", "Weekend Champion", "Weekend Streak", "Weekend Legend"]
        return counts.indices.map { i in
            let count = counts[i]
            return ChallengeTemplate(
                id: "weekend-streak-\(count)",
                title: titles[i],
                subtitle: "Log both Saturday and Sunday, \(count) weekends in a row.",
                category: .varietySeeking,
                windowDays: count * 7 + 2,
                xpReward: 40 + count * 15,
                kind: .consecutiveWeekendsBothDays(weekends: count)
            )
        }
    }()
}
