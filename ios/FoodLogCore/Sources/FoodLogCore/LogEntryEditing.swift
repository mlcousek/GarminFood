// LogEntryEditing.swift
//
// Pure pieces of add-log-entry-editing that aren't the commit itself (that
// is `LogEntryCoordinator.edit`/`duplicate`/`copyMeal`):
//   - `CopyMealPlanner` (design.md D4): turns a past day's read-back
//     (`GET /nutrition-service/food/logs/{date}`, confirmed 2026-09-14 -- the
//     same read the Today tab already uses) into the items "Copy from…" can
//     re-log, and the ones it can't (calories-only quick adds, which have no
//     food or serving id to log again).
//   - `LogEntryEditError`, the reasons an edit/duplicate is refused before
//     anything is written.
//   - Two small adapters from GarminKit's read-back shapes, shared by
//     `MealDashboard` (MealEntry's re-log identity) and the planner.
//
// Why re-logging from the read-back is enough: a read entry carries
// `foodMetaData` (foodId, source, regionCode, languageCode) and
// `nutritionContent.servingId`/`servingQty` -- exactly what the confirmed
// create body needs (docs/garmin-food-log-contract.md), including the
// region/language a custom food's nutrition is stored under
// (fix-custom-food-log-region). No new Garmin route is involved anywhere.
//
// Depended on by: LogEntryCoordinator.swift, MealDashboard.swift, and the
// app's CopyMealSheet/EditEntrySheet. Depends on GarminKit's models only.

import Foundation
import GarminKit

// MARK: - Errors

/// Why an edit, move or duplicate was refused. Nothing was written.
public enum LogEntryEditError: Error, Sendable, Equatable, LocalizedError {
    /// No food/serving id to log again (a calories-only quick add), or no
    /// Garmin id for a synced entry.
    case notEditable
    /// Zero, negative or not a number.
    case invalidQuantity
    /// Same amount and same meal as already logged.
    case noChange
    /// Garmin has accepted this entry, but the day hasn't been read back
    /// yet, so its Garmin id -- which the replace needs -- isn't known.
    case stillSyncing
    /// The queued entry is gone (delivered and confirmed, or deleted).
    case entryGone

    public var errorDescription: String? {
        switch self {
        case .notEditable:
            return "This entry can't be edited here -- it has no food to log again. You can delete it instead."
        case .invalidQuantity:
            return "Enter an amount greater than zero."
        case .noChange:
            return "Nothing changed."
        case .stillSyncing:
            return "This entry is just reaching Garmin. Try again in a moment."
        case .entryGone:
            return "This entry changed in the meantime. Pull to refresh and try again."
        }
    }
}

// MARK: - Copy a past meal (design.md D4)

/// One read-back item "Copy from…" can log again, as it was logged.
public struct CopyableMealItem: Sendable, Equatable, Identifiable {
    /// The source entry's `logId` (or a positional stand-in when Garmin
    /// sent none) -- identity for the preview's checkboxes only.
    public let id: String
    public let foodId: String
    public let servingId: String
    public let servingQty: Double
    public let name: String
    public let brandName: String?
    public let servingDescription: String?
    /// One serving's nutrition as read back.
    public let serving: Serving?
    /// Total for `servingQty`.
    public let calories: Double?
    public let source: GarminFoodSource?
    public let regionCode: String?
    public let languageCode: String?

    public init(
        id: String,
        foodId: String,
        servingId: String,
        servingQty: Double,
        name: String,
        brandName: String? = nil,
        servingDescription: String? = nil,
        serving: Serving? = nil,
        calories: Double? = nil,
        source: GarminFoodSource? = nil,
        regionCode: String? = nil,
        languageCode: String? = nil
    ) {
        self.id = id
        self.foodId = foodId
        self.servingId = servingId
        self.servingQty = servingQty
        self.name = name
        self.brandName = brandName
        self.servingDescription = servingDescription
        self.serving = serving
        self.calories = calories
        self.source = source
        self.regionCode = regionCode
        self.languageCode = languageCode
    }
}

/// A read-back item the preview lists but can't copy, and why.
public struct NonCopyableMealItem: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let calories: Double?
    public let reason: String

    public init(id: String, name: String, calories: Double?, reason: String) {
        self.id = id
        self.name = name
        self.calories = calories
        self.reason = reason
    }
}

public struct CopyMealPlan: Sendable, Equatable {
    public let copyable: [CopyableMealItem]
    public let notCopyable: [NonCopyableMealItem]

    public init(copyable: [CopyableMealItem], notCopyable: [NonCopyableMealItem]) {
        self.copyable = copyable
        self.notCopyable = notCopyable
    }

    public var isEmpty: Bool { copyable.isEmpty && notCopyable.isEmpty }
}

public enum CopyMealPlanner {
    public static let quickAddReason = "Calories only (quick add) -- no food to log again"

    /// The items of `mealType` in `log`, split into what can be logged
    /// again and what can't, in the order Garmin listed them. `nil` log
    /// (nothing logged that day, or it couldn't be read) is an empty plan.
    public static func plan(log: DailyFoodLog?, mealType: MealType) -> CopyMealPlan {
        let foods = (log?.mealDetails ?? [])
            .filter { $0.meal?.mealName == mealType.rawValue }
            .flatMap { $0.loggedFoods ?? [] }

        var copyable: [CopyableMealItem] = []
        var notCopyable: [NonCopyableMealItem] = []
        for (index, food) in foods.enumerated() {
            let meta = food.foodMetaData
            let content = food.nutritionContent
            let qty = food.servingQty ?? 1
            let id = food.logId.flatMap { $0.isEmpty ? nil : $0 } ?? "item-\(index)"
            let name = meta?.foodName ?? "Unnamed food"
            let calories = content?.calories.map { $0 * qty }

            guard let foodId = food.foodId, !foodId.isEmpty,
                  let servingId = food.servingId, !servingId.isEmpty,
                  qty > 0
            else {
                notCopyable.append(NonCopyableMealItem(id: id, name: name, calories: calories, reason: quickAddReason))
                continue
            }
            copyable.append(CopyableMealItem(
                id: id,
                foodId: foodId,
                servingId: servingId,
                servingQty: qty,
                name: name,
                brandName: meta?.brandName,
                servingDescription: MealDashboard.servingDescription(unit: content?.servingUnit, numberOfUnits: content?.numberOfUnits),
                serving: content.flatMap(Serving.init(loggedContent:)),
                calories: calories,
                source: GarminFoodSource(readBackSource: meta?.source),
                regionCode: meta?.regionCode,
                languageCode: meta?.languageCode
            ))
        }
        return CopyMealPlan(copyable: copyable, notCopyable: notCopyable)
    }
}

// MARK: - Read-back adapters

extension Serving {
    /// One serving as a logged entry reads back (`nutritionContent`), whose
    /// nutrient values are per serving -- `MealDashboard.syncedEntries`
    /// multiplies them by `servingQty` for the row's total.
    init?(loggedContent content: LoggedNutritionContent) {
        guard let id = content.servingId, !id.isEmpty else { return nil }
        self.init(
            id: id,
            unit: content.servingUnit ?? "serving",
            numberOfUnits: content.numberOfUnits ?? 1,
            calories: content.calories,
            carbs: content.carbs,
            protein: content.protein,
            fat: content.fat,
            fiber: content.fiber,
            sugar: content.sugar,
            saturatedFat: content.saturatedFat,
            sodium: content.sodium
        )
    }
}

extension GarminFoodSource {
    /// `foodMetaData.source` from a read-back ("GARMIN" | "FATSECRET",
    /// confirmed). Anything else is `nil`, so the write infers the
    /// namespace from the id's shape rather than naming a wrong one.
    init?(readBackSource: String?) {
        guard let raw = readBackSource?.uppercased(), let value = GarminFoodSource(rawValue: raw) else { return nil }
        self = value
    }
}
