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
public enum ChallengeCatalog {
    public static let all: [ChallengeTemplate] = [
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
}
