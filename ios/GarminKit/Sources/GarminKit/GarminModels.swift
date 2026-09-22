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

/// Used for the day total and for each meal's `mealNutritionContent`. The
/// fields after `caloriesPercentage` were observed (2026-09-16) on meals
/// with food logged; the daily total carries only the first few. A meal
/// with nothing logged comes back as an EMPTY object, so every field is
/// optional and an absent value means "nothing", not "unknown".
public struct DailyNutritionContent: Decodable, Sendable {
    public let calories: Double?
    public let carbs: Double?
    public let fat: Double?
    public let protein: Double?
    public let otherCalories: Double?
    public let caloriesPercentage: Double?
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

// MARK: - Nutrition settings (GET /nutrition-service/settings/{date}) -- confirmed live 2026-09-16

/// The account's nutrition plan as Garmin Connect shows it. `macroGoals` are
/// grams: on 2026-09-16 they matched the daily log's base (non-adjusted)
/// goals exactly (316 g carbs / 64 g fat / 115 g protein against 2300 kcal),
/// while the log's `adjusted*` values add burned calories on top.
public struct NutritionSettings: Decodable, Sendable {
    public let calorieGoal: Double?
    public let macroGoals: MacroGoals?
    /// e.g. "LOSS" (observed), presumably also "GAIN" / "MAINTAIN".
    public let weightChangeType: String?
    public let weightChangeRate: Double?
    public let targetWeightGoal: Double?
    public let startingWeight: Double?
    public let targetDate: String?
    public let activeDailyCalories: Double?
    public let userDefinedActiveCalories: Bool?
    public let autoCalorieAdjustment: Bool?
    public let dailyTimelineStartTime: String?
    public let dailyTimelineEndTime: String?
    public let effectiveDate: String?
    /// "ACTIVE" observed.
    public let nutritionStatus: String?
    /// The account's real region/language -- part of this route's own
    /// confirmed-live shape (docs/garmin-routes.json) but never decoded
    /// until now (fix-custom-food-log-region, 2026-09-22). A real device
    /// error logging a just-created custom food ("Custom food nutrition
    /// information is missing for the provided food id with region code
    /// and language code") traced back to `FoodLogWriteBody`/
    /// `CustomFoodWriteBody` always hardcoding `"US"`/`"en"` regardless of
    /// the account's actual locale -- for a REGULAR Garmin/FatSecret food
    /// that's apparently tolerated (this file's own `FoodLogWriteBody`
    /// comment: "not checked against the food"), but a custom food's
    /// nutrition record is looked up by the exact `(foodId, regionCode,
    /// languageCode)` tuple it was created under, so a mismatch between
    /// the region/language used at CREATE time and the one used at LOG
    /// time throws exactly this error. These two fields let the app pass
    /// the account's real values through instead, falling back to the
    /// same `"US"`/`"en"` constants when unavailable (e.g. settings
    /// haven't loaded yet) -- unconfirmed which exact value this account
    /// carries until a real device reports it back.
    public let regionCode: String?
    public let languageCode: String?

    public struct MacroGoals: Decodable, Sendable {
        public let carbs: Double?
        public let fat: Double?
        public let protein: Double?
    }
}

// MARK: - Calorie summary daily (GET /nutrition-service/calorie/summary/daily) -- route confirmed live 2026-09-14 as a probe; first called by GarminClient itself as of add-trends-and-insights (2026-09-22)

/// A multi-day macro trend in ONE call -- `startDate`/`endDate` bound the
/// range, `dailyNutritionContents` carries one entry per day in it. Used by
/// the Trends screen instead of one `dailyFoodLog` call per day.
///
/// `mealNutritionContents`/`averageNutritionContents` (observed as `[]`/`{}`
/// on the probed range, docs/garmin-routes.json) are deliberately NOT
/// modeled here -- their element/field shape was never inspected, and
/// nothing in this app needs them; `JSONDecoder` ignores JSON keys a
/// `Decodable` type doesn't declare, so omitting them does not affect
/// decoding the fields that ARE modeled.
public struct CalorieSummaryDailyResponse: Decodable, Sendable {
    public let startDate: String?
    public let endDate: String?
    public let caloriesBurned: Double?
    public let dailyNutritionContents: [CalorieSummaryDay]?
}

/// One day within a `CalorieSummaryDailyResponse`.
///
/// `nutritionContent`/`nutritionGoals` are BOTH optional, and the route's
/// own confirmed gotcha is that a day nothing was logged on omits them
/// ENTIRELY (a bare `{ mealDate }`) rather than sending zeros -- callers
/// must treat a missing key as "nothing logged that day", never as an
/// error or a fabricated zero.
///
/// Reuses `DailyNutritionContent`/`NutritionGoals` -- the exact same types
/// `dailyFoodLog` decodes -- rather than declaring parallel types: the route
/// doc's field-by-field cross-check against a known day's `dailyFoodLog`
/// goal values (2300/3128/316/430/64/87/115/156 kcal/g) matched exactly, so
/// the two routes' per-day shapes are confirmed identical, not just
/// similar.
public struct CalorieSummaryDay: Decodable, Sendable {
    public let mealDate: String?
    public let nutritionContent: DailyNutritionContent?
    public let nutritionGoals: NutritionGoals?
}

// MARK: - Social profile (GET /userprofile-service/socialProfile) -- confirmed live 2026-09-16

/// Only the fields the profile screen shows. The real response has many
/// more (visibility flags, training speeds, roles) that this app has no use
/// for, and decoding them would only add ways for a decode to break.
public struct SocialProfile: Decodable, Sendable {
    public let displayName: String?
    public let fullName: String?
    public let userName: String?
    public let location: String?
    public let profileImageUrlSmall: String?
    public let profileImageUrlMedium: String?
    public let profileImageUrlLarge: String?
}

// MARK: - Create / delete (PUT/DELETE /nutrition-service/food/logs) -- create confirmed by a real write 2026-09-16; delete not yet exercised

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
    /// `nil` falls back to `FoodLogWriteBody`'s hardcoded `"US"`/`"en"`
    /// constants -- see `NutritionSettings.regionCode`'s doc comment for
    /// why a caller should pass the account's real values here instead
    /// whenever they're available (fix-custom-food-log-region, 2026-09-22).
    public let regionCode: String?
    public let languageCode: String?

    public init(
        date: String,
        mealType: MealType,
        foodId: String,
        servingId: String,
        numberOfUnits: Double,
        source: GarminFoodSource? = nil,
        loggedAt: Date = Date(),
        regionCode: String? = nil,
        languageCode: String? = nil
    ) {
        self.date = date
        self.mealType = mealType
        self.foodId = foodId
        self.servingId = servingId
        self.numberOfUnits = numberOfUnits
        self.source = source ?? .inferred(fromFoodId: foodId)
        self.loggedAt = loggedAt
        self.regionCode = regionCode
        self.languageCode = languageCode
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
    /// is used. `regionCode`/`languageCode` are the FALLBACK when a caller's
    /// `CreateFoodLogEntryRequest` doesn't supply its own (see `make`
    /// below): for a REGULAR Garmin/FatSecret food, region/language aren't
    /// checked against the food itself (on the owner's account the official
    /// app filed a food that search reports under region `US` as `CZ`), but
    /// fix-custom-food-log-region (2026-09-22) found that's NOT true for a
    /// custom food -- its nutrition record is looked up by the exact
    /// `(foodId, regionCode, languageCode)` tuple it was created under, so
    /// logging one with the wrong region/language 400s even though the food
    /// genuinely exists. Prefer the account's real values
    /// (`NutritionSettings.regionCode`/`.languageCode`) when available.
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
            regionCode: request.regionCode ?? regionCode,
            languageCode: request.languageCode ?? languageCode,
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

// MARK: - Create custom food (PUT /nutrition-service/customFood) -- CORRECTED 2026-09-22, evidence tier upgraded

/// The request body for `GarminClient.createCustomFood`, REPLACING the
/// original flat `CreateCustomFoodRequest` guess (add-czech-food-catalog
/// design.md's Context section, task 30.1) after that guess produced a real
/// device 400: `"custom food nutrition information is missing for the
/// provided food id with region code and language code"` (`BadRequestException`,
/// 2026-09-21) even after a first attempted fix (adding top-level
/// `regionCode`/`languageCode`) did not resolve it.
///
/// Source of the shape: `tamcore/garmin-mcp` (github.com/tamcore/garmin-mcp),
/// `internal/garmin/api/nutritionwritefood.go` (fetched 2026-09-22 in full).
///
/// EVIDENCE TIER, corrected 2026-09-22 after a second verification pass:
/// this is NOT the same tier as `WeighInWriteBody`/`HydrationWriteBody`
/// above. Those cite `cyberjunky/python-garminconnect`, and that citation
/// was checked and holds up -- the real file, the real function, the real
/// line range. `nutritionwritefood.go`'s OWN doc comments claim the same
/// thing ("Source: create_custom_food, PUT
/// \"/nutrition-service/customFood\" (nutrition.py:360-363)"), but that
/// citation does NOT hold up: `cyberjunky/python-garminconnect` has no
/// `nutrition.py` file and no custom-food code whatsoever, at either the
/// pinned commit `tamcore/garmin-mcp`'s own THIRD_PARTY_NOTICES.md cites
/// (`414b540`, release 0.3.10) or the current `main` branch -- both cloned
/// and grepped directly, not assumed. The citation appears to be
/// fabricated, not a real reference.
///
/// What DOES hold up, checked directly: `tamcore/garmin-mcp` has a real,
/// build-tag-gated live-account integration test
/// (`live/nutritionwrite_test.go`, `//go:build garminlive`) that creates,
/// updates, logs and deletes a custom food against an actual Garmin
/// account, asserting on the real response (`food_id`/`serving_id` read
/// back, calorie figure persisted, an omitted-on-update field actually
/// cleared). Traced the call chain: that test's tool handler
/// (`internal/tools/customfoodwrites.go`'s `createCustomFood`) calls
/// `Nutrition.CreateCustomFood`, which calls `saveCustomFood`, which calls
/// `buildCustomFoodBody` -- the EXACT function whose `customFoodDTO`/
/// `foodMetaDataDTO`/`nutritionContentDTO` structs this Swift type ports.
/// So: real, structured, actively-maintained code with an apparent
/// real-account test exercising this exact path -- meaningfully better
/// than a blind guess or a decompiled string literal, but NOT
/// independently verified the way the weight/hydration routes are (no way
/// from here to confirm that live test has actually been run and passed
/// recently), and its own internal citation cannot be trusted at face
/// value. Treat this the way the rest of this comment already does: still
/// unconfirmed until exercised by THIS app on the real device. The flat
/// 2026-09-21 guess was wrong in three ways at once, all fixed here:
///   1. The method is **PUT**, not POST.
///   2. The body is NOT flat -- a food's identity (name/type/source/
///      region/language/brand) nests under a `foodMetaData` object, and its
///      nutrition facts are a ONE-ELEMENT `nutritionContents` ARRAY, both
///      siblings at the top level.
///   3. Every numeric field inside `nutritionContents` is sent as a
///      **string** (`"160"`, never `160`), dropping a trailing `.0` for a
///      whole number -- Garmin's own `_num_to_str` wire convention.
/// `foodId`/`servingId` are `nil` (omitted) for a create: Garmin assigns
/// the real ids and returns them in the response (decoded as
/// `FoodSearchResult`, which already shares this exact `foodMetaData`/
/// `nutritionContents` envelope for reads). `foodType`/`source` are fixed
/// constants (`"GENERIC"`/`"GARMIN"`), matching `tamcore/garmin-mcp`'s own
/// `FoodTypeGeneric`/`FoodSourceGarmin` -- every custom food this app
/// creates is a plain, Garmin-sourced generic food.
///
/// Never yet exercised against the real account since this correction --
/// still gated the same way (`GarminClient.createCustomFood`'s own header):
/// the only call site is an explicit, user-triggered "Create in Garmin"
/// action, never automatic.
struct CustomFoodWriteBody: Encodable, Equatable {
    struct FoodMetaData: Encodable, Equatable {
        let foodId: String?
        let foodName: String
        let foodType: String
        let source: String
        let regionCode: String
        let languageCode: String
        let brandName: String?
    }

    struct NutritionContent: Encodable, Equatable {
        let servingId: String?
        let servingUnit: String
        let numberOfUnits: String
        let calories: String
        let carbs: String?
        let protein: String?
        let fat: String?
    }

    let foodMetaData: FoodMetaData
    let nutritionContents: [NutritionContent]

    static func make(
        foodName: String,
        servingUnit: String,
        numberOfUnits: Double,
        calories: Double,
        protein: Double?,
        carbs: Double?,
        fat: Double?,
        regionCode: String? = nil,
        languageCode: String? = nil
    ) -> CustomFoodWriteBody {
        CustomFoodWriteBody(
            foodMetaData: FoodMetaData(
                foodId: nil,
                foodName: foodName,
                foodType: "GENERIC",
                source: "GARMIN",
                // fix-custom-food-log-region (2026-09-22): a caller should
                // pass the account's real region/language
                // (NutritionSettings.regionCode/.languageCode) whenever
                // available -- the food-log write for THIS food later must
                // match whatever gets stored here exactly, or Garmin can't
                // find the nutrition record (see FoodLogWriteBody's own
                // comment on this same fallback pair for the full story).
                regionCode: regionCode ?? FoodLogWriteBody.regionCode,
                languageCode: languageCode ?? FoodLogWriteBody.languageCode,
                brandName: nil
            ),
            nutritionContents: [
                NutritionContent(
                    servingId: nil,
                    servingUnit: servingUnit,
                    numberOfUnits: numberString(numberOfUnits),
                    calories: numberString(calories),
                    carbs: carbs.map(numberString),
                    protein: protein.map(numberString),
                    fat: fat.map(numberString)
                )
            ]
        )
    }

    /// `"160"`, not `"160.0"` -- matches `tamcore/garmin-mcp`'s `numString`
    /// (its own doc comment: "the same wire form `_num_to_str` builds:
    /// Garmin's nutrition write fields expect integer strings like `160`,
    /// never `160.0`"). A whole number drops its fractional part entirely;
    /// anything else keeps its shortest round-tripping decimal form (Swift's
    /// default `Double` `String` conversion already produces this, the same
    /// property Go's `strconv.FormatFloat(_, 'f', -1, 64)` is chosen for).
    static func numberString(_ value: Double) -> String {
        if value.isFinite, value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int64(value))
        }
        return String(value)
    }
}

/// `POST /nutrition-service/customMeal`'s request body (add-meal-presets,
/// 2026-09-22 research) -- a genuine guess, same risk category as
/// `CreateCustomFoodRequest` above and for the same reason: this route was
/// found only as a string literal in the decompiled Android client
/// (docs/garmin-routes.json, "documented, not exercised"), never called
/// even once. No Kotlin `toString()` fragments or other field-level
/// evidence exist for it, unlike `createFoodLogEntry`'s confirmed
/// `FoodLogWriteBody`.
///
/// The shape here is not a blind guess, though: `GET /nutrition-service/
/// food/logs/{date}` already proves a REAL `customMealId` (a plain `Int`,
/// per `LoggedFood.customMealId` above) exists on THIS account today,
/// created by the official Garmin Connect Mobile app -- so the concept is
/// real and in active use, just not yet reverse-engineered on the write
/// side. `foodItems`' per-item fields mirror `FoodLogWriteBody.Item`'s
/// confirmed vocabulary (`foodId`/`servingId`/`source`/`regionCode`/
/// `languageCode`/quantity) on the theory that a sibling nutrition-service
/// write is more likely to reuse that vocabulary than invent a new one --
/// inference, not confirmation.
///
/// If this guess is wrong, `createCustomMeal` fails with a
/// `GarminClientError` the caller/user sees -- a failed POST creates
/// nothing, so a wrong guess here cannot silently corrupt data. Per this
/// project's task rule ("never write to the Garmin account before the
/// write contract is documented"), nothing calls `GarminClient.
/// createCustomMeal` automatically; the only call site is an explicit,
/// clearly-labeled "Sync to Garmin (experimental)" action the user takes
/// deliberately (`MealPresetEditorView`), same gating `createCustomFood`
/// already uses.
/// What a caller of `GarminClient.createCustomMeal` actually supplies --
/// deliberately without `regionCode`/`languageCode`, which `GarminClient`
/// fills in itself from its own internal `FoodLogWriteBody` constants, the
/// same way `createCustomFood`'s public parameter list has no region/
/// language fields either. Keeps the app layer from needing to know that
/// internal type exists at all.
public struct CustomMealItemInput: Sendable, Equatable {
    public let foodId: String
    public let servingId: String
    public let source: String
    public let numberOfUnits: Double

    public init(foodId: String, servingId: String, source: String, numberOfUnits: Double) {
        self.foodId = foodId
        self.servingId = servingId
        self.source = source
        self.numberOfUnits = numberOfUnits
    }
}

public struct CreateCustomMealRequest: Encodable, Sendable, Equatable {
    public struct Item: Encodable, Sendable, Equatable {
        public let foodId: String
        public let servingId: String
        public let source: String
        public let regionCode: String
        public let languageCode: String
        public let numberOfUnits: Double

        public init(foodId: String, servingId: String, source: String, regionCode: String, languageCode: String, numberOfUnits: Double) {
            self.foodId = foodId
            self.servingId = servingId
            self.source = source
            self.regionCode = regionCode
            self.languageCode = languageCode
            self.numberOfUnits = numberOfUnits
        }
    }

    public let mealName: String
    public let foodItems: [Item]

    public init(mealName: String, foodItems: [Item]) {
        self.mealName = mealName
        self.foodItems = foodItems
    }
}

/// The presumed response shape: just the new meal's id. Presumed `Int`
/// because the one real `customMealId` this project has observed
/// (docs/garmin-food-log-contract.md) decoded as a plain integer, and
/// `LoggedFood.customMealId` above is typed the same way. If the real
/// response is shaped differently, `createCustomMeal` throws
/// `GarminClientError.decodingFailed` rather than silently returning
/// something wrong.
public struct CreateCustomMealResponse: Decodable, Sendable {
    public let customMealId: Int
}

// MARK: - Weight (weight-service) -- add-weight-tracking, 2026-09-22 research

/// What the app wants to log -- deliberately not the wire body (mirrors
/// `CreateFoodLogEntryRequest`'s own separation), so `GarminClient.addWeighIn`
/// can format the two timestamp fields itself.
public struct AddWeighInRequest: Sendable, Equatable {
    public let weightKg: Double
    /// Local wall-clock moment of the weigh-in -- may be backdated (the app
    /// lets the user pick a past date/time for a missed entry).
    /// `WeighInWriteBody.make` derives BOTH `dateTimestamp` (this instant
    /// rendered in the given `timeZone`) and `gmtTimestamp` (the same
    /// instant converted to UTC) from this one value -- there is no separate
    /// "GMT" input, matching python-garminconnect's simpler `add_weigh_in`
    /// (as opposed to its `add_weigh_in_with_timestamps` sibling, which
    /// takes the two independently), since this app never needs a GMT value
    /// that isn't simply this instant's own UTC conversion.
    public let loggedAt: Date

    public init(weightKg: Double, loggedAt: Date = Date()) {
        self.weightKg = weightKg
        self.loggedAt = loggedAt
    }
}

/// The wire body for `POST /weight-service/user-weight`.
///
/// Source of truth: `cyberjunky/python-garminconnect` (github.com/cyberjunky/
/// python-garminconnect), a mature, actively-maintained, widely-used
/// open-source Garmin Connect client -- `garminconnect/__init__.py`,
/// `add_weigh_in`/`add_weigh_in_with_timestamps` (~lines 1414-1483 as fetched
/// 2026-09-22) and the shared `_fmt_ts` helper (~line 221):
/// ```
/// payload = {
///     "dateTimestamp": _fmt_ts(dt),        # dt.replace(tzinfo=None).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3]
///     "gmtTimestamp": _fmt_ts(dtGMT),      # dt.astimezone(UTC), same format
///     "unitKey": unitKey,                  # "kg" or "lbs" -- VALID_WEIGHT_UNITS = {"kg", "lbs"}
///     "sourceType": "MANUAL",
///     "value": weight,
/// }
/// ```
/// This is meaningfully stronger evidence than this project's usual
/// "decompiled string literal" tier -- it's a real field-name-and-format
/// contract another live client actually sends and presumably has users
/// exercising -- but it has never been called from THIS app against the
/// real account, so it stays UNCONFIRMED for this project until a real
/// device write is observed and reported back, matching
/// `CreateCustomFoodRequest`'s "documented, not yet exercised by us" status
/// tier (one step below `FoodLogWriteBody`'s, which garmin_mcp's own live
/// end-to-end tests back).
///
/// `unitKey`: note python-garminconnect's valid set is `{"kg", "lbs"}` --
/// "lbs", not "lb". Moot for this app: GarminFood has no imperial/metric
/// setting anywhere (checked before adding this -- no unit-system awareness
/// exists in the app today) and always sends `"kg"`, matching Garmin's own
/// internal body-metric storage unit.
struct WeighInWriteBody: Encodable, Equatable {
    let dateTimestamp: String
    let gmtTimestamp: String
    let unitKey: String
    let sourceType: String
    let value: Double

    static let unitKey = "kg"
    static let sourceType = "MANUAL"

    static func make(for request: AddWeighInRequest, timeZone: TimeZone = .current) -> WeighInWriteBody {
        WeighInWriteBody(
            dateTimestamp: timestampString(request.loggedAt, timeZone: timeZone),
            gmtTimestamp: timestampString(request.loggedAt, timeZone: TimeZone(identifier: "UTC") ?? .gmt),
            unitKey: unitKey,
            sourceType: sourceType,
            value: request.weightKg
        )
    }

    /// `2026-09-22T10:30:00.000` -- wall-clock time in `timeZone`, NO
    /// offset/`Z` suffix, millisecond precision. Confirmed exact shape:
    /// python-garminconnect's `_fmt_ts` does `dt.replace(tzinfo=None)
    /// .strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3]` -- format as naive local
    /// time, truncate microseconds to milliseconds. `WeighInWriteBody.make`
    /// passes the device's own `timeZone` for `dateTimestamp` and UTC for
    /// `gmtTimestamp`, exactly `add_weigh_in`'s `dt` vs `dt.astimezone(UTC)`
    /// split.
    static func timestampString(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
        formatter.timeZone = timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }
}

/// `GET /weight-service/weight/range/{startdate}/{enddate}?includeAll=true`.
///
/// ROUTE confirmed to exist via python-garminconnect's `get_weigh_ins`
/// (`garminconnect/__init__.py`, ~line 1487) -- `startdate`/`enddate` are
/// `YYYY-MM-DD`, `includeAll=true` is always sent as a query param, matching
/// this project's own task brief exactly.
///
/// RESPONSE SHAPE for this specific route is NOT confirmed field-by-field:
/// `get_weigh_ins` returns a plain `dict[str, Any]`, and nothing in that
/// source file ever indexes into it. `dateWeightList` below is a documented
/// GUESS by analogy with a SIBLING route, `get_daily_weigh_ins` (GET
/// `/weight-service/weight/dayview/{cdate}`, not implemented by this
/// package), whose response IS field-confirmed to carry a `dateWeightList`
/// array: `delete_weigh_ins` (~line 1520) reads `daily_weigh_ins.get(
/// "dateWeightList", [])`, then `w["samplePk"]` for each entry (~line 1538)
/// to build the delete route's `{weight_pk}` path segment -- further
/// confirmed by `delete_weigh_in`'s own `_validate_positive_integer` call on
/// that value, i.e. `samplePk` really is a positive `Int`. Two sibling
/// `/weight-service/weight/...` routes sharing the same envelope shape is a
/// reasonable inference, not a confirmation -- if wrong, decoding this type
/// simply yields `nil`/an empty list rather than throwing, matching this
/// package's lenient-decode convention (`FoodSearchResult`'s header).
public struct WeightRangeResponse: Decodable, Sendable {
    public let dateWeightList: [WeighInSample]?
}

// MARK: - Hydration (usersummary-service) -- add-hydration-tracking, 2026-09-22 research

/// What the app wants to log -- same separation from the wire body as
/// `AddWeighInRequest` above, for the same reason.
public struct AddHydrationRequest: Sendable, Equatable {
    public let valueInML: Double
    /// Local wall-clock moment of the drink -- may be backdated the same
    /// way a weigh-in can be. `HydrationWriteBody.make` derives BOTH
    /// `calendarDate` (this instant's own local date) and `timestampLocal`
    /// (this instant rendered in the given time zone) from this one value.
    public let loggedAt: Date

    public init(valueInML: Double, loggedAt: Date = Date()) {
        self.valueInML = valueInML
        self.loggedAt = loggedAt
    }
}

/// The wire body for `PUT /usersummary-service/usersummary/hydration/log`.
///
/// Source of truth: same file as `WeighInWriteBody` above --
/// `cyberjunky/python-garminconnect`'s `garminconnect/__init__.py`,
/// `add_hydration_data` (~lines 1820-1898 as fetched 2026-09-22):
/// ```
/// payload = {
///     "calendarDate": cdate,          # "YYYY-MM-DD", the LOCAL date of the entry
///     "timestampLocal": timestamp,    # local wall-clock, "%Y-%m-%dT%H:%M:%S.%f"[:-3] via the same _fmt_ts helper
///     "valueInML": value_in_ml,
/// }
/// ```
/// Same evidence tier as `WeighInWriteBody`: a real field-name-and-format
/// contract from a live, actively-maintained third-party client, never yet
/// called from THIS app against the real account -- see that struct's own
/// doc comment for the full reasoning, which applies here unchanged.
///
/// Only the write route is implemented. `GET /usersummary-service/
/// usersummary/hydration/daily/{date}` (`garmin_connect_daily_hydration_url`
/// in the same source file) exists but its response is never destructured
/// anywhere in that library either (`get_hydration_data` just returns the
/// raw dict) -- there is even less field-level evidence for it than for
/// `WeightRangeResponse`'s already-guessed shape, so it isn't implemented
/// here at all rather than shipping a second, weaker guess. This app's own
/// `HydrationStore` (FoodLogCore) is the sole source of truth for history
/// and today's total, exactly like `WeightStore` is for weight -- see that
/// type's header.
struct HydrationWriteBody: Encodable, Equatable {
    let calendarDate: String
    let timestampLocal: String
    let valueInML: Double

    static func make(for request: AddHydrationRequest, timeZone: TimeZone = .current) -> HydrationWriteBody {
        HydrationWriteBody(
            calendarDate: calendarDateString(request.loggedAt, timeZone: timeZone),
            timestampLocal: WeighInWriteBody.timestampString(request.loggedAt, timeZone: timeZone),
            valueInML: request.valueInML
        )
    }

    private static func calendarDateString(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }
}

/// One sample within `WeightRangeResponse` (and, presumably, the
/// unimplemented day-view route's response). See `WeightRangeResponse`'s
/// header for exactly which field is confirmed (`samplePk`) vs guessed
/// (everything else) and why.
///
/// Moved back next to this declaration 2026-09-22 (a code-review finding):
/// the Hydration section above was inserted between this comment and the
/// struct it describes, leaving a reader who follows `WeightRangeResponse`'s
/// own doc comment landing in unrelated Hydration code before ever reaching
/// what it was describing.
public struct WeighInSample: Decodable, Sendable {
    /// CONFIRMED name and type (positive `Int`): the value python-
    /// garminconnect's `delete_weigh_in` sends as its `{weight_pk}` path
    /// segment, read from exactly this field on exactly this kind of
    /// object.
    public let samplePk: Int?
    /// UNCONFIRMED guess -- no evidence for this field's name was found
    /// anywhere in python-garminconnect. Grams is this project's own
    /// best-guess unit (Garmin's typical internal body-metric storage
    /// unit); this app's own WRITE always sends kilograms (`unitKey: "kg"`),
    /// which is not proof the READ side uses the same unit.
    public let weight: Double?
    /// UNCONFIRMED guess at the date field's name -- kept alongside
    /// `calendarDate` (another plausible Garmin naming, seen elsewhere in
    /// this project e.g. `dailyWellnessSummary`'s `calendarDate` query
    /// param) since neither has any real evidence backing it for this
    /// specific route.
    public let date: String?
    public let calendarDate: String?
    public let sourceType: String?
}
