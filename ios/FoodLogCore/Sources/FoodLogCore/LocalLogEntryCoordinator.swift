// LocalLogEntryCoordinator.swift
//
// Standalone mode's implementation of every food-log write
// (add-standalone-mode D4, task 2.2): the same `FoodLogging` surface as the
// Garmin `LogEntryCoordinator`, but committing to `LocalFoodLogStore` -- the
// system of record for an install with no Garmin account. There is no
// outbox, no drain and no "syncing" state: the local write IS the durable
// write, so every confirm returns as soon as one JSON file is replaced, and
// nothing here touches the network (the zero-network-wait rule holds
// structurally, as it does for the outbox).
//
// What must match Garmin mode exactly -- the bookkeeping other features
// read regardless of mode, so quick picks, remembered servings, streaks,
// XP and "Log again" behave the same:
//   - usage history: recorded on confirm, custom-food confirm, every preset
//     ingredient, duplicate and copy; NOT on edit (an edit isn't another
//     thing eaten). Same ids: a custom food under its own UUID and
//     `CustomFoodDraft.servingId`.
//   - serving defaults: set on catalog confirm (incl. preset catalog
//     ingredients) and on edit; not on custom-food confirm or duplicate.
//   - food cache: `FoodCacheStore.cacheForDisplay`, the one shared rule, on
//     edit, duplicate and copy.
// `LocalLogEntryCoordinatorTests` runs both coordinators side by side and
// compares the three stores.
//
// What deliberately differs:
//   - Nutrients are snapshotted at confirm (serving x quantity); a custom
//     food logs its OWN macros, never a backing Garmin food's (it has no
//     Garmin to log to). The discrepancy note is therefore empty.
//   - An edit changes the entry in place (amount rescaled by the quantity
//     ratio, meal moved), instead of Garmin's create-then-delete replace.
//   - A preset or a copy is ONE atomic write of all its entries, not N
//     separate commits: the local store can offer that, so a failure can't
//     leave half a meal logged.
//   - The `OutboxEntry` values returned are receipts only (the protocol is
//     `LogEntryCoordinator`'s exact shape, design D4, and no caller reads
//     more than "it didn't throw"): `id` is the local entry's id, `state`
//     `.sent` because it is already in the system of record. They are never
//     enqueued anywhere.
//
// Local entries reach the dashboard as `MealEntry.Status.synced(logId:)`
// with `logId == entry.id.uuidString` (`LocalNutritionReader`): "synced"
// already means "present in the system of record" (design D4), which is
// how `edit`/`duplicate`/`deleteCommitted` find them again.
//
// Depends on: LocalFoodLogStore, UsageHistoryStore, ServingDefaultStore,
// FoodCacheStore. Depended on by: ModeRoutingFoodLogging (AppServices).

import Foundation
import GarminKit

public struct LocalLogEntryCoordinator: FoodLogging {
    private let store: LocalFoodLogStore
    private let usageHistory: UsageHistoryStore
    private let servingDefaults: ServingDefaultStore
    private let foodCache: FoodCacheStore?

    public init(
        store: LocalFoodLogStore,
        usageHistory: UsageHistoryStore = UsageHistoryStore(),
        servingDefaults: ServingDefaultStore = ServingDefaultStore(),
        foodCache: FoodCacheStore? = nil
    ) {
        self.store = store
        self.usageHistory = usageHistory
        self.servingDefaults = servingDefaults
        self.foodCache = foodCache
    }

    // MARK: - Confirm

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
        guard LogQuantity.isValid(numberOfUnits) else { throw LogQuantityError.outOfRange }
        let entry = catalogEntry(food: food, serving: serving, quantity: numberOfUnits, mealType: mealType, date: date, now: now, regionCode: regionCode, languageCode: languageCode, presetId: nil)
        try await store.append([entry])
        await recordCatalogUsage(entry, now: now)
        return Self.receipt(for: entry, now: now)
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
        guard LogQuantity.isValid(quantity) else { throw LogQuantityError.outOfRange }
        let entry = customEntry(customFood, quantity: quantity, mealType: mealType, date: date, now: now, presetId: nil)
        try await store.append([entry])
        await recordCustomUsage(entry, now: now)
        // No note: the custom food is logged as itself, with its own macros.
        return (Self.receipt(for: entry, now: now), "")
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
        // Every ingredient checked first, like the Garmin coordinator --
        // there only the backing amount is extra, which doesn't exist here.
        let allValid = preset.ingredients.allSatisfy { LogQuantity.isValid($0.quantity * servingsMultiplier) }
        guard allValid else { throw LogQuantityError.outOfRange }

        let entries = preset.ingredients.map { ingredient -> LocalLogEntry in
            let quantity = ingredient.quantity * servingsMultiplier
            if let draft = ingredient.customFoodDraft {
                return customEntry(draft, quantity: quantity, mealType: mealType, date: date, now: now, presetId: preset.id)
            }
            return catalogEntry(food: ingredient.food, serving: ingredient.serving, quantity: quantity, mealType: mealType, date: date, now: now, regionCode: regionCode, languageCode: languageCode, presetId: preset.id)
        }
        try await store.append(entries)
        for entry in entries {
            if entry.customFoodId != nil {
                await recordCustomUsage(entry, now: now)
            } else {
                await recordCatalogUsage(entry, now: now)
            }
        }
        return entries.map { Self.receipt(for: $0, now: now) }
    }

    // MARK: - Edit, duplicate, copy

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
        guard LogQuantity.isValid(newQuantity) else { throw LogEntryEditError.invalidQuantity }
        guard entry.canRelog, let servingId = entry.servingId else { throw LogEntryEditError.notEditable }
        var stored = try await storedEntry(for: entry, date: date)
        guard abs(newQuantity - stored.quantity) > LogEntryCoordinator.quantityTolerance || newMeal != stored.mealType else {
            throw LogEntryEditError.noChange
        }
        guard let rescaled = stored.nutrients(rescaledTo: newQuantity) else { throw LogEntryEditError.notEditable }

        stored.quantity = newQuantity
        stored.nutrients = rescaled
        stored.mealType = newMeal
        stored.editedAt = now
        do {
            try await store.update(stored)
        } catch LocalFoodLogError.entryNotFound {
            throw LogEntryEditError.entryGone
        }

        await cacheForDisplay(entry: entry, source: stored.food.source)
        try? await servingDefaults.setDefault(foodId: entry.foodId, servingId: servingId, numberOfUnits: newQuantity, updatedAt: now)
        return Self.receipt(for: stored, now: now)
    }

    @discardableResult
    public func duplicate(
        _ entry: MealEntry,
        date: String,
        now: Date = Date(),
        regionCode: String? = nil,
        languageCode: String? = nil
    ) async throws -> OutboxEntry {
        guard entry.canRelog, let servingId = entry.servingId, let mealType = entry.mealType else {
            throw LogEntryEditError.notEditable
        }
        guard LogQuantity.isValid(entry.servingQty) else { throw LogEntryEditError.invalidQuantity }
        let source = try await storedEntry(for: entry, date: date)
        let copy = LocalLogEntry(
            day: date,
            mealType: mealType,
            loggedAt: now,
            food: source.food,
            servingId: source.servingId,
            servingUnit: source.servingUnit,
            servingNumberOfUnits: source.servingNumberOfUnits,
            servingLabel: source.servingLabel,
            quantity: source.quantity,
            nutrients: source.nutrients,
            customFoodId: source.customFoodId,
            presetId: nil
        )
        try await store.append([copy])

        await cacheForDisplay(entry: entry, source: source.food.source)
        try? await usageHistory.record(foodId: entry.foodId, servingId: servingId, numberOfUnits: entry.servingQty, timestamp: now, nutritionDay: date, mealType: mealType)
        return Self.receipt(for: copy, now: now)
    }

    /// Each item is logged as it was (the source entry's own snapshot when
    /// it is still in the local log -- every nutrient, not just the few a
    /// read-back row carries -- otherwise the item's serving x quantity).
    @discardableResult
    public func copyMeal(
        _ items: [CopyableMealItem],
        to mealType: MealType,
        date: String,
        now: Date = Date(),
        regionCode: String? = nil,
        languageCode: String? = nil
    ) async throws -> [OutboxEntry] {
        let valid = items.filter { LogQuantity.isValid($0.servingQty) }
        var entries: [LocalLogEntry] = []
        entries.reserveCapacity(valid.count)
        for item in valid {
            var original: LocalLogEntry?
            if let sourceId = UUID(uuidString: item.id) {
                original = await store.entry(id: sourceId)
            }
            entries.append(copiedEntry(item, original: original, mealType: mealType, date: date, now: now, regionCode: regionCode, languageCode: languageCode))
        }
        try await store.append(entries)

        for (item, entry) in zip(valid, entries) {
            await foodCache?.cacheForDisplay(
                foodId: item.foodId, name: item.name, brandName: item.brandName,
                source: entry.food.source ?? Self.foodSource(item.source),
                serving: item.serving, regionCode: item.regionCode, languageCode: item.languageCode
            )
            try? await usageHistory.record(foodId: item.foodId, servingId: item.servingId, numberOfUnits: item.servingQty, timestamp: now, nutritionDay: date, mealType: mealType)
        }
        return entries.map { Self.receipt(for: $0, now: now) }
    }

    // MARK: - Delete

    /// Nothing in the local log is ever pending: its rows are all
    /// `.synced`. A still-queued dashboard row is an OUTBOX entry (left over
    /// from Garmin mode), which `ModeRoutingFoodLogging` always sends to the
    /// Garmin coordinator. For completeness this removes a local entry
    /// that happens to carry this id, and otherwise reports it gone.
    public func deletePending(outboxId: UUID) async throws -> LogEntryCoordinator.PendingDeletion {
        guard let stored = await store.entry(id: outboxId) else { throw LogEntryEditError.entryGone }
        try await deleteStored(id: stored.id, day: stored.day)
        return .removed
    }

    /// Removes a local entry (`MealEntry.Status.synced(logId:)`, where the
    /// logId is the entry's UUID). No Garmin request, ever.
    public func deleteCommitted(logId: String, date: String) async throws {
        guard let id = UUID(uuidString: logId) else { throw LogEntryEditError.entryGone }
        try await deleteStored(id: id, day: date)
    }

    private func deleteStored(id: UUID, day: String) async throws {
        do {
            try await store.delete(id: id, day: day)
        } catch LocalFoodLogError.entryNotFound {
            throw LogEntryEditError.entryGone
        }
    }

    // MARK: - Building entries

    private func catalogEntry(
        food: Food,
        serving: Serving,
        quantity: Double,
        mealType: MealType,
        date: String,
        now: Date,
        regionCode: String?,
        languageCode: String?,
        presetId: UUID?
    ) -> LocalLogEntry {
        LocalLogEntry(
            day: date,
            mealType: mealType,
            loggedAt: now,
            food: LocalFoodRef(
                id: food.id,
                source: food.source,
                name: food.name,
                brandName: food.brandName,
                regionCode: food.regionCode ?? regionCode,
                languageCode: food.languageCode ?? languageCode
            ),
            serving: serving,
            quantity: quantity,
            presetId: presetId
        )
    }

    /// The custom food as itself: its own id, its own serving and macros.
    private func customEntry(
        _ customFood: CustomFoodDraft,
        quantity: Double,
        mealType: MealType,
        date: String,
        now: Date,
        presetId: UUID?
    ) -> LocalLogEntry {
        let food = customFood.asFood()
        let serving = food.servings.first ?? Serving(id: CustomFoodDraft.servingId, unit: customFood.servingUnit, numberOfUnits: customFood.numberOfUnits)
        return LocalLogEntry(
            day: date,
            mealType: mealType,
            loggedAt: now,
            food: LocalFoodRef(id: food.id, source: .custom, name: food.name, brandName: food.brandName),
            serving: serving,
            quantity: quantity,
            customFoodId: customFood.id,
            presetId: presetId
        )
    }

    private func copiedEntry(
        _ item: CopyableMealItem,
        original: LocalLogEntry?,
        mealType: MealType,
        date: String,
        now: Date,
        regionCode: String?,
        languageCode: String?
    ) -> LocalLogEntry {
        if let original, original.food.id == item.foodId, original.servingId == item.servingId,
           let nutrients = original.nutrients(rescaledTo: item.servingQty) {
            return LocalLogEntry(
                day: date,
                mealType: mealType,
                loggedAt: now,
                food: original.food,
                servingId: original.servingId,
                servingUnit: original.servingUnit,
                servingNumberOfUnits: original.servingNumberOfUnits,
                servingLabel: original.servingLabel,
                quantity: item.servingQty,
                nutrients: nutrients,
                customFoodId: original.customFoodId
            )
        }
        let food = LocalFoodRef(
            id: item.foodId,
            source: Self.foodSource(item.source),
            name: item.name,
            brandName: item.brandName,
            regionCode: item.regionCode ?? regionCode,
            languageCode: item.languageCode ?? languageCode
        )
        if let serving = item.serving {
            return LocalLogEntry(day: date, mealType: mealType, loggedAt: now, food: food, serving: serving, quantity: item.servingQty)
        }
        // No per-serving nutrition at all: keep what the row showed.
        var nutrients: [String: Double] = [:]
        if let calories = item.calories { nutrients[NutrientKind.calories.rawValue] = calories }
        return LocalLogEntry(
            day: date,
            mealType: mealType,
            loggedAt: now,
            food: food,
            servingId: item.servingId,
            servingLabel: item.servingDescription,
            quantity: item.servingQty,
            nutrients: nutrients
        )
    }

    /// The local entry a dashboard row stands for (`.synced(logId:)`).
    private func storedEntry(for entry: MealEntry, date: String) async throws -> LocalLogEntry {
        guard let logId = entry.syncedLogId, let id = UUID(uuidString: logId) else { throw LogEntryEditError.notEditable }
        guard let stored = try await store.entry(id: id, day: date) else { throw LogEntryEditError.entryGone }
        return stored
    }

    // MARK: - Side effects (identical to LogEntryCoordinator's)

    private func recordCatalogUsage(_ entry: LocalLogEntry, now: Date) async {
        // Best-effort, as in Garmin mode: bookkeeping must never undo an
        // entry that is already committed.
        try? await usageHistory.record(foodId: entry.food.id, servingId: entry.servingId, numberOfUnits: entry.quantity, timestamp: now, nutritionDay: entry.day, mealType: entry.mealType)
        try? await servingDefaults.setDefault(foodId: entry.food.id, servingId: entry.servingId, numberOfUnits: entry.quantity, updatedAt: now)
    }

    private func recordCustomUsage(_ entry: LocalLogEntry, now: Date) async {
        try? await usageHistory.record(foodId: entry.food.id, servingId: CustomFoodDraft.servingId, numberOfUnits: entry.quantity, timestamp: now, nutritionDay: entry.day, mealType: entry.mealType)
    }

    private func cacheForDisplay(entry: MealEntry, source: FoodSource?) async {
        await foodCache?.cacheForDisplay(
            foodId: entry.foodId, name: entry.name, brandName: entry.brandName,
            source: source ?? Self.foodSource(entry.source),
            serving: entry.serving, regionCode: entry.regionCode, languageCode: entry.languageCode
        )
    }

    /// Garmin's cache rule for a food it only knows by its read-back
    /// namespace (`LogEntryCoordinator.cacheForDisplay`).
    static func foodSource(_ source: GarminFoodSource?) -> FoodSource {
        source == .fatSecret ? .fatSecret : .garmin
    }

    static func receipt(for entry: LocalLogEntry, now: Date) -> OutboxEntry {
        OutboxEntry(
            id: entry.id,
            date: entry.day,
            mealType: entry.mealType,
            foodId: entry.food.id,
            servingId: entry.servingId,
            numberOfUnits: entry.quantity,
            state: .sent,
            createdAt: now,
            nextAttemptAt: now
        )
    }
}
