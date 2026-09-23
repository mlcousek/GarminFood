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
        case .calories: return "Calories"
        case .carbs: return "Carbohydrates"
        case .fiber: return "Fiber"
        case .sugar: return "Sugar"
        case .protein: return "Protein"
        case .fat: return "Fat"
        case .saturatedFat: return "Saturated fat"
        case .monounsaturatedFat: return "Monounsaturated fat"
        case .polyunsaturatedFat: return "Polyunsaturated fat"
        case .cholesterol: return "Cholesterol"
        case .sodium: return "Sodium"
        case .potassium: return "Potassium"
        case .vitaminA: return "Vitamin A"
        case .vitaminC: return "Vitamin C"
        case .calcium: return "Calcium"
        case .iron: return "Iron"
        case .vitaminB1: return "Vitamin B1 (Thiamin)"
        case .vitaminB2: return "Vitamin B2 (Riboflavin)"
        case .vitaminB3: return "Vitamin B3 (Niacin)"
        case .vitaminB5: return "Vitamin B5 (Pantothenic acid)"
        case .vitaminB6: return "Vitamin B6"
        case .vitaminB9: return "Folate (B9)"
        case .vitaminB12: return "Vitamin B12"
        case .vitaminD: return "Vitamin D"
        case .vitaminE: return "Vitamin E"
        case .vitaminK: return "Vitamin K"
        case .magnesium: return "Magnesium"
        case .zinc: return "Zinc"
        case .phosphorus: return "Phosphorus"
        case .selenium: return "Selenium"
        case .copper: return "Copper"
        case .manganese: return "Manganese"
        case .iodine: return "Iodine"
        case .omega3: return "Omega-3"
        case .omega6: return "Omega-6"
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
        case .energy: return "Energy"
        case .macronutrient: return "Macronutrients"
        case .vitamin: return "Vitamins"
        case .mineral: return "Minerals"
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
        status: Status
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
    }

    public var isSynced: Bool {
        if case .synced = status { return true }
        return false
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

        var sections: [MealSection] = []
        for type in order {
            let detail = detailByType[type]
            let meal = detail?.meal ?? mealByType[type]
            let synced = syncedEntries(detail?.loggedFoods ?? [])
            let pending = pendingEntries(
                queued.filter { $0.mealType == type },
                logged: detail?.loggedFoods ?? [],
                foods: foods
            )
            sections.append(section(
                type: type,
                meal: meal,
                content: detail?.mealNutritionContent,
                goals: detail?.mealNutritionGoals,
                synced: synced,
                pending: pending
            ))
        }

        let dayContent = log?.dailyNutritionContent
        let dayGoals = log?.dailyNutritionGoals
        let pendingAll = sections.flatMap(\.entries).filter { !$0.isSynced }
        let totals = NutrientTotals(
            calories: MacroProgress(consumed: (dayContent?.calories ?? 0) + sum(pendingAll, \.calories), goal: target(dayGoals?.adjustedCalories, dayGoals?.calories)),
            carbs: MacroProgress(consumed: (dayContent?.carbs ?? 0) + sum(pendingAll, \.carbs), goal: target(dayGoals?.adjustedCarbs, dayGoals?.carbs)),
            protein: MacroProgress(consumed: (dayContent?.protein ?? 0) + sum(pendingAll, \.protein), goal: target(dayGoals?.adjustedProtein, dayGoals?.protein)),
            fat: MacroProgress(consumed: (dayContent?.fat ?? 0) + sum(pendingAll, \.fat), goal: target(dayGoals?.adjustedFat, dayGoals?.fat))
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
        pending: [MealEntry]
    ) -> MealSection {
        let pendingCalories = sum(pending, \.calories)
        let pendingCarbs = sum(pending, \.carbs)
        let pendingProtein = sum(pending, \.protein)
        let pendingFat = sum(pending, \.fat)

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

    static func syncedEntries(_ logged: [LoggedFood]) -> [MealEntry] {
        var entries: [MealEntry] = []
        for (index, food) in logged.enumerated() {
            let logId = food.logId ?? ""
            let qty = food.servingQty ?? 1
            let content = food.nutritionContent
            let serving = servingDescription(unit: content?.servingUnit, numberOfUnits: content?.numberOfUnits)
            entries.append(MealEntry(
                id: logId.isEmpty ? "synced-\(index)-\(food.foodId ?? "")" : logId,
                foodId: food.foodId ?? "",
                name: food.foodMetaData?.foodName ?? "Unnamed food",
                brandName: food.foodMetaData?.brandName,
                servingQty: qty,
                servingDescription: serving,
                calories: content?.calories.map { $0 * qty },
                carbs: content?.carbs.map { $0 * qty },
                protein: content?.protein.map { $0 * qty },
                fat: content?.fat.map { $0 * qty },
                status: .synced(logId: logId)
            ))
        }
        return entries
    }

    /// Queued entries for one meal. A `.sent` entry is already accepted by
    /// Garmin; it's shown only while it can't be matched to an entry in the
    /// loaded log, so a delivered entry never appears twice.
    static func pendingEntries(_ queued: [OutboxEntry], logged: [LoggedFood], foods: [String: Food]) -> [MealEntry] {
        var unmatched = logged
        var entries: [MealEntry] = []
        for entry in queued.sorted(by: { $0.createdAt < $1.createdAt }) {
            if entry.state == .sent {
                if let index = unmatched.firstIndex(where: { matches($0, entry) }) {
                    unmatched.remove(at: index)
                    continue
                }
            }
            entries.append(pendingEntry(entry, food: foods[entry.foodId]))
        }
        return entries
    }

    static func matches(_ logged: LoggedFood, _ entry: OutboxEntry) -> Bool {
        logged.foodId == entry.foodId
            && logged.servingId == entry.servingId
            && logged.matchesQuantity(entry.numberOfUnits)
    }

    static func pendingEntry(_ entry: OutboxEntry, food: Food?) -> MealEntry {
        let serving = food?.servings.first { $0.id == entry.servingId }
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
            name: food?.name ?? "Syncing…",
            brandName: food?.brandName,
            servingQty: qty,
            servingDescription: serving?.displayLabel,
            calories: serving?.calories.map { $0 * qty },
            carbs: serving?.carbs.map { $0 * qty },
            protein: serving?.protein.map { $0 * qty },
            fat: serving?.fat.map { $0 * qty },
            status: status
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
        let quantity = numberOfUnits.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(numberOfUnits))
            : String(format: "%.1f", numberOfUnits)
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
