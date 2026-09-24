// GarminClient.swift
//
// The API client. Read routes (`searchFood`, `dailyFoodLog`) are confirmed
// live against the real account as of 2026-09-14 (docs/garmin-routes.json).
// Write routes (`createFoodLogEntry`, `deleteFoodLogEntries`) follow the
// contract garmin_mcp uses against a real account (see FoodLogWriteBody in
// GarminModels.swift and docs/garmin-food-log-contract.md). Create is
// CONFIRMED by this project's own first real write (2026-09-16). Delete is
// still unexercised here.
//
// This type deliberately does not decode or trust the response body of
// `createFoodLogEntry` for anything -- design.md D5 already assumes the
// only trustworthy signal after a write is a fresh read of the day's log
// (Reconciliation.swift), so a wrong guess about the create response shape
// can't silently corrupt anything downstream.
//
// `createCustomFood` (add-czech-food-catalog, task group 30) is the one
// exception to that "don't trust the response body" rule: it MUST decode
// the response to learn the newly created food's Garmin `foodId` before
// anything can be logged against it, so there is no read-back-and-verify
// step available the way `createFoodLogEntry` has via
// Reconciliation.swift. Its request shape is now a real third-party
// client's confirmed contract (2026-09-22 correction, `CustomFoodWriteBody`
// in GarminModels.swift); its response shape remains an educated guess --
// see both doc comments for the full reasoning.
//
// `addWeighIn`/`getWeighIns` (add-weight-tracking, 2026-09-22) add
// `weight-service` routes. Their evidence tier is DIFFERENT from every
// route above: sourced from `cyberjunky/python-garminconnect`, a real
// third-party OSS client's actual field names and formats, not a
// decompiled string literal or blind guess -- but, like `createCustomFood`,
// never yet called by THIS project against the real account. See
// `WeighInWriteBody`/`WeightRangeResponse`'s doc comments in
// GarminModels.swift.
//
// UPDATE 2026-09-23 (sync-weight-hydration-with-garmin): `addWeighIn` is
// now CONFIRMED (owner-approved probe + device reports), and the weight/
// hydration READS were live-probed: `weighInRange` (range route, replaces
// the never-called `getWeighIns` and its wrong response guess),
// `weighIns(on:)` (dayview), `hydrationDaily(date:)`, plus
// `deleteWeighIn(date:samplePk:)` (owner-approved probe, 204). Garmin is
// now the source of truth for weigh-ins and the daily water total.
//
// `calorieSummaryDaily` (add-trends-and-insights, 2026-09-22) is a READ the
// route registry already had confirmed live (2026-09-14, as a standalone
// probe) but this project had never actually called from its own code until
// now -- unlike the weight routes above, its evidence tier doesn't change:
// still "confirmed live with a real date range", not "device-verified
// against this app's own UI". Powers the Trends screen's ~30-day macro
// chart in one call instead of one `dailyFoodLog` per day.

import Foundation

public enum GarminClientError: Error, Sendable {
    case invalidURL
    case noHTTPResponse
    case unauthorized(body: String?)
    case rateLimited(retryAfterSeconds: Double?)
    case httpError(statusCode: Int, body: String?)
    case decodingFailed(description: String)
}

public struct GarminClient: Sendable {
    private let tokenProvider: TokenProvider
    private let urlSession: URLSession
    private let baseURL: String

    public init(
        tokenProvider: TokenProvider = .shared,
        urlSession: URLSession = .shared,
        baseURL: String = GarminAPI.connectAPI
    ) {
        self.tokenProvider = tokenProvider
        self.urlSession = urlSession
        self.baseURL = baseURL
    }

    private static let decoder = JSONDecoder()
    private static let encoder = JSONEncoder()

    // MARK: - Reads

    /// GET `/nutrition-service/food/search?searchExpression={term}&start=&limit=[&regionCode=]`.
    /// Confirmed live 2026-09-14; paging and region re-probed read-only
    /// 2026-09-23 (docs/garmin-routes.json `foodSearch`): `limit` is at most
    /// 50 and `start` must be divisible by it (400 otherwise);
    /// `moreDataAvailable` says whether another page exists. `regionCode`
    /// (e.g. "CZ") selects FatSecret's regional catalogue; `languageCode`
    /// "cs" is rejected, so it is never sent.
    public func searchFood(term: String, start: Int, limit: Int, regionCode: String?) async throws -> FoodSearchResponse {
        var query = [
            URLQueryItem(name: "searchExpression", value: term),
            URLQueryItem(name: "start", value: String(start)),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        if let regionCode, !regionCode.isEmpty {
            query.append(URLQueryItem(name: "regionCode", value: regionCode))
        }
        let (data, response) = try await get(path: "/nutrition-service/food/search", query: query)
        try Self.throwIfNotSuccessful(response, data: data)
        do {
            return try Self.decoder.decode(FoodSearchResponse.self, from: data)
        } catch {
            throw GarminClientError.decodingFailed(description: String(describing: error))
        }
    }

    /// GET `/nutrition-service/food/logs/{date}` (`date` is `YYYY-MM-DD`).
    /// Confirmed live 2026-09-14 -- the plural "logs" route; the vault's
    /// singular "log" route 404s and is NOT what this calls.
    ///
    /// Returns `nil` on 404 rather than throwing. Per design.md D7 ("auth
    /// failure is loud; everything else is quiet") and the garmin-auth
    /// spec's "a route is merely unavailable, not an auth failure" scenario,
    /// no logged food for a date is missing DATA, not a broken credential --
    /// callers must not conflate the two the way the vault's own
    /// `getNutritionLog()` historically did (see design.md D7's rationale).
    public func dailyFoodLog(date: String) async throws -> DailyFoodLog? {
        let (data, response) = try await get(path: "/nutrition-service/food/logs/\(date)", query: [])
        if response.statusCode == 404 { return nil }
        try Self.throwIfNotSuccessful(response, data: data)
        do {
            return try Self.decoder.decode(DailyFoodLog.self, from: data)
        } catch {
            throw GarminClientError.decodingFailed(description: String(describing: error))
        }
    }

    /// GET `/nutrition-service/food/search/barCode?barCode={ean}`.
    ///
    /// Added for `add-food-log-core`'s (deprioritized, per that change's
    /// design.md D3) barcode-scanning feature. Route CONFIRMED to exist
    /// 2026-09-14 (a no-param request 400s naming the right parameter), but
    /// the SUCCESS payload shape is UNCONFIRMED -- every real-looking EAN-13
    /// tried so far 404'd ("no product for this barcode", not "route
    /// missing"). Modeled as a single `FoodSearchResult` (the same shape one
    /// entry of `searchFood`'s `results` array uses) since a barcode lookup
    /// is conceptually "find the one food this code identifies" -- if
    /// Garmin's real response turns out to wrap this differently (e.g.
    /// `{ result: {...} }` or a bare `results: [...]` array like the text
    /// search), this decode will fail and surface as
    /// `GarminClientError.decodingFailed`, not silently return the wrong
    /// thing.
    ///
    /// Returns `nil` on 404, matching `dailyFoodLog`'s convention: no
    /// product for this barcode is missing DATA, not a broken credential or
    /// a broken route.
    public func searchFoodByBarcode(ean: String) async throws -> FoodSearchResult? {
        let (data, response) = try await get(
            path: "/nutrition-service/food/search/barCode",
            query: [URLQueryItem(name: "barCode", value: ean)]
        )
        if response.statusCode == 404 { return nil }
        try Self.throwIfNotSuccessful(response, data: data)
        do {
            return try Self.decoder.decode(FoodSearchResult.self, from: data)
        } catch {
            throw GarminClientError.decodingFailed(description: String(describing: error))
        }
    }

    /// GET `/nutrition-service/meals/{date}`. Confirmed live 2026-09-16:
    /// returns the date's meal definitions (per-date numeric `mealId`, name,
    /// and for all but SNACKS a startTime/endTime window) whether or not
    /// anything is logged, which `dailyFoodLog` can't promise.
    public func mealsForDate(date: String) async throws -> MealsForDate {
        let (data, response) = try await get(path: "/nutrition-service/meals/\(date)", query: [])
        try Self.throwIfNotSuccessful(response, data: data)
        do {
            return try Self.decoder.decode(MealsForDate.self, from: data)
        } catch {
            throw GarminClientError.decodingFailed(description: String(describing: error))
        }
    }

    /// GET `/nutrition-service/settings/{date}`. Confirmed live 2026-09-16:
    /// the calorie goal, macro goals in grams, and the weight plan.
    public func nutritionSettings(date: String) async throws -> NutritionSettings {
        let (data, response) = try await get(path: "/nutrition-service/settings/\(date)", query: [])
        try Self.throwIfNotSuccessful(response, data: data)
        do {
            return try Self.decoder.decode(NutritionSettings.self, from: data)
        } catch {
            throw GarminClientError.decodingFailed(description: String(describing: error))
        }
    }

    /// GET `/nutrition-service/calorie/summary/daily?startDate={date}&endDate={date}`
    /// (dates `YYYY-MM-DD`). Route confirmed live 2026-09-14 as a standalone
    /// probe (docs/garmin-routes.json); this is the first time GarminClient
    /// itself calls it (add-trends-and-insights, 2026-09-22). One call
    /// covers a whole date range -- the Trends screen's ~30-day macro chart
    /// uses this instead of 30 separate `dailyFoodLog` reads.
    ///
    /// Does NOT special-case 404 the way `dailyFoodLog`/`searchFoodByBarcode`
    /// do -- a day with nothing logged is represented WITHIN a 200 response
    /// (its `nutritionContent`/`nutritionGoals` simply absent, per
    /// `CalorieSummaryDay`'s doc comment in GarminModels.swift), not by the
    /// route 404ing, per the probe's own observation.
    public func calorieSummaryDaily(startDate: String, endDate: String) async throws -> CalorieSummaryDailyResponse {
        let (data, response) = try await get(
            path: "/nutrition-service/calorie/summary/daily",
            query: [
                URLQueryItem(name: "startDate", value: startDate),
                URLQueryItem(name: "endDate", value: endDate)
            ]
        )
        try Self.throwIfNotSuccessful(response, data: data)
        do {
            return try Self.decoder.decode(CalorieSummaryDailyResponse.self, from: data)
        } catch {
            throw GarminClientError.decodingFailed(description: String(describing: error))
        }
    }

    /// GET `/userprofile-service/socialProfile`. Confirmed live 2026-09-16:
    /// display name, full name and profile photo URLs.
    public func socialProfile() async throws -> SocialProfile {
        let (data, response) = try await get(path: "/userprofile-service/socialProfile", query: [])
        try Self.throwIfNotSuccessful(response, data: data)
        do {
            return try Self.decoder.decode(SocialProfile.self, from: data)
        } catch {
            throw GarminClientError.decodingFailed(description: String(describing: error))
        }
    }

    /// GET `/usersummary-service/usersummary/daily?calendarDate={date}`
    /// (`YYYY-MM-DD`). The route itself was confirmed live 2026-09-14 as an
    /// auth control probe; its calorie fields (`activeKilocalories` et al.)
    /// were confirmed with real values 2026-09-23 (docs/garmin-routes.json
    /// `dailyWellnessSummary`). Read-only. Powers the home screen's
    /// informational "Active today" line (fix-testing-feedback-quick-wins);
    /// callers treat any failure as "hide the line", never as an error.
    public func dailyUserSummary(date: String) async throws -> DailyUserSummary {
        let (data, response) = try await get(
            path: "/usersummary-service/usersummary/daily",
            query: [URLQueryItem(name: "calendarDate", value: date)]
        )
        try Self.throwIfNotSuccessful(response, data: data)
        do {
            return try Self.decoder.decode(DailyUserSummary.self, from: data)
        } catch {
            throw GarminClientError.decodingFailed(description: String(describing: error))
        }
    }

    /// GET `/activitylist-service/activities/search/activities?startDate=&endDate=&limit=`
    /// (dates `yyyy-MM-dd`). READ-ONLY -- confirmed 200 by a read-only probe
    /// against the owner's live account on 2026-09-24 (docs/garmin-routes.json
    /// `activitiesSearch`): a bare JSON array of activities, see
    /// `GarminActivity`. Keep `limit` <= 20 (the probe could only see 20 KB of
    /// body; larger pages are unverified). Used only by the app's
    /// `GamificationSignalsSync` on refresh -- never on a confirm path.
    /// NOT yet device-verified from this project's own code.
    public func activities(startDate: String, endDate: String, limit: Int) async throws -> [GarminActivity] {
        let (data, response) = try await get(
            path: "/activitylist-service/activities/search/activities",
            query: [
                URLQueryItem(name: "startDate", value: startDate),
                URLQueryItem(name: "endDate", value: endDate),
                URLQueryItem(name: "limit", value: String(limit))
            ]
        )
        try Self.throwIfNotSuccessful(response, data: data)
        do {
            return try Self.decoder.decode([GarminActivity].self, from: data)
        } catch {
            DiagnosticsLog.log(.error, category: "GarminClient", "activities \(startDate)..\(endDate) did not decode: \(String(describing: error).prefix(300))")
            throw GarminClientError.decodingFailed(description: String(describing: error))
        }
    }

    // MARK: - Writes (create confirmed 2026-09-16; delete not yet exercised)

    /// PUT `/nutrition-service/food/logs`, body per `FoodLogWriteBody`.
    ///
    /// Two requests, not one: the body needs the date's meal INSTANCE id,
    /// which only exists server-side per date, so it is looked up here at
    /// delivery time rather than at confirm time -- an entry can be queued
    /// offline for a day it has never fetched. A missing meal throws
    /// `FoodLogWriteError.mealNotFound` before anything is written.
    @discardableResult
    public func createFoodLogEntry(_ entry: CreateFoodLogEntryRequest) async throws -> HTTPURLResponse {
        let meals = try await mealsForDate(date: entry.date).meals ?? []
        let body = try FoodLogWriteBody.make(for: entry, meals: meals)
        let (data, response) = try await put(path: "/nutrition-service/food/logs", body: body)
        try Self.throwIfNotSuccessful(response, data: data)
        return response
    }

    /// DELETE `/nutrition-service/food/logs/{date}`, body `{ "logIds": [...] }`,
    /// as garmin_mcp's `delete_food_log` sends it. The date is part of the
    /// path; the earlier inferred route omitted it. `logIds` are the hex
    /// `logId` values from a read entry, not `foodId`s. Used by
    /// Reconciliation.swift to remove a detected duplicate.
    @discardableResult
    public func deleteFoodLogEntries(logIds: [String], date: String) async throws -> HTTPURLResponse {
        let (data, response) = try await delete(
            path: "/nutrition-service/food/logs/\(date)",
            body: DeleteFoodLogEntriesRequest(logIds: logIds)
        )
        try Self.throwIfNotSuccessful(response, data: data)
        return response
    }

    /// PUT `/nutrition-service/customFood` (add-czech-food-catalog design.md
    /// D4, task 30.1 -- CORRECTED 2026-09-22).
    ///
    /// The ORIGINAL flat POST guess 400'd on a real device: "custom food
    /// nutrition information is missing for the provided food id with
    /// region code and language code". A first attempted fix (adding
    /// top-level regionCode/languageCode) did NOT resolve it, because the
    /// real problem was the envelope shape itself, not a missing field --
    /// see `CustomFoodWriteBody`'s doc comment in GarminModels.swift for
    /// the full, now-evidence-backed contract (method, nesting, and
    /// numbers-as-strings, all confirmed against a real third-party
    /// client's source, not guessed).
    ///
    /// The response is decoded as a `FoodSearchResult` -- the exact same
    /// `foodMetaData`/`nutritionContents` envelope shape the confirmed
    /// source client's own response type (`FoodItem`) uses, so this is a
    /// stronger bet than the request shape was, but still not
    /// device-confirmed for the response specifically. If the real response
    /// is shaped differently, this throws `GarminClientError.
    /// decodingFailed` rather than silently returning something wrong.
    ///
    /// IMPORTANT, same rule as `createFoodLogEntry`'s task 11.4 above:
    /// nothing in this package invokes this automatically, and per
    /// add-czech-food-catalog task 30.4 nothing in the app layer may
    /// either -- the first (and every) real invocation is a deliberate
    /// action the user takes by tapping "Create in Garmin" after reviewing
    /// the exact name and macro values that will be sent.
    public func createCustomFood(
        name: String,
        servingUnit: String,
        numberOfUnits: Double = 100,
        calories: Double,
        protein: Double? = nil,
        carbs: Double? = nil,
        fat: Double? = nil,
        regionCode: String? = nil,
        languageCode: String? = nil
    ) async throws -> FoodSearchResult {
        let body = CustomFoodWriteBody.make(
            foodName: name,
            servingUnit: servingUnit,
            numberOfUnits: numberOfUnits,
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat,
            regionCode: regionCode,
            languageCode: languageCode
        )
        let (data, response) = try await put(path: "/nutrition-service/customFood", body: body)
        try Self.throwIfNotSuccessful(response, data: data)
        do {
            return try Self.decoder.decode(FoodSearchResult.self, from: data)
        } catch {
            throw GarminClientError.decodingFailed(description: String(describing: error))
        }
    }

    /// POST `/nutrition-service/customMeal` (add-meal-presets, 2026-09-22
    /// research task).
    ///
    /// ROUTE CONFIRMED TO EXIST (decompiled Android client string literal,
    /// docs/garmin-routes.json) AND the concept is confirmed in active use
    /// on this very account -- a real `customMealId` already shows up on a
    /// logged food entry, created by the official Garmin Connect Mobile app
    /// -- but, exactly like `createCustomFood` above, BOTH the request and
    /// response shapes are genuinely unconfirmed guesses; see
    /// `CreateCustomMealRequest`'s doc comment in GarminModels.swift for
    /// what's being guessed and why.
    ///
    /// Same rule as `createCustomFood`/`createFoodLogEntry`: nothing in this
    /// package invokes this automatically, and nothing in the app layer may
    /// either -- the only real invocation is the user's own deliberate
    /// "Sync to Garmin (experimental)" tap after reviewing exactly what's
    /// about to be sent.
    public func createCustomMeal(name: String, items: [CustomMealItemInput]) async throws -> CreateCustomMealResponse {
        let body = CreateCustomMealRequest(
            mealName: name,
            foodItems: items.map { item in
                CreateCustomMealRequest.Item(
                    foodId: item.foodId,
                    servingId: item.servingId,
                    source: item.source,
                    // Baked in here, not exposed as a caller-supplied
                    // parameter -- same reasoning as `createCustomFood`
                    // above: the app layer shouldn't need to know these
                    // constants exist, and there is no other confirmed
                    // value to use.
                    regionCode: FoodLogWriteBody.regionCode,
                    languageCode: FoodLogWriteBody.languageCode,
                    numberOfUnits: item.numberOfUnits
                )
            }
        )
        let (data, response) = try await post(path: "/nutrition-service/customMeal", body: body)
        try Self.throwIfNotSuccessful(response, data: data)
        do {
            return try Self.decoder.decode(CreateCustomMealResponse.self, from: data)
        } catch {
            throw GarminClientError.decodingFailed(description: String(describing: error))
        }
    }

    // MARK: - Weight (add-weight-tracking, 2026-09-22)

    /// POST `/weight-service/user-weight`, body per `WeighInWriteBody`.
    ///
    /// Same "don't trust the response body" stance as `createFoodLogEntry`:
    /// a caller that needs proof of persistence should re-read via
    /// `weighInRange`, not trust this call's 2xx alone. This route's own
    /// evidence tier (see `WeighInWriteBody`'s doc comment in
    /// GarminModels.swift) sits one step below `createFoodLogEntry`'s
    /// (garmin_mcp, a live-tested client with its own end-to-end tests
    /// against a real Garmin account): a real, actively-maintained
    /// third-party OSS client's exact request shape, with a citation that
    /// was independently checked and holds up, just never yet exercised BY
    /// THIS APP against the real account. `createCustomFood`'s evidence is
    /// different in kind, not just degree -- see `CustomFoodWriteBody`'s
    /// doc comment in GarminModels.swift, which found and corrected a false
    /// citation in its own source client on a second verification pass.
    ///
    /// Not gated behind an extra confirmation the way `createCustomFood`/
    /// `createCustomMeal` are: logging a weight IS the deliberate user
    /// action (tapping "Save" on the Add Weight screen), same as logging a
    /// food is for `createFoodLogEntry` -- Garmin's own official app logs a
    /// weigh-in immediately as a normal flow too, there is nothing
    /// "experimental-feature-shaped" about this write the way an unreviewed
    /// custom-food/custom-meal creation is. Delivery still goes through
    /// `WeightOutbox`'s durable local-first queue (WeightSync.swift),
    /// exactly mirroring `Outbox`'s shape for food logs, so this method
    /// itself is never called synchronously from a UI action.
    @discardableResult
    public func addWeighIn(_ request: AddWeighInRequest) async throws -> HTTPURLResponse {
        let body = WeighInWriteBody.make(for: request)
        let (data, response) = try await post(path: "/weight-service/user-weight", body: body)
        try Self.throwIfNotSuccessful(response, data: data)
        return response
    }

    /// GET `/weight-service/weight/range/{startdate}/{enddate}?includeAll=true`
    /// (dates `YYYY-MM-DD`, inclusive). LIVE-PROBED read-only 2026-09-23
    /// (docs/garmin-routes.json `getWeighIns`): 200 with
    /// `dailyWeightSummaries[].allWeightMetrics[]` -- see
    /// `WeightRangeResponse`'s doc comment in GarminModels.swift. One call
    /// covers the Weight screen's whole 90-day history (design.md D2's
    /// "if the probe confirms that shape, use it as one call" path), so no
    /// per-day dayview fan-out is needed. Days without a weigh-in are
    /// omitted from the response, not returned empty.
    ///
    /// Replaces the unused 2026-09-22 `getWeighIns(startDate:endDate:)`,
    /// whose response type was a guess that would not have decoded.
    public func weighInRange(startDate: String, endDate: String) async throws -> WeightRangeResponse {
        let (data, response) = try await get(
            path: "/weight-service/weight/range/\(startDate)/\(endDate)",
            query: [URLQueryItem(name: "includeAll", value: "true")]
        )
        try Self.throwIfNotSuccessful(response, data: data)
        let decoded: WeightRangeResponse
        do {
            decoded = try Self.decoder.decode(WeightRangeResponse.self, from: data)
        } catch {
            DiagnosticsLog.log(.error, category: "GarminClient", "weight range \(startDate)..\(endDate) did not decode: \(String(describing: error).prefix(300))")
            throw GarminClientError.decodingFailed(description: String(describing: error))
        }
        if decoded.skippedCount > 0 {
            DiagnosticsLog.log(.warning, category: "GarminClient", "weight range \(startDate)..\(endDate): skipped \(decoded.skippedCount) weigh-in(s) that did not decode")
        }
        return decoded
    }

    /// GET `/weight-service/weight/dayview/{date}?includeAll=true` (date
    /// `YYYY-MM-DD`). LIVE-PROBED 2026-09-23 (docs/garmin-routes.json
    /// `weighInsDayView`): `dateWeightList[]` of `GarminWeighIn`, grams,
    /// newest first. The app's refresh path uses `weighInRange` (one call
    /// for many days); this single-day read is kept as the documented
    /// fallback should the range route ever break (design.md D2).
    public func weighIns(on date: String) async throws -> WeighInDayView {
        let (data, response) = try await get(
            path: "/weight-service/weight/dayview/\(date)",
            query: [URLQueryItem(name: "includeAll", value: "true")]
        )
        try Self.throwIfNotSuccessful(response, data: data)
        let decoded: WeighInDayView
        do {
            decoded = try Self.decoder.decode(WeighInDayView.self, from: data)
        } catch {
            DiagnosticsLog.log(.error, category: "GarminClient", "weight dayview \(date) did not decode: \(String(describing: error).prefix(300))")
            throw GarminClientError.decodingFailed(description: String(describing: error))
        }
        if decoded.skippedCount > 0 {
            DiagnosticsLog.log(.warning, category: "GarminClient", "weight dayview \(date): skipped \(decoded.skippedCount) weigh-in(s) that did not decode")
        }
        return decoded
    }

    /// DELETE `/weight-service/weight/{date}/byversion/{samplePk}` with a
    /// `{}` body. LIVE-CONFIRMED 2026-09-23 with the owner's explicit
    /// approval (docs/garmin-routes.json `weighInDelete`): 204, and a
    /// re-read no longer listed the sample while the day's other weigh-ins
    /// were untouched. `date` is the sample's own `calendarDate`,
    /// `samplePk` its `samplePk` -- both straight from a `GarminWeighIn`.
    ///
    /// Like `addWeighIn`, never called synchronously from a UI action:
    /// the user's delete is enqueued in `WeightOutbox` (a `.delete`
    /// operation) and delivered by its drain, so it survives being offline
    /// and a failure shows in the sync queue instead of being lost.
    @discardableResult
    public func deleteWeighIn(date: String, samplePk: Int) async throws -> HTTPURLResponse {
        let (data, response) = try await delete(
            path: "/weight-service/weight/\(date)/byversion/\(samplePk)",
            body: EmptyJSONBody()
        )
        try Self.throwIfNotSuccessful(response, data: data)
        return response
    }

    // MARK: - Hydration (add-hydration-tracking, 2026-09-22)

    /// PUT `/usersummary-service/usersummary/hydration/log`, body per
    /// `HydrationWriteBody`. Same evidence tier and same "not gated behind
    /// an extra confirmation" reasoning as `addWeighIn` above -- logging a
    /// drink IS the deliberate user action, and delivery goes through
    /// `HydrationOutbox`'s durable local-first queue (HydrationSync.swift),
    /// so this method is never called synchronously from a UI action.
    @discardableResult
    public func addHydration(_ request: AddHydrationRequest) async throws -> HTTPURLResponse {
        let body = HydrationWriteBody.make(for: request)
        let (data, response) = try await put(path: "/usersummary-service/usersummary/hydration/log", body: body)
        try Self.throwIfNotSuccessful(response, data: data)
        return response
    }

    /// GET `/usersummary-service/usersummary/hydration/daily/{date}` (date
    /// `YYYY-MM-DD`). LIVE-PROBED 2026-09-23 (docs/garmin-routes.json
    /// `hydrationDaily`): the day's TOTAL (`valueInML`) and Garmin's goal
    /// (`goalInML`) -- see `HydrationDaily`'s doc comment. Makes Garmin the
    /// source of truth for "water today" (sync-weight-hydration-with-garmin),
    /// so water logged on the watch or in Connect counts too.
    public func hydrationDaily(date: String) async throws -> HydrationDaily {
        let (data, response) = try await get(path: "/usersummary-service/usersummary/hydration/daily/\(date)", query: [])
        try Self.throwIfNotSuccessful(response, data: data)
        do {
            return try Self.decoder.decode(HydrationDaily.self, from: data)
        } catch {
            DiagnosticsLog.log(.error, category: "GarminClient", "hydration daily \(date) did not decode: \(String(describing: error).prefix(300))")
            throw GarminClientError.decodingFailed(description: String(describing: error))
        }
    }

    // MARK: - Request plumbing

    private func authorizedRequest(method: String, path: String, query: [URLQueryItem] = []) async throws -> URLRequest {
        guard var components = URLComponents(string: baseURL + path) else {
            throw GarminClientError.invalidURL
        }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw GarminClientError.invalidURL }

        // Propagates GarminAuthError.notSignedIn / .longLivedTokenExpired /
        // .exchangeFailed straight through to the caller -- GarminClient
        // does not catch or reinterpret token errors, so AuthState.report(_:)
        // downstream sees the real underlying error.
        let token = try await tokenProvider.accessToken()

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(GarminUserAgent.value, forHTTPHeaderField: "User-Agent")
        return request
    }

    private func get(path: String, query: [URLQueryItem]) async throws -> (Data, HTTPURLResponse) {
        try await send { try await self.authorizedRequest(method: "GET", path: path, query: query) }
    }

    private func post(path: String, body: some Encodable) async throws -> (Data, HTTPURLResponse) {
        try await send {
            var request = try await self.authorizedRequest(method: "POST", path: path)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try Self.encoder.encode(body)
            return request
        }
    }

    private func put(path: String, body: some Encodable) async throws -> (Data, HTTPURLResponse) {
        try await send {
            var request = try await self.authorizedRequest(method: "PUT", path: path)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try Self.encoder.encode(body)
            return request
        }
    }

    private func delete(path: String, body: some Encodable) async throws -> (Data, HTTPURLResponse) {
        try await send {
            var request = try await self.authorizedRequest(method: "DELETE", path: path)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try Self.encoder.encode(body)
            return request
        }
    }

    /// Builds and sends a request via `requestBuilder`, retrying exactly
    /// once with a forced-fresh OAuth2 token if the FIRST attempt comes back
    /// 401 (R6).
    ///
    /// A 401 from a data route (as opposed to the OAuth1->OAuth2 exchange
    /// route itself, which `TokenProvider.refreshAccessToken` handles on its
    /// own terms) has no single confirmed cause -- the write routes in
    /// particular are explicitly DOCUMENTED-BUT-UNCONFIRMED (see this file's
    /// header) and could plausibly 401 for a reason other than "the cached
    /// OAuth2 token happened to expire between mint and use". Forcing one
    /// fresh exchange and retrying once costs nothing on the (expected to be
    /// common) happy path, and gives a real chance of recovery before an
    /// outbox entry burns one of its bounded retry attempts or an app-layer
    /// read call gives up.
    ///
    /// `requestBuilder` is re-invoked (not just re-signed) for the retry so
    /// it picks up whatever fresh token `tokenProvider.accessToken()` now
    /// has cached -- `refreshAccessToken()` below populates that cache, so
    /// this does not trigger a second network exchange.
    ///
    /// If the long-lived OAuth1 token itself is dead, `refreshAccessToken()`
    /// throws `GarminAuthError.longLivedTokenExpired` here and that
    /// propagates straight through, same as any other token error from
    /// `authorizedRequest`.
    private func send(_ requestBuilder: () async throws -> URLRequest) async throws -> (Data, HTTPURLResponse) {
        let request = try await requestBuilder()
        let (data, http) = try await perform(request)
        guard http.statusCode == 401 else { return (data, http) }

        _ = try await tokenProvider.refreshAccessToken()
        let retryRequest = try await requestBuilder()
        return try await perform(retryRequest)
    }

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            // A request cancelled on purpose (search-as-you-type drops the
            // previous keystroke's request) is not a failure worth logging.
            let cancelled = error is CancellationError || (error as? URLError)?.code == .cancelled
            if !cancelled {
                DiagnosticsLog.log(.error, category: "GarminClient", "\(request.httpMethod ?? "?") \(request.url?.path ?? "?") failed: \(error.localizedDescription)")
            }
            throw error
        }
        guard let http = response as? HTTPURLResponse else {
            DiagnosticsLog.log(.error, category: "GarminClient", "\(request.httpMethod ?? "?") \(request.url?.path ?? "?") returned no HTTP response")
            throw GarminClientError.noHTTPResponse
        }
        return (data, http)
    }

    private static func throwIfNotSuccessful(_ response: HTTPURLResponse, data: Data) throws {
        if (200..<300).contains(response.statusCode) { return }
        let body = String(data: data, encoding: .utf8)
        let path = response.url?.path ?? "?"
        DiagnosticsLog.log(.warning, category: "GarminClient", "\(path) returned \(response.statusCode)\(body.map { ": \($0.prefix(300))" } ?? "")")
        switch response.statusCode {
        case 401:
            throw GarminClientError.unauthorized(body: body)
        case 429:
            let retryAfter = response.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
            throw GarminClientError.rateLimited(retryAfterSeconds: retryAfter)
        default:
            throw GarminClientError.httpError(statusCode: response.statusCode, body: body)
        }
    }
}

// MARK: - Outbox.swift / Reconciliation.swift protocol conformance
//
// Structural conformance: `GarminClient`'s existing method signatures
// already match `FoodLogDelivering` and `FoodLogReconciling` exactly, so
// this is declared here purely to make the relationship explicit and
// discoverable, not because any method bodies are needed.

extension GarminClient: FoodLogDelivering {}
extension GarminClient: FoodLogReconciling {}
extension GarminClient: WeighInDelivering {
    /// The dayview read's samples (`weighIns(on:)`, live-probed read-only
    /// 2026-09-23) -- how `WeightOutbox.drain` resolves a delete-by-match.
    public func weighInSamples(on date: String) async throws -> [GarminWeighIn] {
        try await weighIns(on: date).weighIns
    }
}
extension GarminClient: HydrationDelivering {}
