// GarminModels.swift
//
// Codable models matching `docs/garmin-food-log-contract.md` and
// `docs/garmin-routes.json` field-for-field, for the routes GarminClient
// implements. Confidence varies by route -- see each type's doc comment --
// so nearly everything is Optional rather than assumed-present: a decode
// should not fail hard just because one cosmetic field Garmin didn't
// document precisely is missing or renamed on a given response. The few
// fields treated as required (e.g. `foodId`, `servingId` as identifiers)
// are the ones this project's own logic (search -> create -> reconcile)
// cannot function without.

import Foundation

// MARK: - Food search (GET /nutrition-service/food/search) -- confirmed live 2026-09-14

public struct FoodSearchResponse: Decodable, Sendable {
    public let results: [FoodSearchResult]
    public let moreDataAvailable: Bool?
}

public struct FoodSearchResult: Decodable, Sendable {
    public let type: String?
    public let foodMetaData: FoodMetaData
    public let nutritionContents: [NutritionContent]?
    public let isFavorite: Bool?
    public let isRecent: Bool?
    public let servingQty: Double?
    public let logTimestamp: String?
}

public struct FoodMetaData: Decodable, Sendable {
    public let foodId: String
    public let foodName: String?
    public let foodType: String?
    public let brandName: String?
    /// "GARMIN" | "FATSECRET" per the contract, kept as a plain String
    /// rather than an enum since the full value set isn't confirmed.
    public let source: String?
    public let regionCode: String?
    public let languageCode: String?
    public let customFoodType: String?
}

public struct NutritionContent: Decodable, Sendable {
    public let servingId: String?
    public let servingUnit: String?
    public let numberOfUnits: Double?
    public let calories: Double?
    public let carbs: Double?
    public let protein: Double?
    public let fat: Double?
    public let fiber: Double?
    public let sugar: Double?
    public let saturatedFat: Double?
    public let monounsaturatedFat: Double?
    public let polyunsaturatedFat: Double?
    public let cholesterol: Double?
    public let sodium: Double?
    public let potassium: Double?
    public let vitaminA: Double?
    public let vitaminC: Double?
    public let calcium: Double?
    public let iron: Double?
    public let unitHasServing: Bool?
}

// MARK: - Daily food log (GET /nutrition-service/food/logs/{date}) -- confirmed live 2026-09-14

public struct DailyFoodLog: Decodable, Sendable {
    public let mealDate: String?
    /// "04:00:00" observed -- the nutrition day is NOT calendar
    /// midnight-to-midnight. Any "today" logic MUST read this from the
    /// response rather than assuming 00:00, per the contract doc's
    /// explicit warning.
    public let dayStartTime: String?
    public let dayEndTime: String?
    public let dailyViewType: String?
    public let dailyNutritionGoals: NutritionGoals?
    public let dailyNutritionContent: DailyNutritionContent?
    public let mealDetails: [MealDetail]?
    public let loggedFoodsWithServingSizes: [LoggedFood]?
}

public struct NutritionGoals: Decodable, Sendable {
    public let calories: Double?
    public let adjustedCalories: Double?
    public let carbs: Double?
    public let adjustedCarbs: Double?
    public let fat: Double?
    public let adjustedFat: Double?
    public let protein: Double?
    public let adjustedProtein: Double?
}

public struct DailyNutritionContent: Decodable, Sendable {
    public let calories: Double?
    public let carbs: Double?
    public let fat: Double?
    public let protein: Double?
    public let otherCalories: Double?
    public let caloriesPercentage: Double?
}

public struct MealDetail: Decodable, Sendable {
    public let meal: Meal?
    public let mealNutritionContent: DailyNutritionContent?
    public let mealNutritionGoals: NutritionGoals?
    public let loggedFoods: [LoggedFood]?
}

public struct Meal: Decodable, Sendable {
    public let mealId: Int?
    public let mealIndex: Int?
    /// Confirmed values via real reads: BREAKFAST, LUNCH, SNACKS. DINNER is
    /// presumed to exist but not yet observed on this account.
    public let mealName: String?
    public let displayOrder: Int?
    public let startTime: String?
    public let endTime: String?
    public let goals: NutritionGoals?
    public let editable: Bool?
    public let translated: Bool?
}

/// A single logged food entry, as it comes back from `dailyFoodLog` or
/// `loggedFoodsWithServingSizes`.
public struct LoggedFood: Decodable, Sendable {
    /// "appears to equal foodId" per the contract -- not relied on as a
    /// distinct identifier anywhere in this package.
    public let id: String?
    /// Hex string, unique per log entry -- the identifier `deleteFoodLogEntries`
    /// actually takes (NOT the same as `foodId`).
    public let logId: String?
    public let logTimestamp: String?
    /// Observed value: "GCM". Presumed server-assigned, not client-supplied.
    public let logSource: String?
    /// Observed value: "REGULAR_LOG". Presumed server-assigned.
    public let logCategory: String?
    /// Top-level fractional quantity (e.g. 0.7). See `matchesQuantity`'s
    /// doc comment: which of this or `nutritionContent.numberOfUnits` is
    /// "the" quantity a write controls is UNCONFIRMED.
    public let servingQty: Double?
    public let foodMetaData: FoodMetaData?
    public let nutritionContent: LoggedNutritionContent?
    public let isFavorite: Bool?
    /// Numeric, per-day-instance identifier -- NOT a stable enum. `customMealId`
    /// may be the more useful client-facing handle per the contract doc.
    public let mealId: Int?
    public let customMealId: Int?
    public let mealTime: String?
    public let foodInactive: Bool?
    public let type: String?

    /// Reconciliation match key components (design.md D5 / garmin-sync spec:
    /// match on "(date, mealType, foodId, servingId, numberOfUnits)"). `date`
    /// and `mealType` come from the enclosing `DailyFoodLog`/`Meal`, not
    /// from this struct, so callers combine those separately.
    public var foodId: String? { foodMetaData?.foodId }
    public var servingId: String? { nutritionContent?.servingId }

    /// Whether this entry's quantity matches `numberOfUnits` as understood
    /// by whichever process sent the original create request.
    ///
    /// Deliberately tolerant, per this phase's explicit instruction to code
    /// defensively around the unconfirmed quantity field: a read entry
    /// carries BOTH a top-level `servingQty` (e.g. 0.7) and a nested
    /// `nutritionContent.numberOfUnits` (e.g. 100 -- looks more like "grams
    /// per serving" than "how many servings were logged"). Rather than
    /// guess which one a write actually controls, this matches against
    /// EITHER, within a small floating-point tolerance. Only a real write
    /// (task 11.4, deliberately not automated by this package) will settle
    /// which one is authoritative -- see docs/garmin-food-log-contract.md's
    /// "what remains genuinely unconfirmed" list, item 2.
    public func matchesQuantity(_ numberOfUnits: Double, tolerance: Double = 0.001) -> Bool {
        if let servingQty, abs(servingQty - numberOfUnits) < tolerance { return true }
        if let contentUnits = nutritionContent?.numberOfUnits, abs(contentUnits - numberOfUnits) < tolerance { return true }
        return false
    }
}

public struct LoggedNutritionContent: Decodable, Sendable {
    public let servingId: String?
    public let servingUnit: String?
    public let numberOfUnits: Double?
    public let calories: Double?
    public let carbs: Double?
    public let protein: Double?
    public let fat: Double?
    public let fiber: Double?
    public let sugar: Double?
    public let saturatedFat: Double?
    public let sodium: Double?
    public let unitHasServing: Bool?
}

// MARK: - Create / delete (POST/DELETE /nutrition-service/food/logs) -- DOCUMENTED, NOT CONFIRMED BY A REAL WRITE

/// Confirmed values (via real reads' `meal.mealName`): `.breakfast`,
/// `.lunch`, `.snacks`. `.dinner` is presumed to exist but UNCONFIRMED on
/// this account -- see docs/garmin-food-log-contract.md.
public enum MealType: String, Codable, Sendable, CaseIterable {
    case breakfast = "BREAKFAST"
    case lunch = "LUNCH"
    case snacks = "SNACKS"
    case dinner = "DINNER"
}

/// The inferred request body for `createFoodLogEntry`, per
/// docs/garmin-food-log-contract.md's "Inferred request body (unconfirmed)"
/// section. Field names come from decompiled `FoodLogRequestDTO` Kotlin
/// `toString()` fragments cross-referenced against the read shape --
/// high confidence in which fields exist, only moderate confidence in exact
/// spelling/nesting, since the dex string pool that produced them is
/// alphabetically sorted and destroys original source/field order.
///
/// `numberOfUnits` here is sent as a plain top-level field, per the
/// documented shape -- this is DISTINCT from the ambiguity discussed on
/// `LoggedFood.matchesQuantity`, which concerns how to interpret quantity
/// fields when reading a response back, not what to send on write.
public struct CreateFoodLogEntryRequest: Encodable, Sendable, Equatable {
    public let date: String // YYYY-MM-DD, local nutrition-day date
    public let mealType: MealType
    public let foodId: String
    public let servingId: String
    public let numberOfUnits: Double

    public init(date: String, mealType: MealType, foodId: String, servingId: String, numberOfUnits: Double) {
        self.date = date
        self.mealType = mealType
        self.foodId = foodId
        self.servingId = servingId
        self.numberOfUnits = numberOfUnits
    }
}

/// Per the contract: `DeleteFoodRequestDTO(logIds=...)` -- takes `logId`
/// values (the hex string from a read entry), not `foodId`s.
struct DeleteFoodLogEntriesRequest: Encodable, Sendable {
    let logIds: [String]
}

// MARK: - Create custom food (POST /nutrition-service/customFood) -- ROUTE CONFIRMED TO EXIST, BODY GENUINELY UNCONFIRMED

/// The inferred request body for `GarminClient.createCustomFood`
/// (add-czech-food-catalog design.md's Context section, task 30.1).
///
/// UNLIKE `CreateFoodLogEntryRequest` above, this shape has NO decompiled
/// Kotlin `toString()` fragments behind it at all -- design.md is explicit:
/// "unlike `createFoodLogEntry`, which had Kotlin `toString()` fragments
/// hinting at field names, no field-level information was ever extracted
/// for this route." What follows is a genuine guess: field names a "food"
/// conceptually needs (a name, a serving unit/size, and macros), informed
/// only by the shape Garmin's OWN search results already use for a food's
/// nutrition content (see `NutritionContent` above) -- NOT by any
/// decompiled evidence for this specific route. Both the field names AND
/// the nesting could be wrong.
///
/// If this guess is wrong, `createCustomFood` fails with a
/// `GarminClientError` the caller/user sees (per this project's existing
/// loud-failure convention) -- a failed POST creates nothing, so a wrong
/// guess here cannot silently corrupt data.
public struct CreateCustomFoodRequest: Encodable, Sendable, Equatable {
    public let foodName: String
    public let servingUnit: String
    public let numberOfUnits: Double
    public let nutritionContent: CreateCustomFoodNutritionContent

    public init(foodName: String, servingUnit: String, numberOfUnits: Double, nutritionContent: CreateCustomFoodNutritionContent) {
        self.foodName = foodName
        self.servingUnit = servingUnit
        self.numberOfUnits = numberOfUnits
        self.nutritionContent = nutritionContent
    }
}

/// Same guess-quality caveat as `CreateCustomFoodRequest` above -- field
/// names mirror `NutritionContent`'s existing confirmed-live-for-READS
/// names, on the theory that a write is more likely to accept the same
/// vocabulary the read side already uses than to invent a new one, but
/// this is inference, not confirmation.
public struct CreateCustomFoodNutritionContent: Encodable, Sendable, Equatable {
    public let calories: Double
    public let protein: Double?
    public let carbs: Double?
    public let fat: Double?

    public init(calories: Double, protein: Double? = nil, carbs: Double? = nil, fat: Double? = nil) {
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
    }
}
