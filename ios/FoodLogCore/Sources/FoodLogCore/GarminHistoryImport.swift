// GarminHistoryImport.swift
//
// add-standalone-mode task 5.5 (design D10, "Copy my last 90 days from
// Garmin"): an explicit, optional action in standalone mode that copies the
// food the user logged in Garmin over the last 90 days into this phone's
// local food log, so switching to standalone doesn't start from an empty
// history (Trends, streak-adjacent views, "Log again").
//
// READ-ONLY toward Garmin: it only calls the confirmed read route
// `GET /nutrition-service/food/logs/{date}` (confirmed live 2026-09-14,
// docs/garmin-routes.json) through `NutritionLogReading.dailyFoodLog`,
// one day at a time. Nothing is ever written to Garmin.
//
// Mapping mirrors `LocalNutritionReader.loggedFood` in reverse, so a copied
// entry reads back exactly as Garmin showed it: `nutritionContent` is PER
// SERVING and `servingQty` is how many servings, so the stored (logged)
// amount is per-serving x quantity -- the same rule `MealDashboard.
// syncedEntries` uses on a Garmin read.
//
// Idempotent: a copied entry's id is derived from the day and Garmin's
// `logId`, so running the action again (or after a partial run) skips what
// is already on the phone instead of duplicating it. Days are read oldest
// first; the run stops at once on a sign-in problem or rate limit (loud,
// CLAUDE.md) and otherwise counts a day that couldn't be read and goes on.
//
// Depends on: GarminKit (NutritionLogReading, DailyFoodLog, LoggedFood,
// GarminClientError), LocalFoodLogStore, MealType, NutrientKind.
// Depended on by: the app's DataModeSection via AppEnvironment.
// Tests: GarminHistoryImportTests.

import Foundation
import CryptoKit
import GarminKit

public enum GarminHistoryImport {
    public static let defaultDays = 90

    public struct Result: Sendable, Equatable {
        /// Days Garmin answered for (with or without food).
        public var daysRead = 0
        /// Entries added to the phone's food log.
        public var entriesCopied = 0
        /// Entries skipped because an earlier copy already added them.
        public var alreadyOnPhone = 0
        /// Days that couldn't be read (anything but sign-in / rate limit).
        public var failedDays = 0

        public init() {}
    }

    public enum ImportError: Error, Sendable, Equatable {
        /// Garmin refused the sign-in; nothing after this day was read.
        case signInNeeded(copiedSoFar: Int)
        /// Garmin asked us to slow down; nothing after this day was read.
        case rateLimited(copiedSoFar: Int)
        /// `maxConsecutiveFailures` days in a row couldn't be read (offline,
        /// or the route changed): stopped rather than failing all 90 quietly.
        case unavailable(copiedSoFar: Int)
    }

    /// Days in a row that may fail before the run gives up.
    public static let maxConsecutiveFailures = 5

    // MARK: - Pure mapping

    /// The local entries for one Garmin day log. Entries whose meal this app
    /// doesn't know are skipped (they would have nowhere to show).
    public static func localEntries(from log: DailyFoodLog, day: String, calendar: Calendar = .current) -> [LocalLogEntry] {
        var result: [LocalLogEntry] = []
        for detail in log.mealDetails ?? [] {
            guard let name = detail.meal?.mealName, let mealType = MealType(rawValue: name) else { continue }
            for (index, food) in (detail.loggedFoods ?? []).enumerated() {
                result.append(localEntry(from: food, day: day, mealType: mealType, index: index, calendar: calendar))
            }
        }
        return result
    }

    static func localEntry(from food: LoggedFood, day: String, mealType: MealType, index: Int, calendar: Calendar) -> LocalLogEntry {
        let quantity = food.servingQty.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? 1
        let content = food.nutritionContent
        let meta = food.foodMetaData
        var nutrients: [String: Double] = [:]
        func put(_ kind: NutrientKind, _ perServing: Double?) {
            guard let perServing, perServing.isFinite else { return }
            nutrients[kind.rawValue] = perServing * quantity
        }
        put(.calories, content?.calories)
        put(.carbs, content?.carbs)
        put(.protein, content?.protein)
        put(.fat, content?.fat)
        put(.fiber, content?.fiber)
        put(.sugar, content?.sugar)
        put(.saturatedFat, content?.saturatedFat)
        put(.sodium, content?.sodium)

        let source = GarminFoodSource(readBackSource: meta?.source)
        let ref = LocalFoodRef(
            id: meta?.foodId ?? "",
            source: LocalLogEntryCoordinator.foodSource(source),
            name: meta?.foodName ?? String(localized: "Food from Garmin", bundle: .module, comment: "Name of an entry copied from Garmin Connect whose food name Garmin didn't send."),
            brandName: meta?.brandName,
            regionCode: meta?.regionCode,
            languageCode: meta?.languageCode
        )
        return LocalLogEntry(
            id: stableId(day: day, logId: food.logId, fallback: "\(mealType.rawValue)-\(index)-\(meta?.foodId ?? "")"),
            day: day,
            mealType: mealType,
            loggedAt: loggedAt(food.logTimestamp, day: day, calendar: calendar),
            food: ref,
            servingId: content?.servingId ?? "",
            servingUnit: content?.servingUnit,
            servingNumberOfUnits: content?.numberOfUnits,
            quantity: quantity,
            nutrients: nutrients
        )
    }

    /// A UUID derived from the day and Garmin's `logId` (or, without one,
    /// the entry's position), so a second copy recognises the first.
    static func stableId(day: String, logId: String?, fallback: String) -> UUID {
        let key = "garmin-history:" + day + ":" + ((logId?.isEmpty == false ? logId : nil) ?? fallback)
        var bytes = Array(SHA256.hash(data: Data(key.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50 // version 5 style (name-based)
        bytes[8] = (bytes[8] & 0x3F) | 0x80 // RFC 4122 variant
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    /// Garmin's timestamp when it parses, else noon of the day.
    static func loggedAt(_ timestamp: String?, day: String, calendar: Calendar) -> Date {
        if let timestamp {
            for format in ["yyyy-MM-dd'T'HH:mm:ss.SSS", "yyyy-MM-dd'T'HH:mm:ss"] {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.calendar = calendar
                formatter.timeZone = calendar.timeZone
                formatter.dateFormat = format
                if let date = formatter.date(from: timestamp) { return date }
            }
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let start = formatter.date(from: day) ?? Date(timeIntervalSince1970: 0)
        return calendar.date(byAdding: .hour, value: 12, to: start) ?? start
    }

    /// The `count` days ending with `today`, oldest first.
    public static func days(endingOn today: String, count: Int) -> [String] {
        guard count > 0, let start = SupplementDate.adding(-(count - 1), to: today) else { return [] }
        return SupplementDate.days(from: start, through: today)
    }

    // MARK: - Run

    /// Copies up to `days` days ending today. `progress` gets (done, total)
    /// after every day.
    public static func run(
        reader: any NutritionLogReading,
        store: LocalFoodLogStore,
        today: String,
        days count: Int = defaultDays,
        calendar: Calendar = .current,
        progress: @Sendable (Int, Int) async -> Void = { _, _ in }
    ) async throws -> Result {
        let days = days(endingOn: today, count: count)
        var result = Result()
        var consecutiveFailures = 0
        let existing = Set((try? await store.entries(fromDay: days.first ?? today, toDay: today))?.map(\.id) ?? [])
        for (index, day) in days.enumerated() {
            let log: DailyFoodLog?
            do {
                log = try await reader.dailyFoodLog(date: day)
            } catch GarminClientError.unauthorized {
                throw ImportError.signInNeeded(copiedSoFar: result.entriesCopied)
            } catch GarminClientError.rateLimited {
                throw ImportError.rateLimited(copiedSoFar: result.entriesCopied)
            } catch {
                result.failedDays += 1
                consecutiveFailures += 1
                if consecutiveFailures >= maxConsecutiveFailures {
                    throw ImportError.unavailable(copiedSoFar: result.entriesCopied)
                }
                await progress(index + 1, days.count)
                continue
            }
            consecutiveFailures = 0
            result.daysRead += 1
            if let log {
                let entries = localEntries(from: log, day: day, calendar: calendar)
                let fresh = entries.filter { !existing.contains($0.id) }
                result.alreadyOnPhone += entries.count - fresh.count
                if !fresh.isEmpty {
                    try await store.append(fresh)
                    result.entriesCopied += fresh.count
                }
            }
            await progress(index + 1, days.count)
        }
        return result
    }
}
