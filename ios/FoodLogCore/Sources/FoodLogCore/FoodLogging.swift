// FoodLogging.swift
//
// The write seam of add-standalone-mode (design D4): every food-log WRITE
// the app makes, as one protocol, so wave 2 can add a local system of
// record (`LocalLogEntryCoordinator`, writing `LocalFoodLogStore`) beside
// the Garmin one without touching a single view or intent.
//
// The surface is exactly `LogEntryCoordinator`'s public API as it stood
// before this change, plus `deleteCommitted(logId:date:)` -- the `.synced`
// delete that used to sit inline in `DayLogLoader.delete` (a direct
// `GarminClient.deleteFoodLogEntries` call). `LogEntryCoordinator` conforms
// with its bodies unchanged.
//
// Protocol requirements can't carry default arguments, so callers never
// hold `any FoodLogging` for the defaulted calls: they hold
// `ModeRoutingFoodLogging` (below), whose methods repeat
// `LogEntryCoordinator`'s exact signatures INCLUDING the defaults, and which
// forwards everything with every argument spelled out. That keeps every
// existing call site (views, `AppEnvironment`, Siri/Control intents)
// compiling unchanged, with no protocol-extension overloads that could make
// a concrete `LogEntryCoordinator` call ambiguous.
//
// Wave 2 (task 2.5): `LocalLogEntryCoordinator` is the second
// implementation, and the router picks it on every call while the
// effective `DataMode` is `.standalone` (only reachable through the hidden
// testing toggle until onboarding exists). Garmin mode forwards exactly as
// in wave 1.
//
// Depended on by: Shared/AppServices.swift (holds the one router per
// process as `logEntryCoordinator`), GarminFood/Today/DayLogLoader.swift
// (deletes), and every confirm/edit/duplicate/copy caller through
// `AppServices`/`AppEnvironment`.

import Foundation
import GarminKit

/// Every food-log write. `LogEntryCoordinator` (Garmin, via the outbox) and
/// `LocalLogEntryCoordinator` (standalone, the local food log).
public protocol FoodLogging: Sendable {
    @discardableResult
    func confirm(
        food: Food,
        serving: Serving,
        numberOfUnits: Double,
        mealType: MealType,
        date: String,
        now: Date,
        regionCode: String?,
        languageCode: String?
    ) async throws -> OutboxEntry

    @discardableResult
    func confirmCustomFood(
        _ customFood: CustomFoodDraft,
        quantity: Double,
        mealType: MealType,
        date: String,
        now: Date,
        regionCode: String?,
        languageCode: String?
    ) async throws -> (entry: OutboxEntry, discrepancyNote: String)

    @discardableResult
    func confirmMealPreset(
        _ preset: MealPreset,
        servingsMultiplier: Double,
        mealType: MealType,
        date: String,
        now: Date,
        regionCode: String?,
        languageCode: String?
    ) async throws -> [OutboxEntry]

    @discardableResult
    func edit(
        _ entry: MealEntry,
        date: String,
        newQuantity: Double,
        newMeal: MealType,
        now: Date,
        regionCode: String?,
        languageCode: String?
    ) async throws -> OutboxEntry

    @discardableResult
    func duplicate(
        _ entry: MealEntry,
        date: String,
        now: Date,
        regionCode: String?,
        languageCode: String?
    ) async throws -> OutboxEntry

    @discardableResult
    func copyMeal(
        _ items: [CopyableMealItem],
        to mealType: MealType,
        date: String,
        now: Date,
        regionCode: String?,
        languageCode: String?
    ) async throws -> [OutboxEntry]

    /// A row not yet in the system of record (`.syncing`/`.failed`).
    func deletePending(outboxId: UUID) async throws -> LogEntryCoordinator.PendingDeletion

    /// A row already in the system of record (`MealEntry.status ==
    /// .synced(logId:)`). For Garmin: `DELETE /nutrition-service/food/logs/
    /// {date}` -- the route `DayLogLoader.delete` has always called.
    func deleteCommitted(logId: String, date: String) async throws
}

extension LogEntryCoordinator: FoodLogging {}

/// Thrown by `LogEntryCoordinator.deleteCommitted` when it was built
/// without a Garmin log to delete from (tests, previews). The app's
/// coordinator always has one (`AppServices`).
public enum CommittedDeleteError: Error, Sendable, Equatable {
    case noSystemOfRecord
}

/// Held by `AppServices` as the one `logEntryCoordinator` per process.
/// Design D4: forwards each call to the implementation for the current
/// `DataMode`, read on every call (`mode`), so flipping the mode needs no
/// relaunch. Built without `local` (wave 1's shape, and tests) it always
/// forwards to Garmin.
public struct ModeRoutingFoodLogging: FoodLogging {
    private let garmin: any FoodLogging
    private let local: (any FoodLogging)?
    private let mode: @Sendable () -> DataMode

    public init(
        garmin: any FoodLogging,
        local: (any FoodLogging)? = nil,
        mode: @escaping @Sendable () -> DataMode = { .garminConnected }
    ) {
        self.garmin = garmin
        self.local = local
        self.mode = mode
    }

    /// The implementation for the current data mode.
    private var current: any FoodLogging {
        if let local, mode() == .standalone { return local }
        return garmin
    }

    @discardableResult
    public func confirm(
        food: Food,
        serving: Serving,
        numberOfUnits: Double,
        mealType: MealType,
        date: String,
        now: Date = Date(),
        regionCode: String? = nil,
        languageCode: String? = nil
    ) async throws -> OutboxEntry {
        try await current.confirm(
            food: food,
            serving: serving,
            numberOfUnits: numberOfUnits,
            mealType: mealType,
            date: date,
            now: now,
            regionCode: regionCode,
            languageCode: languageCode
        )
    }

    @discardableResult
    public func confirmCustomFood(
        _ customFood: CustomFoodDraft,
        quantity: Double,
        mealType: MealType,
        date: String,
        now: Date = Date(),
        regionCode: String? = nil,
        languageCode: String? = nil
    ) async throws -> (entry: OutboxEntry, discrepancyNote: String) {
        try await current.confirmCustomFood(
            customFood,
            quantity: quantity,
            mealType: mealType,
            date: date,
            now: now,
            regionCode: regionCode,
            languageCode: languageCode
        )
    }

    @discardableResult
    public func confirmMealPreset(
        _ preset: MealPreset,
        servingsMultiplier: Double = 1,
        mealType: MealType,
        date: String,
        now: Date = Date(),
        regionCode: String? = nil,
        languageCode: String? = nil
    ) async throws -> [OutboxEntry] {
        try await current.confirmMealPreset(
            preset,
            servingsMultiplier: servingsMultiplier,
            mealType: mealType,
            date: date,
            now: now,
            regionCode: regionCode,
            languageCode: languageCode
        )
    }

    @discardableResult
    public func edit(
        _ entry: MealEntry,
        date: String,
        newQuantity: Double,
        newMeal: MealType,
        now: Date = Date(),
        regionCode: String? = nil,
        languageCode: String? = nil
    ) async throws -> OutboxEntry {
        try await current.edit(
            entry,
            date: date,
            newQuantity: newQuantity,
            newMeal: newMeal,
            now: now,
            regionCode: regionCode,
            languageCode: languageCode
        )
    }

    @discardableResult
    public func duplicate(
        _ entry: MealEntry,
        date: String,
        now: Date = Date(),
        regionCode: String? = nil,
        languageCode: String? = nil
    ) async throws -> OutboxEntry {
        try await current.duplicate(
            entry,
            date: date,
            now: now,
            regionCode: regionCode,
            languageCode: languageCode
        )
    }

    @discardableResult
    public func copyMeal(
        _ items: [CopyableMealItem],
        to mealType: MealType,
        date: String,
        now: Date = Date(),
        regionCode: String? = nil,
        languageCode: String? = nil
    ) async throws -> [OutboxEntry] {
        try await current.copyMeal(
            items,
            to: mealType,
            date: date,
            now: now,
            regionCode: regionCode,
            languageCode: languageCode
        )
    }

    /// Always the Garmin coordinator, in either mode: a pending row is an
    /// OUTBOX entry (the local log has no pending state), and cancelling it
    /// is a local outbox write -- no network. In standalone mode that only
    /// happens for an entry queued before the mode was switched.
    public func deletePending(outboxId: UUID) async throws -> LogEntryCoordinator.PendingDeletion {
        try await garmin.deletePending(outboxId: outboxId)
    }

    public func deleteCommitted(logId: String, date: String) async throws {
        try await current.deleteCommitted(logId: logId, date: date)
    }
}
