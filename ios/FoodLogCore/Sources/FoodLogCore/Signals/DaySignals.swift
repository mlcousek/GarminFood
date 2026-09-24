// DaySignals.swift
//
// The per-nutrition-day picture of WHAT HAPPENED (design D5) that every
// gamification rule reads: entries with tags, time, meal and macros; macro
// totals incl. fibre/sugar; water; active kcal; Garmin activities; the
// day's weigh-in; the fasting verdict; day-note tags; and flags saying
// which of those sources actually had data. Built by `DaySignalsBuilder`
// (pure) from local stores and cached Garmin reads -- never the network.
//
// Deliberately PLAIN types only: no GarminKit type appears in any public
// signature here, because the Gamification package (which must not import
// GarminKit, see its Package.swift) consumes these directly.
//
// "Unknown" is modelled as `nil`, never as zero, so a rule can tell "no
// fibre data" from "0 g fibre" and a missing source never counts a day as
// failed (spec: "Missing water data").
//
// Depended on by: DaySignalsBuilder, Gamification's DayPredicate/
// SignalEvaluator/GamificationFeature, and every wave-2 feature.

import Foundation

/// The meal an entry belongs to. Mirrors Garmin's four meals without
/// naming GarminKit's `MealType`.
public enum SignalMeal: String, Sendable, Equatable, Hashable, Codable, CaseIterable {
    case breakfast, lunch, dinner, snack
}

/// Macro totals for a day. Each value is `nil` when at least one entry's
/// value is unknown -- a partial sum would under-report and make a
/// "≤ 40 g sugar" rule pass by accident.
public struct MacroTotals: Sendable, Equatable, Codable {
    public var calories: Double?
    public var protein: Double?
    public var carbs: Double?
    public var fat: Double?
    public var fiber: Double?
    public var sugar: Double?

    public init(
        calories: Double? = nil,
        protein: Double? = nil,
        carbs: Double? = nil,
        fat: Double? = nil,
        fiber: Double? = nil,
        sugar: Double? = nil
    ) {
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.fiber = fiber
        self.sugar = sugar
    }

    public static let zero = MacroTotals(calories: 0, protein: 0, carbs: 0, fat: 0, fiber: 0, sugar: 0)
}

/// The day's Garmin nutrition goals, as cached from its day log.
public struct MacroGoals: Sendable, Equatable, Codable {
    public var calories: Double?
    public var protein: Double?
    public var carbs: Double?
    public var fat: Double?

    public init(calories: Double? = nil, protein: Double? = nil, carbs: Double? = nil, fat: Double? = nil) {
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
    }
}

/// Gamification's four goal booleans (`DailyGoalStatus`), mirrored here as
/// plain values because FoodLogCore cannot see that Gamification type.
public struct SignalGoalStatus: Sendable, Equatable, Codable {
    public let metCalorieGoal: Bool
    public let metProteinGoal: Bool
    public let metCarbGoal: Bool
    public let metFatGoal: Bool

    public init(metCalorieGoal: Bool, metProteinGoal: Bool, metCarbGoal: Bool, metFatGoal: Bool) {
        self.metCalorieGoal = metCalorieGoal
        self.metProteinGoal = metProteinGoal
        self.metCarbGoal = metCarbGoal
        self.metFatGoal = metFatGoal
    }
}

/// A fast that ended on this day: kept or broken. `nil` on `DaySignals`
/// means not tracked / still running / fasting off.
public enum FastingOutcome: String, Sendable, Equatable, Codable {
    case kept, broken
}

/// Which sources had data for the day. A rule whose data is unavailable
/// does not evaluate (never a false "failed").
public struct SignalAvailability: Sendable, Equatable, Codable {
    /// A cached Garmin day log (digest) exists for the day.
    public var hasGarminLog: Bool
    /// Every entry's calories/protein/carbs/fat are known.
    public var hasMacros: Bool
    public var hasWater: Bool
    /// Garmin activities were read for the day (possibly zero of them).
    public var hasActivities: Bool
    public var hasWeight: Bool
    public var hasFasting: Bool

    public init(
        hasGarminLog: Bool = false,
        hasMacros: Bool = false,
        hasWater: Bool = false,
        hasActivities: Bool = false,
        hasWeight: Bool = false,
        hasFasting: Bool = false
    ) {
        self.hasGarminLog = hasGarminLog
        self.hasMacros = hasMacros
        self.hasWater = hasWater
        self.hasActivities = hasActivities
        self.hasWeight = hasWeight
        self.hasFasting = hasFasting
    }
}

/// One Garmin activity (run, walk, ride, ...), cached from the read-only
/// activities route. `start` is the UTC instant (parsed from
/// `startTimeGMT`); `day` is the LOCAL calendar date the activity belongs
/// to (from `startTimeLocal`), so time-zone travel cannot move it.
public struct ActivitySummary: Sendable, Equatable, Hashable, Codable, Identifiable {
    public let id: String
    public let typeKey: String
    public let day: String
    public let start: Date
    public let durationS: Double
    public let calories: Double?
    public let distanceM: Double?

    public init(
        id: String,
        typeKey: String,
        day: String,
        start: Date,
        durationS: Double,
        calories: Double? = nil,
        distanceM: Double? = nil
    ) {
        self.id = id
        self.typeKey = typeKey
        self.day = day
        self.start = start
        self.durationS = durationS
        self.calories = calories
        self.distanceM = distanceM
    }

    public var end: Date { start.addingTimeInterval(durationS) }
    public var durationMinutes: Double { durationS / 60 }
}

/// One logged food entry of a day, whichever source it came from.
public struct SignalEntry: Sendable, Equatable {
    public let foodId: String
    public let name: String?
    public let brand: String?
    public let barcode: String?
    public let tags: Set<FoodTag>
    public let timestamp: Date
    public let meal: SignalMeal
    public let calories: Double?
    public let protein: Double?
    public let carbs: Double?
    public let fat: Double?
    public let fiber: Double?
    public let sugar: Double?
    /// `true` when the entry came from the cached Garmin day log, `false`
    /// when it was added from the local usage history.
    public let fromGarminLog: Bool

    public init(
        foodId: String,
        name: String? = nil,
        brand: String? = nil,
        barcode: String? = nil,
        tags: Set<FoodTag> = [],
        timestamp: Date,
        meal: SignalMeal,
        calories: Double? = nil,
        protein: Double? = nil,
        carbs: Double? = nil,
        fat: Double? = nil,
        fiber: Double? = nil,
        sugar: Double? = nil,
        fromGarminLog: Bool = false
    ) {
        self.foodId = foodId
        self.name = name
        self.brand = brand
        self.barcode = barcode
        self.tags = tags
        self.timestamp = timestamp
        self.meal = meal
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.fiber = fiber
        self.sugar = sugar
        self.fromGarminLog = fromGarminLog
    }

    public func has(_ tag: FoodTag) -> Bool { tags.contains(tag) }
}

public struct DaySignals: Sendable, Equatable {
    /// `yyyy-MM-dd`, the logged nutrition date.
    public let day: String
    /// Start of that day in the builder's calendar.
    public let date: Date
    /// Sorted by timestamp.
    public let entries: [SignalEntry]
    public let totals: MacroTotals
    public let goals: MacroGoals?
    public let goalStatus: SignalGoalStatus?
    public let waterML: Double?
    public let waterGoalML: Double?
    public let activeKcal: Double?
    public let activities: [ActivitySummary]
    /// The last weigh-in of the day, kilograms.
    public let weighInKg: Double?
    public let fasting: FastingOutcome?
    public let noteTags: Set<DayNoteTag>
    public let availability: SignalAvailability

    public init(
        day: String,
        date: Date,
        entries: [SignalEntry] = [],
        totals: MacroTotals = .zero,
        goals: MacroGoals? = nil,
        goalStatus: SignalGoalStatus? = nil,
        waterML: Double? = nil,
        waterGoalML: Double? = nil,
        activeKcal: Double? = nil,
        activities: [ActivitySummary] = [],
        weighInKg: Double? = nil,
        fasting: FastingOutcome? = nil,
        noteTags: Set<DayNoteTag> = [],
        availability: SignalAvailability = SignalAvailability()
    ) {
        self.day = day
        self.date = date
        self.entries = entries
        self.totals = totals
        self.goals = goals
        self.goalStatus = goalStatus
        self.waterML = waterML
        self.waterGoalML = waterGoalML
        self.activeKcal = activeKcal
        self.activities = activities
        self.weighInKg = weighInKg
        self.fasting = fasting
        self.noteTags = noteTags
        self.availability = availability
    }

    public var hasEntries: Bool { !entries.isEmpty }
    public var firstLog: Date? { entries.first?.timestamp }
    public var lastLog: Date? { entries.last?.timestamp }

    public func entries(in meal: SignalMeal) -> [SignalEntry] {
        entries.filter { $0.meal == meal }
    }

    public func entries(tagged tag: FoodTag) -> [SignalEntry] {
        entries.filter { $0.tags.contains(tag) }
    }

    /// Every tag carried by any entry of the day.
    public var allTags: Set<FoodTag> {
        entries.reduce(into: Set<FoodTag>()) { $0.formUnion($1.tags) }
    }
}

/// The window of days features evaluate, plus the few lifetime facts a
/// 42-day window cannot answer on its own.
public struct SignalsSnapshot: Sendable, Equatable {
    /// Keyed by `yyyy-MM-dd`. Only days inside the window that had ANY
    /// data (an entry, water, an activity, a weigh-in, a fast, a note).
    public let days: [String: DaySignals]
    /// `yyyy-MM-dd` of "today" when the snapshot was built.
    public let today: String
    /// Every day of the window, oldest first, whether or not it has data.
    public let windowDays: [String]
    public let profile: ProfileSignals
    /// The first day each food id was ever seen in the retained history
    /// (usage events + cached day logs), for "a food never logged before".
    public let firstSeenDayByFood: [String: String]
    /// The first day each (folded) Czech brand was seen, for "a new Czech
    /// brand".
    public let firstSeenDayByCzechBrand: [String: String]

    public init(
        days: [String: DaySignals],
        today: String,
        windowDays: [String],
        profile: ProfileSignals = ProfileSignals(),
        firstSeenDayByFood: [String: String] = [:],
        firstSeenDayByCzechBrand: [String: String] = [:]
    ) {
        self.days = days
        self.today = today
        self.windowDays = windowDays
        self.profile = profile
        self.firstSeenDayByFood = firstSeenDayByFood
        self.firstSeenDayByCzechBrand = firstSeenDayByCzechBrand
    }

    public static let empty = SignalsSnapshot(days: [:], today: "", windowDays: [])

    /// Days with data, oldest first.
    public var orderedDays: [DaySignals] {
        windowDays.compactMap { days[$0] }
    }

    public func day(_ key: String) -> DaySignals? { days[key] }

    /// The data-bearing days among `keys`, in the given order.
    public func days(_ keys: [String]) -> [DaySignals] {
        keys.compactMap { days[$0] }
    }

    /// The last `count` window days ending at (and including) `today`.
    public func recentDayKeys(_ count: Int) -> [String] {
        guard count > 0 else { return [] }
        return Array(windowDays.suffix(count))
    }
}
