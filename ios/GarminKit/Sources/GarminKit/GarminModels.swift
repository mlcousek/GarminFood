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
    /// Client-supplied on write (see `FoodLogWriteBody`). Observed "GCM" on
    /// entries the official mobile app created; this app sends "GCW".
    public let logSource: String?
    /// Client-supplied on write. Observed "REGULAR_LOG".
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

// MARK: - Meal definitions (GET /nutrition-service/meals/{date}) -- confirmed live 2026-09-16

/// The meal definitions for one date, returned whether or not anything is
/// logged on it. The write needs this: Garmin files an entry under a meal
/// INSTANCE (`mealId`, numeric, different for every date), not under a meal
/// name, and an entry queued offline cannot know that id until delivery.
public struct MealsForDate: Decodable, Sendable {
    public let meals: [Meal]?
    public let dailyTimelineStartTime: String?
    public let dailyTimelineEndTime: String?
}

// MARK: - Create / delete (PUT/DELETE /nutrition-service/food/logs) -- modelled on a live-tested client, not yet exercised by this project

/// Confirmed values: all four names below are returned by
/// `GET /nutrition-service/meals/{date}` on the owner's account (2026-09-16).
/// BREAKFAST, LUNCH and DINNER carry a startTime/endTime window; SNACKS
/// carries none.
public enum MealType: String, Codable, Sendable, CaseIterable {
    case breakfast = "BREAKFAST"
    case lunch = "LUNCH"
    case snacks = "SNACKS"
    case dinner = "DINNER"
}

/// Which of Garmin's two food namespaces a `foodId` belongs to. The write
/// body has to say, and naming the wrong one is a 400.
public enum GarminFoodSource: String, Codable, Sendable, Equatable {
    case garmin = "GARMIN"
    case fatSecret = "FATSECRET"

    /// For callers that don't know the namespace: a custom food's backing
    /// food, or an entry queued by a build that predates this field.
    /// FatSecret ids are purely numeric; Garmin's own ids -- including a
    /// user's custom foods -- are 32-character hex UUIDs. Checked against
    /// every entry logged on the owner's account on 2026-09-16: all numeric
    /// ids were FATSECRET and all hex ids were GARMIN.
    public static func inferred(fromFoodId foodId: String) -> GarminFoodSource {
        let isNumeric = !foodId.isEmpty && foodId.utf8.allSatisfy { $0 >= 48 && $0 <= 57 }
        return isNumeric ? .fatSecret : .garmin
    }
}

/// What the app wants logged -- deliberately NOT the wire body. Garmin files
/// an entry under a per-date meal instance id that an entry queued offline
/// can't know yet, so `GarminClient.createFoodLogEntry` resolves that at
/// delivery time and builds `FoodLogWriteBody` from this.
public struct CreateFoodLogEntryRequest: Sendable, Equatable {
    public let date: String // YYYY-MM-DD, local nutrition-day date
    public let mealType: MealType
    public let foodId: String
    public let servingId: String
    /// How many of `servingId` -- sent as Garmin's `servingQty`, which is
    /// also the field `LoggedFood.matchesQuantity` checks first on read-back.
    public let numberOfUnits: Double
    public let source: GarminFoodSource
    /// When the user logged it, not when it was delivered. Sent as
    /// `logTimestamp`, which is how the official app's own entries read
    /// back (the moment of logging), and what lets Reconciliation tell this
    /// app's deliveries apart from entries that already existed.
    public let loggedAt: Date

    public init(
        date: String,
        mealType: MealType,
        foodId: String,
        servingId: String,
        numberOfUnits: Double,
        source: GarminFoodSource? = nil,
        loggedAt: Date = Date()
    ) {
        self.date = date
        self.mealType = mealType
        self.foodId = foodId
        self.servingId = servingId
        self.numberOfUnits = numberOfUnits
        self.source = source ?? .inferred(fromFoodId: foodId)
        self.loggedAt = loggedAt
    }
}

public enum FoodLogWriteError: Error, Sendable, Equatable {
    /// The date's meal definitions have no meal by this name, or it has no
    /// id. Waiting won't fix it -- the meal set is account configuration --
    /// so the message has to say exactly which meal and date.
    case mealNotFound(mealName: String, date: String)
}

/// The wire body for `PUT /nutrition-service/food/logs`.
///
/// Source of truth: garmin_mcp (Taxuspt/garmin_mcp, `log_food_to_meal` in
/// src/garmin_mcp/nutrition.py), which writes to this route and ships live
/// end-to-end tests against a real account. The body this project inferred
/// earlier -- a flat POST of date/mealType/foodId/servingId/numberOfUnits,
/// reconstructed from alphabetically sorted dex strings -- matched it in
/// almost nothing: wrong method, no `foodLogItems` envelope, a meal NAME
/// where Garmin wants a per-date meal INSTANCE id, `numberOfUnits` for
/// `servingQty`, and no `source`. Every field here is what that client sends.
struct FoodLogWriteBody: Encodable, Equatable {
    let mealDate: String
    let foodLogItems: [Item]

    struct Item: Encodable, Equatable {
        let logTimestamp: String
        let logSource: String
        let logCategory: String
        let mealTime: String
        let action: String
        let mealId: Int
        let foodId: String
        let servingId: String
        let source: String
        let regionCode: String
        let languageCode: String
        let servingQty: Double
    }

    /// garmin_mcp's values. It sends `GCW` (Garmin Connect Web); the
    /// official mobile app's entries read back as `GCM` -- the proven value
    /// is used. `regionCode`/`languageCode` come from the client and are not
    /// checked against the food: on the owner's account the official app
    /// filed a food that search reports under region `US` as `CZ`.
    static let logSource = "GCW"
    static let logCategory = "REGULAR_LOG"
    static let action = "ADD"
    static let regionCode = "US"
    static let languageCode = "en"

    static func make(
        for request: CreateFoodLogEntryRequest,
        meals: [Meal],
        timeZone: TimeZone = .current
    ) throws -> FoodLogWriteBody {
        guard
            let meal = meals.first(where: { $0.mealName == request.mealType.rawValue }),
            let mealId = meal.mealId
        else {
            throw FoodLogWriteError.mealNotFound(mealName: request.mealType.rawValue, date: request.date)
        }
        let item = Item(
            logTimestamp: logTimestampString(request.loggedAt),
            logSource: logSource,
            logCategory: logCategory,
            mealTime: mealTime(for: meal, among: meals, loggedAt: request.loggedAt, timeZone: timeZone),
            action: action,
            mealId: mealId,
            foodId: request.foodId,
            servingId: request.servingId,
            source: request.source.rawValue,
            regionCode: regionCode,
            languageCode: languageCode,
            servingQty: request.numberOfUnits
        )
        return FoodLogWriteBody(mealDate: request.date, foodLogItems: [item])
    }

    /// `2026-09-16T13:35:49.324Z` -- the exact shape entries read back with.
    static func logTimestampString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    /// A meal with a window is logged at its start time, which is how the
    /// official app's own entries read back (every breakfast entry on the
    /// owner's account carries that meal's startTime as `mealTime`).
    ///
    /// A windowless meal (SNACKS) gets the local time of logging -- unless
    /// that lands inside another meal's window, in which case it moves just
    /// past that window. garmin_mcp derives `mealId` FROM `mealTime` (inside
    /// a window means that meal, otherwise SNACKS), so a snack stamped 11:00
    /// would read as a lunch. This keeps the two fields from contradicting
    /// each other, whichever one Garmin actually honours.
    static func mealTime(for meal: Meal, among meals: [Meal], loggedAt: Date, timeZone: TimeZone) -> String {
        if let start = meal.startTime, meal.endTime != nil {
            return start
        }

        var windows: [(start: Int, end: Int)] = []
        for other in meals {
            guard
                let startTime = other.startTime, let start = secondsOfDay(startTime),
                let endTime = other.endTime, let end = secondsOfDay(endTime)
            else { continue }
            windows.append((start: start, end: end))
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute, .second], from: loggedAt)
        let local = (parts.hour ?? 0) * 3600 + (parts.minute ?? 0) * 60 + (parts.second ?? 0)

        guard let containing = windows.first(where: { local >= $0.start && local <= $0.end }) else {
            return timeString(local)
        }

        var candidates: [Int] = [containing.end + 1, containing.start - 1]
        for window in windows {
            candidates.append(window.end + 1)
            candidates.append(window.start - 1)
        }
        for candidate in candidates {
            guard candidate >= 0, candidate < 86_400 else { continue }
            let insideAWindow = windows.contains(where: { candidate >= $0.start && candidate <= $0.end })
            if !insideAWindow {
                return timeString(candidate)
            }
        }
        return timeString(local)
    }

    static func secondsOfDay(_ time: String) -> Int? {
        let parts = time.split(separator: ":")
        guard parts.count == 3,
              let hours = Int(parts[0]), let minutes = Int(parts[1]), let seconds = Int(parts[2])
        else { return nil }
        return hours * 3600 + minutes * 60 + seconds
    }

    static func timeString(_ secondsOfDay: Int) -> String {
        let hours = secondsOfDay / 3600
        let minutes = (secondsOfDay % 3600) / 60
        let seconds = secondsOfDay % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
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
