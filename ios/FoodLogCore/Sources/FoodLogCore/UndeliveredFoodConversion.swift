// UndeliveredFoodConversion.swift
//
// Switching Garmin -> standalone with food entries Garmin hasn't accepted
// yet (add-standalone-mode D10, task 5.4; data-mode spec "Keeping
// undelivered entries"). The user picks "Keep on this phone": each such
// outbox entry becomes a `LocalLogEntry` on its own day and meal and is
// cancelled in the outbox, so nothing is lost and nothing is sent later.
//
// Nutrients come from `FoodCacheStore` (the food the entry was logged
// from: serving x quantity); if the cache doesn't have that serving, the
// entry keeps its name and amount without nutrients rather than being
// dropped (design D10: "or calories only if the cache lacks them" -- the
// cache is the only place calories could come from, so without it there
// are none).
//
// Order per entry, for no silent loss: append the local copy FIRST, then
// cancel the outbox entry with the claim-guarded `Outbox.cancelQueued`.
// If the cancel is refused (a drain is sending it right now, or Garmin
// already accepted it) the local copy is removed again and the entry stays
// Garmin's -- it is counted as `leftInGarmin`, never duplicated.
//
// Only `.pending` and `.failed` entries are converted. `.sent` and
// `.createdAwaitingDelete` ones are already in Garmin.
//
// Depended on by: the app's DataModeSection (Settings) via AppEnvironment.
// Tests: UndeliveredFoodConversionTests.

import Foundation
import GarminKit

public enum UndeliveredFoodConversion {
    public struct Result: Sendable, Equatable {
        /// Converted into local entries and removed from the outbox.
        public let kept: Int
        /// Could not be taken back (in flight / delivered meanwhile).
        public let leftInGarmin: Int
    }

    /// Entries Garmin hasn't accepted (`.pending` / `.failed`).
    public static func undelivered(_ entries: [OutboxEntry]) -> [OutboxEntry] {
        entries.filter { $0.state == .pending || $0.state == .failed }
    }

    /// The local entry `entry` becomes. `food` is the cached food it was
    /// logged from, if any.
    public static func localEntry(for entry: OutboxEntry, food: Food?) -> LocalLogEntry {
        let ref = LocalFoodRef(
            id: food?.id ?? entry.foodId,
            source: food?.source ?? LocalLogEntryCoordinator.foodSource(entry.source),
            name: food?.name ?? String(localized: "Unknown food", bundle: .module, comment: "Name of a food entry kept on the phone whose food details are unknown (switching from Garmin to standalone mode)."),
            brandName: food?.brandName,
            regionCode: food?.regionCode ?? entry.regionCode,
            languageCode: food?.languageCode ?? entry.languageCode
        )
        if let serving = food?.servings.first(where: { $0.id == entry.servingId }) {
            return LocalLogEntry(
                day: entry.date,
                mealType: entry.mealType,
                loggedAt: entry.createdAt,
                food: ref,
                serving: serving,
                quantity: entry.numberOfUnits
            )
        }
        return LocalLogEntry(
            day: entry.date,
            mealType: entry.mealType,
            loggedAt: entry.createdAt,
            food: ref,
            servingId: entry.servingId,
            quantity: entry.numberOfUnits,
            nutrients: [:]
        )
    }

    /// "Keep on this phone": converts every undelivered food entry.
    /// Throws only if writing the local log fails (the outbox entry is then
    /// left untouched).
    public static func keepOnPhone(
        outbox: Outbox,
        localLog: LocalFoodLogStore,
        foodCache: FoodCacheStore
    ) async throws -> Result {
        let candidates = undelivered(await outbox.allEntries())
        var kept = 0
        var left = 0
        for entry in candidates {
            let local = localEntry(for: entry, food: await foodCache.food(forId: entry.foodId))
            try await localLog.append([local])
            do {
                try await outbox.cancelQueued(id: entry.id)
                kept += 1
            } catch {
                // In flight, delivered or gone meanwhile: Garmin has (or is
                // getting) it, so the local copy would be a duplicate.
                do {
                    _ = try await localLog.delete(id: local.id, day: local.day)
                } catch {
                    // Never silent (CLAUDE.md): the entry now exists in both
                    // places; say so, so it can be deleted by hand.
                    DiagnosticsLog.log(.error, category: "DataMode", "Couldn't remove the local copy of \(entry.id) on \(local.day) after Garmin kept it; it may show twice: \(error.localizedDescription)")
                }
                left += 1
            }
        }
        return Result(kept: kept, leftInGarmin: left)
    }
}
