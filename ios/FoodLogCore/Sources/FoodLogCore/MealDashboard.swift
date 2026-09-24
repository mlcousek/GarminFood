// MealDashboard.swift
//
// The Today screen's data, organised the way Garmin Connect's food page is:
// meal by meal, each with its foods and consumed-vs-suggested calories and
// macros (add-app-shell-and-meal-dashboard, meal-dashboard spec, design D2).
//
// Pure: a `DailyFoodLog` (GET /nutrition-service/food/logs/{date}, 200 on
// 2026-09-16), the outbox's queued entries and the locally cached foods in,
// a `DayDashboard` out. Everything a test can check lives here; the app
// target only loads the inputs and draws the result.
//
// Evidence behind the rules (probed 2026-09-16):
// - every `mealDetails[]` item carries `mealNutritionGoals`, including
//   `adjusted*` variants that add burned calories on top of the plan
//   (deliberately NOT used as the target since 2026-09-23 -- see `target`);
// - a meal with nothing logged returns an EMPTY `mealNutritionContent`;
// - `meal.startTime`/`endTime` exist for breakfast, lunch and dinner, and
//   not for snacks.

import Foundation
import GarminKit

// MARK: - Progress against a target

/// Consumed versus target for one nutrient. `state` uses the same +/-10%
/// band as `TodaySummary.GoalState`, so a meal and the day never disagree
/// about what "on target" means.
public struct MacroProgress: Sendable, Equatable {
    public let consumed: Double
    public let goal: Double?

    public init(consumed: Double, goal: Double?) {
        self.consumed = consumed
        self.goal = goal
    }

    /// 0...1 share of the target, for bars; `nil` without a usable target.
    public var fraction: Double? {
        guard let goal, goal > 0 else { return nil }
        return min(max(consumed / goal, 0), 1)
    }

    /// 2026-09-21 bug fix: this used to guard only `goal != nil`, while its
    /// siblings `fraction`/`state` both guard `goal > 0` (a `0` goal is
    /// "no usable target", same as no goal at all). If Garmin ever sends an
    /// explicit `0` rather than omitting the field, `fraction`/`state`
    /// correctly read it as "no goal" while `remaining` returned a large
    /// negative number for the same value -- e.g. the calorie ring showing
    /// "no goal" right next to text saying "1800 kcal over."
    public var remaining: Double? {
        guard let goal, goal > 0 else { return nil }
        return goal - consumed
    }

    public var state: TodaySummary.GoalState {
        guard let goal, goal > 0 else { return .noGoal }
        let ratio = consumed / goal
        if ratio > 1.10 { return .over }
        if ratio >= 0.90 { return .onTarget }
        return .under
    }
}

public struct NutrientTotals: Sendable, Equatable {
    public let calories: MacroProgress
    public let carbs: MacroProgress
    public let protein: MacroProgress
    public let fat: MacroProgress

    public init(calories: MacroProgress, carbs: MacroProgress, protein: MacroProgress, fat: MacroProgress) {
        self.calories = calories
        self.carbs = carbs
        self.protein = protein
        self.fat = fat
    }
}

// MARK: - Detailed nutrients

/// 2026-09-22 (implement-micronutrients): `vitaminB1`...`omega6` are new.
/// They deliberately CANNOT appear via `MealDashboard.nutrients(content:
/// totals:)` -- Garmin's own daily/meal log aggregate (`DailyNutritionContent`,
/// GarminModels.swift) has no such fields, full stop, confirmed by re-reading
/// every field that struct and `NutritionContent` already decode. They exist
/// on this enum so a single `Food`/`Serving`'s own richer panel (Open Food
/// Facts only -- see `Serving`'s header comment in Food.swift) can reuse the
/// same `NutrientKind`/`NutrientAmount` display types via `Serving.
/// detailedNutrients`, rather than inventing a parallel enum for the exact
/// same "kind + value, only if present" shape.
public enum NutrientKind: String, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    case calories, carbs, fiber, sugar, protein, fat
    case saturatedFat, monounsaturatedFat, polyunsaturatedFat
    case cholesterol, sodium, potassium, vitaminA, vitaminC, calcium, iron
    // New in implement-micronutrients (2026-09-22) -- Open Food Facts only,
    // never populated by `MealDashboard`'s Garmin-fed pipeline. Appended
    // after `iron` rather than interleaved so existing enumeration order
    // (and the tests that assert on it) is unaffected.
    case vitaminB1, vitaminB2, vitaminB3, vitaminB5, vitaminB6, vitaminB9, vitaminB12
    case vitaminD, vitaminE, vitaminK
    case magnesium, zinc, phosphorus, selenium, copper, manganese, iodine
    case omega3, omega6

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .calories: return String(localized: "Calories", bundle: .module, comment: "Nutrient name.")
        case .carbs: return String(localized: "Carbohydrates", bundle: .module, comment: "Nutrient name.")
        case .fiber: return String(localized: "Fiber", bundle: .module, comment: "Nutrient name.")
        case .sugar: return String(localized: "Sugar", bundle: .module, comment: "Nutrient name.")
        case .protein: return String(localized: "Protein", bundle: .module, comment: "Nutrient name.")
        case .fat: return String(localized: "Fat", bundle: .module, comment: "Nutrient name.")
        case .saturatedFat: return String(localized: "Saturated fat", bundle: .module, comment: "Nutrient name.")
        case .monounsaturatedFat: return String(localized: "Monounsaturated fat", bundle: .module, comment: "Nutrient name.")
        case .polyunsaturatedFat: return String(localized: "Polyunsaturated fat", bundle: .module, comment: "Nutrient name.")
        case .cholesterol: return String(localized: "Cholesterol", bundle: .module, comment: "Nutrient name.")
        case .sodium: return String(localized: "Sodium", bundle: .module, comment: "Nutrient name.")
        case .potassium: return String(localized: "Potassium", bundle: .module, comment: "Nutrient name.")
        case .vitaminA: return String(localized: "Vitamin A", bundle: .module, comment: "Nutrient name.")
        case .vitaminC: return String(localized: "Vitamin C", bundle: .module, comment: "Nutrient name.")
        case .calcium: return String(localized: "Calcium", bundle: .module, comment: "Nutrient name.")
        case .iron: return String(localized: "Iron", bundle: .module, comment: "Nutrient name.")
        case .vitaminB1: return String(localized: "Vitamin B1 (Thiamin)", bundle: .module, comment: "Nutrient name.")
        case .vitaminB2: return String(localized: "Vitamin B2 (Riboflavin)", bundle: .module, comment: "Nutrient name.")
        case .vitaminB3: return String(localized: "Vitamin B3 (Niacin)", bundle: .module, comment: "Nutrient name.")
        case .vitaminB5: return String(localized: "Vitamin B5 (Pantothenic acid)", bundle: .module, comment: "Nutrient name.")
        case .vitaminB6: return String(localized: "Vitamin B6", bundle: .module, comment: "Nutrient name.")
        case .vitaminB9: return String(localized: "Folate (B9)", bundle: .module, comment: "Nutrient name.")
        case .vitaminB12: return String(localized: "Vitamin B12", bundle: .module, comment: "Nutrient name.")
        case .vitaminD: return String(localized: "Vitamin D", bundle: .module, comment: "Nutrient name.")
        case .vitaminE: return String(localized: "Vitamin E", bundle: .module, comment: "Nutrient name.")
        case .vitaminK: return String(localized: "Vitamin K", bundle: .module, comment: "Nutrient name.")
        case .magnesium: return String(localized: "Magnesium", bundle: .module, comment: "Nutrient name.")
        case .zinc: return String(localized: "Zinc", bundle: .module, comment: "Nutrient name.")
        case .phosphorus: return String(localized: "Phosphorus", bundle: .module, comment: "Nutrient name.")
        case .selenium: return String(localized: "Selenium", bundle: .module, comment: "Nutrient name.")
        case .copper: return String(localized: "Copper", bundle: .module, comment: "Nutrient name.")
        case .manganese: return String(localized: "Manganese", bundle: .module, comment: "Nutrient name.")
        case .iodine: return String(localized: "Iodine", bundle: .module, comment: "Nutrient name.")
        case .omega3: return String(localized: "Omega-3", bundle: .module, comment: "Nutrient name.")
        case .omega6: return String(localized: "Omega-6", bundle: .module, comment: "Nutrient name.")
        }
    }

    /// Units as Garmin reports them for the original set. Vitamins and
    /// minerals come back as a percentage of the daily value, the way
    /// FatSecret publishes them. The new (Open Food Facts only) nutrients
    /// below use OFF's own per-serving mg/µg convention instead -- see
    /// `Serving`'s header comment in Food.swift for why these two
    /// vocabularies are never mixed into the same field/kind.
    public var unit: String {
        switch self {
        case .calories: return "kcal"
        case .carbs, .fiber, .sugar, .protein, .fat, .saturatedFat, .monounsaturatedFat, .polyunsaturatedFat: return "g"
        case .cholesterol, .sodium, .potassium: return "mg"
        case .vitaminA, .vitaminC, .calcium, .iron: return "%"
        case .vitaminB1, .vitaminB2, .vitaminB3, .vitaminB5, .vitaminB6: return "mg"
        case .vitaminB9, .vitaminB12: return "µg"
        case .vitaminD: return "µg"
        case .vitaminE: return "mg"
        case .vitaminK: return "µg"
        case .magnesium, .zinc, .phosphorus, .copper, .manganese: return "mg"
        case .selenium, .iodine: return "µg"
        case .omega3, .omega6: return "mg"
        }
    }

    /// Nested under another nutrient in a breakdown (fiber under carbs).
    public var isSubNutrient: Bool {
        switch self {
        case .fiber, .sugar, .saturatedFat, .monounsaturatedFat, .polyunsaturatedFat: return true
        default: return false
        }
    }

    /// Which section of a grouped breakdown this belongs in (design ask:
    /// "Group by type (vitamins vs. minerals) if that reads better than one
    /// flat list" -- `LogEntryConfirmView`'s nutrition section uses this).
    public var group: NutrientGroup {
        switch self {
        case .calories: return .energy
        case .carbs, .fiber, .sugar, .protein, .fat,
             .saturatedFat, .monounsaturatedFat, .polyunsaturatedFat,
             .cholesterol, .omega3, .omega6: return .macronutrient
        case .vitaminA, .vitaminC, .vitaminB1, .vitaminB2, .vitaminB3, .vitaminB5, .vitaminB6,
             .vitaminB9, .vitaminB12, .vitaminD, .vitaminE, .vitaminK: return .vitamin
        case .sodium, .potassium, .calcium, .iron,
             .magnesium, .zinc, .phosphorus, .selenium, .copper, .manganese, .iodine: return .mineral
        }
    }
}

/// A grouped-breakdown section, per `NutrientKind.group`.
public enum NutrientGroup: String, Sendable, Equatable, CaseIterable {
    case energy, macronutrient, vitamin, mineral

    public var displayName: String {
        switch self {
        case .energy: return String(localized: "Energy", bundle: .module, comment: "Section header in a nutrition breakdown.")
        case .macronutrient: return String(localized: "Macronutrients", bundle: .module, comment: "Section header in a nutrition breakdown.")
        case .vitamin: return String(localized: "Vitamins", bundle: .module, comment: "Section header in a nutrition breakdown.")
        case .mineral: return String(localized: "Minerals", bundle: .module, comment: "Section header in a nutrition breakdown.")
        }
    }
}

public struct NutrientAmount: Sendable, Equatable, Identifiable {
    public let kind: NutrientKind
    public let value: Double
    public var id: NutrientKind { kind }

    public init(kind: NutrientKind, value: Double) {
        self.kind = kind
        self.value = value
    }
}

// MARK: - Entries and sections

public struct MealEntry: Sendable, Equatable, Identifiable {
    public enum Status: Sendable, Equatable {
        /// In Garmin's log; `logId` deletes it there.
        case synced(logId: String)
        /// Queued in the outbox and not yet in Garmin's log.
        case syncing(outboxId: UUID)
        /// Queued, but delivery gave up; needs a retry or a delete.
        case failed(outboxId: UUID, reason: String?)
    }

    public let id: String
    public let foodId: String
    public let name: String
    public let brandName: String?
    /// How many servings were logged.
    public let servingQty: Double
    /// e.g. "100 g" or "1 medium", when known.
    public let servingDescription: String?
    public let calories: Double?
    public let carbs: Double?
    public let protein: Double?
    public let fat: Double?
    public let status: Status
    /// add-log-entry-editing: what re-logging this entry needs (an edit's
    /// replacement, a duplicate). `nil` when unknown -- then the entry can
    /// only be deleted, like a calories-only quick add.
    public let mealType: MealType?
    public let servingId: String?
    /// One serving's nutrition, as Garmin read it back (or the cached food's
    /// serving for a queued entry) -- the edit sheet's live kcal.
    public let serving: Serving?
    public let source: GarminFoodSource?
    public let regionCode: String?
    public let languageCode: String?
    /// Set while this row is a queued edit of a Garmin entry: the `logId`
    /// the edit replaces (design.md D3's "marked pending").
    public let replacesLogId: String?

    public init(
        id: String,
        foodId: String,
        name: String,
        brandName: String?,
        servingQty: Double,
        servingDescription: String?,
        calories: Double?,
        carbs: Double?,
        protein: Double?,
        fat: Double?,
        status: Status,
        mealType: MealType? = nil,
        servingId: String? = nil,
        serving: Serving? = nil,
        source: GarminFoodSource? = nil,
        regionCode: String? = nil,
        languageCode: String? = nil,
        replacesLogId: String? = nil
    ) {
        self.id = id
        self.foodId = foodId
        self.name = name
        self.brandName = brandName
        self.servingQty = servingQty
        self.servingDescription = servingDescription
        self.calories = calories
        self.carbs = carbs
        self.protein = protein
        self.fat = fat
        self.status = status
        self.mealType = mealType
        self.servingId = servingId
        self.serving = serving
        self.source = source
        self.regionCode = regionCode
        self.languageCode = languageCode
        self.replacesLogId = replacesLogId
    }

    public var isSynced: Bool {
        if case .synced = status { return true }
        return false
    }

    /// The Garmin `logId`, for a synced entry that has one.
    public var syncedLogId: String? {
        guard case .synced(let logId) = status, !logId.isEmpty else { return nil }
        return logId
    }

    /// Whether this entry carries enough identity to be logged again with
    /// a different amount or meal (add-log-entry-editing). Quick-add
    /// entries (no food or serving id) can only be deleted.
    public var canRelog: Bool {
        guard !foodId.isEmpty, let servingId, !servingId.isEmpty, mealType != nil else { return false }
        if case .synced = status { return syncedLogId != nil }
        return true
    }

    /// Calories for `quantity` servings, from the per-serving nutrition, or
    /// by scaling this entry's own total when that is all there is.
    public func calories(forQuantity quantity: Double) -> Double? {
        if let perServing = serving?.calories { return perServing * quantity }
        guard let calories, servingQty > 0 else { return nil }
        return calories / servingQty * quantity
    }
}

/// A meal's time window in seconds since local midnight.
public struct MealWindow: Sendable, Equatable {
    public let mealType: MealType
    public let start: Int
    public let end: Int

    public init(mealType: MealType, start: Int, end: Int) {
        self.mealType = mealType
        self.start = start
        self.end = end
    }

    public func contains(secondsOfDay: Int) -> Bool {
        secondsOfDay >= start && secondsOfDay <= end
    }
}

public struct MealSection: Sendable, Equatable, Identifiable {
    public let mealType: MealType
    public let window: MealWindow?
    public let totals: NutrientTotals
    /// Every nutrient Garmin returned for this meal, in display order, plus
    /// the queued entries' share of calories and macros.
    public let nutrients: [NutrientAmount]
    public let entries: [MealEntry]
    public var id: MealType { mealType }

    public var hasPendingEntries: Bool {
        entries.contains { !$0.isSynced }
    }
}

public struct DayDashboard: Sendable, Equatable {
    public let date: String
    public let totals: NutrientTotals
    public let sections: [MealSection]
    /// `false` when no Garmin log was available, so the numbers come only
    /// from queued entries.
    public let hasGarminData: Bool

    public var windows: [MealWindow] {
        sections.compactMap(\.window)
    }

    public func section(for mealType: MealType) -> MealSection? {
        sections.first { $0.mealType == mealType }
    }
}

// MARK: - Building a day

public enum MealDashboard {
    /// Garmin Connect's order. `MealType.allCases` puts snacks before dinner.
    public static let defaultOrder: [MealType] = [.breakfast, .lunch, .dinner, .snacks]

    /// - Parameters:
    ///   - date: `yyyy-MM-dd`, the day being shown.
    ///   - log: Garmin's log for `date`, or `nil` if it couldn't be loaded.
    ///   - meals: meal definitions from `GET /nutrition-service/meals/{date}`,
    ///     used for windows when the log has none (e.g. it failed to load).
    ///   - outboxEntries: every outbox entry; only those for `date` that
    ///     Garmin hasn't accepted (or that were accepted but aren't in
    ///     `log` yet) are shown.
    ///   - foods: cached foods by id, to name and size queued entries.
    public static func build(
        date: String,
        log: DailyFoodLog?,
        meals: [Meal] = [],
        outboxEntries: [OutboxEntry],
        foods: [String: Food]
    ) -> DayDashboard {
        let details = log?.mealDetails ?? []
        var detailByType: [MealType: MealDetail] = [:]
        for detail in details {
            guard let name = detail.meal?.mealName, let type = MealType(rawValue: name) else { continue }
            if detailByType[type] == nil { detailByType[type] = detail }
        }
        var mealByType: [MealType: Meal] = [:]
        for meal in meals {
            guard let name = meal.mealName, let type = MealType(rawValue: name) else { continue }
            if mealByType[type] == nil { mealByType[type] = meal }
        }

        let order = mealOrder(details: detailByType, meals: mealByType)
        let queued = outboxEntries.filter { $0.date == date }
        // add-log-entry-editing D3: an edit overlays Garmin's read-back --
        // the entry it replaces is hidden (and its share taken off Garmin's
        // totals) until the replace lands. Not while the replace is parked:
        // then the old entry really is still in Garmin, and hiding it would
        // make the duplicate silent.
        let hiddenLogIds = Set(queued.compactMap { entry -> String? in
            guard let replaced = entry.replaces, replaced.date == date, !entry.isParkedReplace else { return nil }
            return replaced.logId
        })
        var loggedById: [String: LoggedFood] = [:]
        for detail in details {
            for food in detail.loggedFoods ?? [] {
                guard let logId = food.logId, !logId.isEmpty, loggedById[logId] == nil else { continue }
                loggedById[logId] = food
            }
        }

        var sections: [MealSection] = []
        var hiddenAll: [MealEntry] = []
        for type in order {
            let detail = detailByType[type]
            let meal = detail?.meal ?? mealByType[type]
            let logged = detail?.loggedFoods ?? []
            let visible = logged.filter { !isHidden($0, hiddenLogIds) }
            let hidden = syncedEntries(logged.filter { isHidden($0, hiddenLogIds) }, mealType: type)
            hiddenAll.append(contentsOf: hidden)
            let synced = syncedEntries(visible, mealType: type)
            let pending = pendingEntries(
                queued.filter { $0.mealType == type },
                logged: visible,
                foods: foods,
                mealType: type,
                loggedById: loggedById
            )
            sections.append(section(
                type: type,
                meal: meal,
                content: detail?.mealNutritionContent,
                goals: detail?.mealNutritionGoals,
                synced: synced,
                pending: pending,
                hidden: hidden
            ))
        }

        let dayContent = log?.dailyNutritionContent
        let dayGoals = log?.dailyNutritionGoals
        let pendingAll = sections.flatMap(\.entries).filter { !$0.isSynced }
        let totals = NutrientTotals(
            calories: MacroProgress(consumed: (dayContent?.calories ?? 0) - sum(hiddenAll, \.calories) + sum(pendingAll, \.calories), goal: target(dayGoals?.adjustedCalories, dayGoals?.calories)),
            carbs: MacroProgress(consumed: (dayContent?.carbs ?? 0) - sum(hiddenAll, \.carbs) + sum(pendingAll, \.carbs), goal: target(dayGoals?.adjustedCarbs, dayGoals?.carbs)),
            protein: MacroProgress(consumed: (dayContent?.protein ?? 0) - sum(hiddenAll, \.protein) + sum(pendingAll, \.protein), goal: target(dayGoals?.adjustedProtein, dayGoals?.protein)),
            fat: MacroProgress(consumed: (dayContent?.fat ?? 0) - sum(hiddenAll, \.fat) + sum(pendingAll, \.fat), goal: target(dayGoals?.adjustedFat, dayGoals?.fat))
        )

        return DayDashboard(date: date, totals: totals, sections: sections, hasGarminData: log != nil)
    }

    // MARK: Order

    static func mealOrder(details: [MealType: MealDetail], meals: [MealType: Meal]) -> [MealType] {
        var displayOrder: [MealType: Int] = [:]
        for type in defaultOrder {
            if let order = details[type]?.meal?.displayOrder ?? meals[type]?.displayOrder {
                displayOrder[type] = order
            }
        }
        // Only trust Garmin's order when every meal has one; a partial set
        // can't be merged with the default without guessing.
        guard displayOrder.count == defaultOrder.count else { return defaultOrder }
        return defaultOrder.sorted { (displayOrder[$0] ?? 0) < (displayOrder[$1] ?? 0) }
    }

    // MARK: Sections

    static func section(
        type: MealType,
        meal: Meal?,
        content: DailyNutritionContent?,
        goals: NutritionGoals?,
        synced: [MealEntry],
        pending: [MealEntry],
        hidden: [MealEntry] = []
    ) -> MealSection {
        // `hidden`: Garmin entries an edit replaces (D3). Still inside
        // Garmin's own meal total, so their share comes off it here.
        let pendingCalories = sum(pending, \.calories) - sum(hidden, \.calories)
        let pendingCarbs = sum(pending, \.carbs) - sum(hidden, \.carbs)
        let pendingProtein = sum(pending, \.protein) - sum(hidden, \.protein)
        let pendingFat = sum(pending, \.fat) - sum(hidden, \.fat)

        let totals = NutrientTotals(
            calories: MacroProgress(consumed: (content?.calories ?? 0) + pendingCalories, goal: target(goals?.adjustedCalories, goals?.calories)),
            carbs: MacroProgress(consumed: (content?.carbs ?? 0) + pendingCarbs, goal: target(goals?.adjustedCarbs, goals?.carbs)),
            protein: MacroProgress(consumed: (content?.protein ?? 0) + pendingProtein, goal: target(goals?.adjustedProtein, goals?.protein)),
            fat: MacroProgress(consumed: (content?.fat ?? 0) + pendingFat, goal: target(goals?.adjustedFat, goals?.fat))
        )

        return MealSection(
            mealType: type,
            window: window(for: type, meal: meal),
            totals: totals,
            nutrients: nutrients(content: content, totals: totals),
            entries: synced + pending
        )
    }

    /// The four headline values always appear (as totals, so they include
    /// queued entries). The rest appear only when Garmin returned them.
    ///
    /// `vitaminB1`...`omega6` always resolve to `nil` here, deliberately --
    /// `DailyNutritionContent` (Garmin's own daily/meal aggregate) has no
    /// such fields at all, so there is nothing genuine to surface at this
    /// level; see `NutrientKind`'s header comment. A single food's own
    /// richer Open-Food-Facts-sourced panel is shown separately, via
    /// `Serving.detailedNutrients` (Food.swift), not synthesized into this
    /// day/meal total.
    static func nutrients(content: DailyNutritionContent?, totals: NutrientTotals) -> [NutrientAmount] {
        var result: [NutrientAmount] = []
        for kind in NutrientKind.allCases {
            let value: Double?
            switch kind {
            case .calories: value = totals.calories.consumed
            case .carbs: value = totals.carbs.consumed
            case .protein: value = totals.protein.consumed
            case .fat: value = totals.fat.consumed
            case .fiber: value = content?.fiber
            case .sugar: value = content?.sugar
            case .saturatedFat: value = content?.saturatedFat
            case .monounsaturatedFat: value = content?.monounsaturatedFat
            case .polyunsaturatedFat: value = content?.polyunsaturatedFat
            case .cholesterol: value = content?.cholesterol
            case .sodium: value = content?.sodium
            case .potassium: value = content?.potassium
            case .vitaminA: value = content?.vitaminA
            case .vitaminC: value = content?.vitaminC
            case .calcium: value = content?.calcium
            case .iron: value = content?.iron
            case .vitaminB1, .vitaminB2, .vitaminB3, .vitaminB5, .vitaminB6, .vitaminB9, .vitaminB12,
                 .vitaminD, .vitaminE, .vitaminK,
                 .magnesium, .zinc, .phosphorus, .selenium, .copper, .manganese, .iodine,
                 .omega3, .omega6:
                value = nil
            }
            if let value {
                result.append(NutrientAmount(kind: kind, value: value))
            }
        }
        return result
    }

    static func window(for type: MealType, meal: Meal?) -> MealWindow? {
        guard
            let startTime = meal?.startTime, let start = secondsOfDay(startTime),
            let endTime = meal?.endTime, let end = secondsOfDay(endTime)
        else { return nil }
        return MealWindow(mealType: type, start: start, end: end)
    }

    // MARK: Entries

    static func isHidden(_ food: LoggedFood, _ hiddenLogIds: Set<String>) -> Bool {
        guard let logId = food.logId, !logId.isEmpty else { return false }
        return hiddenLogIds.contains(logId)
    }

    static func syncedEntries(_ logged: [LoggedFood], mealType: MealType? = nil) -> [MealEntry] {
        var entries: [MealEntry] = []
        for (index, food) in logged.enumerated() {
            let logId = food.logId ?? ""
            let qty = food.servingQty ?? 1
            let content = food.nutritionContent
            let serving = servingDescription(unit: content?.servingUnit, numberOfUnits: content?.numberOfUnits)
            let meta = food.foodMetaData
            entries.append(MealEntry(
                id: logId.isEmpty ? "synced-\(index)-\(food.foodId ?? "")" : logId,
                foodId: food.foodId ?? "",
                name: meta?.foodName ?? "Unnamed food",
                brandName: meta?.brandName,
                servingQty: qty,
                servingDescription: serving,
                calories: content?.calories.map { $0 * qty },
                carbs: content?.carbs.map { $0 * qty },
                protein: content?.protein.map { $0 * qty },
                fat: content?.fat.map { $0 * qty },
                status: .synced(logId: logId),
                mealType: mealType,
                servingId: food.servingId,
                serving: content.flatMap(Serving.init(loggedContent:)),
                source: GarminFoodSource(readBackSource: meta?.source),
                regionCode: meta?.regionCode,
                languageCode: meta?.languageCode
            ))
        }
        return entries
    }

    /// Queued entries for one meal. A `.sent` entry is already accepted by
    /// Garmin; it's shown only while it can't be matched to an entry in the
    /// loaded log, so a delivered entry never appears twice. The same goes
    /// for a replace whose corrected entry is already created
    /// (`.createdAwaitingDelete`, add-log-entry-editing) -- and a duplicate
    /// is never matched to the very entry it was copied from.
    ///
    /// `loggedById` (every read-back entry of the day) names and sizes an
    /// edit or duplicate from the entry it came from when the food isn't
    /// in the local cache.
    static func pendingEntries(
        _ queued: [OutboxEntry],
        logged: [LoggedFood],
        foods: [String: Food],
        mealType: MealType? = nil,
        loggedById: [String: LoggedFood] = [:]
    ) -> [MealEntry] {
        var unmatched = logged
        var entries: [MealEntry] = []
        for entry in queued.sorted(by: { $0.createdAt < $1.createdAt }) {
            if entry.state == .sent || entry.state == .createdAwaitingDelete {
                let index = unmatched.firstIndex { food in
                    matches(food, entry) && (entry.duplicateOf == nil || food.logId != entry.duplicateOf)
                }
                if let index {
                    unmatched.remove(at: index)
                    continue
                }
            }
            let origin = entry.replaces.flatMap { loggedById[$0.logId] }
                ?? entry.duplicateOf.flatMap { loggedById[$0] }
            entries.append(pendingEntry(entry, food: foods[entry.foodId], origin: origin, mealType: mealType))
        }
        return entries
    }

    static func matches(_ logged: LoggedFood, _ entry: OutboxEntry) -> Bool {
        logged.foodId == entry.foodId
            && logged.servingId == entry.servingId
            && logged.matchesQuantity(entry.numberOfUnits)
    }

    /// `origin`: the read-back entry an edit replaces or a duplicate copies
    /// -- same food and serving, so its per-serving nutrition is this
    /// entry's too when the food isn't cached.
    static func pendingEntry(_ entry: OutboxEntry, food: Food?, origin: LoggedFood? = nil, mealType: MealType? = nil) -> MealEntry {
        let cachedServing = food?.servings.first { $0.id == entry.servingId }
        let originContent = origin?.servingId == entry.servingId ? origin?.nutritionContent : nil
        let serving = cachedServing ?? originContent.flatMap(Serving.init(loggedContent:))
        let description = cachedServing?.displayLabel
            ?? servingDescription(unit: originContent?.servingUnit, numberOfUnits: originContent?.numberOfUnits)
        let qty = entry.numberOfUnits
        let status: MealEntry.Status
        if entry.state == .failed {
            status = .failed(outboxId: entry.id, reason: entry.lastError)
        } else {
            status = .syncing(outboxId: entry.id)
        }
        return MealEntry(
            id: entry.id.uuidString,
            foodId: entry.foodId,
            name: food?.name ?? origin?.foodMetaData?.foodName ?? "Syncing…",
            brandName: food?.brandName ?? origin?.foodMetaData?.brandName,
            servingQty: qty,
            servingDescription: description,
            calories: serving?.calories.map { $0 * qty },
            carbs: serving?.carbs.map { $0 * qty },
            protein: serving?.protein.map { $0 * qty },
            fat: serving?.fat.map { $0 * qty },
            status: status,
            mealType: mealType ?? entry.mealType,
            servingId: entry.servingId,
            serving: serving,
            source: entry.source ?? GarminFoodSource(readBackSource: origin?.foodMetaData?.source),
            regionCode: entry.regionCode ?? origin?.foodMetaData?.regionCode,
            languageCode: entry.languageCode ?? origin?.foodMetaData?.languageCode,
            replacesLogId: entry.replaces?.logId
        )
    }

    // MARK: Helpers

    /// The fixed, base goal (Garmin `calorieGoal` and its macro split), NOT
    /// the `adjusted*` value -- owner decision 2026-09-23 (fix-testing-
    /// feedback-quick-wins, today-dashboard spec "The home Target is the
    /// fixed calorie goal"): `adjusted*` is the goal PLUS burned calories,
    /// which silently moved the Target after every run. Burned calories are
    /// shown separately, for information only ("Active today"). Macros
    /// follow the same rule so their bars stay consistent with the calorie
    /// Target. The adjusted value is only a fallback for a payload that
    /// somehow carries no base value at all.
    static func target(_ adjusted: Double?, _ base: Double?) -> Double? {
        base ?? adjusted
    }

    static func sum(_ entries: [MealEntry], _ value: KeyPath<MealEntry, Double?>) -> Double {
        var total = 0.0
        for entry in entries {
            total += entry[keyPath: value] ?? 0
        }
        return total
    }

    static func servingDescription(unit: String?, numberOfUnits: Double?) -> String? {
        guard let unit = unit?.trimmingCharacters(in: .whitespaces), !unit.isEmpty else { return nil }
        guard let numberOfUnits, numberOfUnits != 1 else { return unit.lowercased() }
        let quantity = NumberDisplay.quantity(numberOfUnits, fractionDigits: 1)
        return "\(quantity) \(unit.lowercased())"
    }

    public static func secondsOfDay(_ time: String) -> Int? {
        let parts = time.split(separator: ":")
        guard parts.count >= 2,
              let hours = Int(parts[0]), let minutes = Int(parts[1])
        else { return nil }
        let seconds = parts.count > 2 ? (Int(parts[2]) ?? 0) : 0
        return hours * 3600 + minutes * 60 + seconds
    }
}

// MARK: - Default meal from Garmin's windows

public enum MealWindowDefaulting {
    /// The meal whose window contains `date`'s local time; SNACKS outside
    /// every window, which is how garmin_mcp maps a time to a meal. With no
    /// windows known, falls back to the fixed hour table.
    public static func mealType(at date: Date, windows: [MealWindow], calendar: Calendar = .current) -> MealType {
        guard !windows.isEmpty else {
            return MealTypeDefaulting.defaultMealType(for: date, calendar: calendar)
        }
        let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
        let seconds = (parts.hour ?? 0) * 3600 + (parts.minute ?? 0) * 60 + (parts.second ?? 0)
        return windows.first { $0.contains(secondsOfDay: seconds) }?.mealType ?? .snacks
    }
}
