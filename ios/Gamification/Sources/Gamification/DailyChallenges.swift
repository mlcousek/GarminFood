import Foundation

// DailyChallenges.swift
//
// daily-challenges spec's "exactly two daily challenges are active per
// nutrition-day, drawn from a large template pool" requirement
// (expand-gamification-depth design.md D3): single-day-scoped challenges,
// architecturally separate from the long-running `ChallengeStore` (which is
// deliberately single-slot and multi-day). Every `DailyChallengeKind` is
// evaluable purely from one day's `[UsageEvent]` plus that day's optional
// `DailyGoalStatus` -- see `DailyChallengeEngine.swift`.
public enum DailyChallengeKind: Sendable, Equatable {
    /// At least `count` entries logged today.
    case logAtLeast(count: Int)
    /// At least `count` DISTINCT foods logged today.
    case logDistinctFoods(count: Int)
    /// Something logged in `bucket`'s time-of-day window today.
    case logInMealSlot(bucket: MealTimeBucket)
    /// At least one entry logged today, but NOTHING in `bucket`'s window.
    case avoidMealSlot(bucket: MealTimeBucket)
    /// Today's calorie goal met.
    case hitCalorieGoal
    /// Today's `macro` goal met (protein/carbs/fat -- calories has its own
    /// dedicated `hitCalorieGoal` case).
    case hitMacroGoal(macro: GoalMacro)
    /// All four tracked goals met today.
    case hitAllGoals
    /// At least one food logged today that has never appeared anywhere
    /// else in the retained usage history before today.
    case tryNewFood
    /// All four `MealTimeBucket` values logged today.
    case logAllFourSlots
    /// Something logged before `beforeHour` (the event's real hour, not the
    /// coarser `MealTimeBucket`).
    case earlyLog(beforeHour: Int)
    /// Something logged at or after `afterHour`.
    case lateLog(afterHour: Int)
}

public struct DailyChallengeTemplate: Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let kind: DailyChallengeKind

    public init(id: String, title: String, subtitle: String, kind: DailyChallengeKind) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.kind = kind
    }
}

/// A template plus its completion state for today -- what the app layer
/// exposes to the UI (`GamificationEngine.todayDailyChallenges`).
public struct DailyChallengeDisplay: Identifiable, Sendable, Equatable {
    public let template: DailyChallengeTemplate
    public let isComplete: Bool
    public var id: String { template.id }

    public init(template: DailyChallengeTemplate, isComplete: Bool) {
        self.template = template
        self.isComplete = isComplete
    }
}

/// design.md D3: 120+ templates, leaning on flavor-text variation (several
/// differently-worded templates sharing the same underlying kind/params)
/// rather than mechanical novelty -- a player sees any one daily challenge
/// for a single day, so the writing carries the variety more than the
/// mechanics can. Every award is the flat `XPAward.dailyChallengeBonus`,
/// not a per-template amount, since these are meant to be frequent and
/// easy relative to the long-running catalog.
public enum DailyChallengeCatalog {
    public static let all: [DailyChallengeTemplate] = logAtLeastFamily
        + logDistinctFoodsFamily
        + logInMealSlotFamily
        + avoidMealSlotFamily
        + hitCalorieGoalFamily
        + hitMacroGoalFamily
        + hitAllGoalsFamily
        + tryNewFoodFamily
        + logAllFourSlotsFamily
        + earlyLogFamily
        + lateLogFamily

    private static func bucketDisplayName(_ bucket: MealTimeBucket) -> String {
        switch bucket {
        case .breakfast: return "Breakfast"
        case .lunch: return "Lunch"
        case .snack: return "Snack"
        case .dinner: return "Dinner"
        }
    }

    private static func macroDisplayName(_ macro: GoalMacro) -> String {
        switch macro {
        case .calories: return "Calorie"
        case .protein: return "Protein"
        case .carbs: return "Carb"
        case .fat: return "Fat"
        }
    }

    private static let logAtLeastFamily: [DailyChallengeTemplate] = {
        let tiers: [(count: Int, variants: [String])] = [
            (1, ["Just Log Something", "One and Done", "Log At Least One"]),
            (2, ["Just Two", "Double Log", "Two's Enough"]),
            (3, ["Triple Play", "Three's the Charm", "Log Three Today"]),
            (4, ["Four for the Day", "Quad Log", "Four-Peat"]),
            (5, ["High Five Today", "Five and Alive", "Take Five"]),
            (6, ["Six Strong", "Half a Dozen Logged", "Six for the Day"])
        ]
        return tiers.flatMap { tier -> [DailyChallengeTemplate] in
            tier.variants.enumerated().map { index, title in
                DailyChallengeTemplate(
                    id: "daily-log-\(tier.count)-\(index)",
                    title: title,
                    subtitle: "Log at least \(tier.count) entr\(tier.count == 1 ? "y" : "ies") today.",
                    kind: .logAtLeast(count: tier.count)
                )
            }
        }
    }()

    private static let logDistinctFoodsFamily: [DailyChallengeTemplate] = {
        let tiers: [(count: Int, variants: [String])] = [
            (2, ["Mix It Up", "Two Different Bites", "Double Variety"]),
            (3, ["Triple Variety", "Three Different Foods", "Mix Master"]),
            (4, ["Quad Variety", "Four Different Foods", "Variety Pack"]),
            (5, ["Five Flavors", "Five Different Foods", "Variety Champion"])
        ]
        return tiers.flatMap { tier -> [DailyChallengeTemplate] in
            tier.variants.enumerated().map { index, title in
                DailyChallengeTemplate(
                    id: "daily-distinct-\(tier.count)-\(index)",
                    title: title,
                    subtitle: "Log \(tier.count) different foods today.",
                    kind: .logDistinctFoods(count: tier.count)
                )
            }
        }
    }()

    private static let logInMealSlotFamily: [DailyChallengeTemplate] = {
        let variantsByBucket: [MealTimeBucket: [String]] = [
            .breakfast: ["Rise and Log", "Morning Fuel", "Breakfast Check-In", "First Bite of the Day"],
            .lunch: ["Midday Log", "Lunch Check-In", "Noon Nourishment", "Lunchtime Logged"],
            .snack: ["Snack Time Log", "Little Bite Logged", "Snack Check-In", "Small Bite Logged"],
            .dinner: ["Evening Log", "Dinner Check-In", "Nightfall Nourishment", "Supper Logged"]
        ]
        return MealTimeBucket.allCases.flatMap { bucket -> [DailyChallengeTemplate] in
            (variantsByBucket[bucket] ?? []).enumerated().map { index, title in
                DailyChallengeTemplate(
                    id: "daily-meal-\(bucket.rawValue)-\(index)",
                    title: title,
                    subtitle: "Log something during \(bucketDisplayName(bucket).lowercased()) hours today.",
                    kind: .logInMealSlot(bucket: bucket)
                )
            }
        }
    }()

    private static let avoidMealSlotFamily: [DailyChallengeTemplate] = {
        let variantsByBucket: [MealTimeBucket: [String]] = [
            .breakfast: ["Skip Breakfast Today", "Fasted Morning", "No AM Bites", "Intermittent Morning"],
            .lunch: ["Skip the Midday Meal", "Lunch-Free Today", "No Noon Nibbles", "Lunch on Pause"],
            .snack: ["No Snacking Today", "Snack-Free Day", "Resist the Snack", "Willpower Win"],
            .dinner: ["Light Evening", "No Dinner Tonight", "Early Stop", "Dinner Off Today"]
        ]
        return MealTimeBucket.allCases.flatMap { bucket -> [DailyChallengeTemplate] in
            (variantsByBucket[bucket] ?? []).enumerated().map { index, title in
                DailyChallengeTemplate(
                    id: "daily-avoid-\(bucket.rawValue)-\(index)",
                    title: title,
                    subtitle: "Log at least one thing today, but nothing during \(bucketDisplayName(bucket).lowercased()) hours.",
                    kind: .avoidMealSlot(bucket: bucket)
                )
            }
        }
    }()

    private static let hitCalorieGoalFamily: [DailyChallengeTemplate] = {
        let titles = ["Right on Target", "Calorie Bullseye", "Dialed In Today", "On the Number", "Calorie Precision", "Calorie Sniper", "Right in the Zone"]
        return titles.enumerated().map { index, title in
            DailyChallengeTemplate(
                id: "daily-calorie-goal-\(index)",
                title: title,
                subtitle: "Hit your calorie goal today.",
                kind: .hitCalorieGoal
            )
        }
    }()

    private static let hitMacroGoalFamily: [DailyChallengeTemplate] = {
        let macros: [GoalMacro] = [.protein, .carbs, .fat]
        let variantSuffixes = ["Target Hit", "Win", "Precision", "Perfectly Placed", "Nailed It"]
        return macros.flatMap { macro -> [DailyChallengeTemplate] in
            variantSuffixes.enumerated().map { index, suffix in
                DailyChallengeTemplate(
                    id: "daily-macro-\(macro.rawValue)-\(index)",
                    title: "\(macroDisplayName(macro)) \(suffix)",
                    subtitle: "Hit your \(macro.rawValue) goal today.",
                    kind: .hitMacroGoal(macro: macro)
                )
            }
        }
    }()

    private static let hitAllGoalsFamily: [DailyChallengeTemplate] = {
        let titles = ["Everything Aligned", "Full Goal Sweep", "Perfectly Balanced", "All Four Hit", "Nutrition Grand Slam", "Goals: Complete", "Clean Sweep", "Four for Four"]
        return titles.enumerated().map { index, title in
            DailyChallengeTemplate(
                id: "daily-all-goals-\(index)",
                title: title,
                subtitle: "Hit calories, protein, carbs AND fat today.",
                kind: .hitAllGoals
            )
        }
    }()

    private static let tryNewFoodFamily: [DailyChallengeTemplate] = {
        let titles = ["Something New", "First Taste Today", "Fresh Find", "New on the Menu", "Try Something Different", "Uncharted Bite", "Novelty Bite", "Unexplored Plate"]
        return titles.enumerated().map { index, title in
            DailyChallengeTemplate(
                id: "daily-new-food-\(index)",
                title: title,
                subtitle: "Log a food you haven't logged before.",
                kind: .tryNewFood
            )
        }
    }()

    private static let logAllFourSlotsFamily: [DailyChallengeTemplate] = {
        let titles = ["Full Course Today", "All Four Slots", "Breakfast to Dinner", "The Whole Day Logged", "Complete Coverage", "Four-Slot Finish"]
        return titles.enumerated().map { index, title in
            DailyChallengeTemplate(
                id: "daily-full-course-\(index)",
                title: title,
                subtitle: "Log breakfast, lunch, snack AND dinner today.",
                kind: .logAllFourSlots
            )
        }
    }()

    private static let earlyLogFamily: [DailyChallengeTemplate] = {
        let tiers: [(hour: Int, variants: [String])] = [
            (8, ["Early Riser", "Morning Momentum", "Up and At It"]),
            (7, ["Sunrise Logger", "Before-7 Bonus", "Dawn Patrol"]),
            (6, ["Before-6 Club", "Ultra Early Bird", "First Light Log"])
        ]
        return tiers.flatMap { tier -> [DailyChallengeTemplate] in
            tier.variants.enumerated().map { index, title in
                DailyChallengeTemplate(
                    id: "daily-early-\(tier.hour)-\(index)",
                    title: title,
                    subtitle: "Log something before \(tier.hour):00 today.",
                    kind: .earlyLog(beforeHour: tier.hour)
                )
            }
        }
    }()

    private static let lateLogFamily: [DailyChallengeTemplate] = {
        let tiers: [(hour: Int, variants: [String])] = [
            (19, ["Seven PM Sign-In", "Post-Dinner Ping", "Evening Echo"]),
            (20, ["Night Owl Check-In", "Evening Wrap-Up", "Late Log"]),
            (21, ["After Hours", "Nightcap Log", "Nine PM Nudge"])
        ]
        return tiers.flatMap { tier -> [DailyChallengeTemplate] in
            tier.variants.enumerated().map { index, title in
                DailyChallengeTemplate(
                    id: "daily-late-\(tier.hour)-\(index)",
                    title: title,
                    subtitle: "Log something at or after \(tier.hour):00 today.",
                    kind: .lateLog(afterHour: tier.hour)
                )
            }
        }
    }()
}
