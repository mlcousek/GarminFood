// LogEntryCoordinator.swift
//
// The confirm-and-commit action (tasks 16.1-16.2; food-log-entry spec's
// three core requirements: commits without waiting on the network, hands
// off to sync in the same action, and updates local usage ranking in the
// same action).
//
// Zero-network-wait is structural here, not a promise kept by discipline:
// `Outbox.logFood` (GarminKit) only appends to a local JSON file and
// returns -- it does not make an HTTP request. This coordinator calls
// nothing else that touches the network either. Delivery happens later,
// whenever something drains the outbox (GarminKit's `Outbox.drain`,
// triggered by the app layer on foreground/after this call, per
// add-garmin-auth-and-sync design.md's "the app drains its own... on
// foreground" -- NOT this coordinator's job, per this change's own
// non-goal: "Delivering the entry to Garmin. Owned by
// add-garmin-auth-and-sync's garmin-sync capability").
//
// add-log-entry-editing adds `edit` (amount and/or meal), `duplicate` and
// `copyMeal`. They keep the same zero-network-wait shape: each only writes
// the local outbox. An edit of a Garmin entry is enqueued as a replace
// (GarminKit `Outbox`, design.md D1: create the corrected entry, then delete
// the old one, at drain time); an edit of an entry that never reached Garmin
// is a local swap of the queued entry. `foodCache` (optional) is fed the
// food being re-logged so the queued row can show its name and calories
// before Garmin reads it back.
//
// Every path here checks its quantity against `LogQuantity.isValid`
// (finite, > 0, <= 10 000) BEFORE writing anything, so an absurd typed
// amount is refused with an error the screen shows instead of being queued
// (LogQuantity.swift's header has the crash this prevented).

import Foundation
import GarminKit

public struct LogEntryCoordinator: Sendable {
    private let outbox: Outbox
    private let usageHistory: UsageHistoryStore
    private let servingDefaults: ServingDefaultStore
    private let foodCache: FoodCacheStore?

    public init(
        outbox: Outbox,
        usageHistory: UsageHistoryStore = UsageHistoryStore(),
        servingDefaults: ServingDefaultStore = ServingDefaultStore(),
        foodCache: FoodCacheStore? = nil
    ) {
        self.outbox = outbox
        self.usageHistory = usageHistory
        self.servingDefaults = servingDefaults
        self.foodCache = foodCache
    }

    /// Confirms a catalog (Garmin-search-backed) food. Returns as soon as
    /// the entry is durably enqueued -- callers may show success
    /// immediately, per the spec. Throws `LogQuantityError.outOfRange`,
    /// enqueueing nothing, for a quantity outside `LogQuantity.isValid`.
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
        let entry = try await outbox.logFood(
            date: date,
            mealType: mealType,
            foodId: food.id,
            servingId: serving.id,
            numberOfUnits: numberOfUnits,
            source: food.source.garminFoodSource,
            // The food's own region/language (as Garmin reported it) is the
            // exact tuple a custom food's nutrition is stored under, so it
            // wins; the caller's account-wide values are only a fallback.
            regionCode: food.regionCode ?? regionCode,
            languageCode: food.languageCode ?? languageCode,
            createdAt: now
        )
        // Best-effort: a failure recording usage/defaults must never undo an
        // already-committed, already-enqueued entry -- the entry existing is
        // the durability guarantee the spec cares about, not this
        // bookkeeping.
        try? await usageHistory.record(foodId: food.id, servingId: serving.id, numberOfUnits: numberOfUnits, timestamp: now, nutritionDay: date, mealType: mealType)
        try? await servingDefaults.setDefault(foodId: food.id, servingId: serving.id, numberOfUnits: numberOfUnits, updatedAt: now)
        return entry
    }

    /// Confirms a custom food (design.md D4's fallback path): the entry
    /// actually sent to Garmin is the custom food's declared backing
    /// food/serving, scaled by `quantity`; usage history is recorded
    /// against the CUSTOM food's own id so quick-pick/serving-memory
    /// reflect what the user actually picked (matching D1's "independent of
    /// Garmin's own view" framing), not the Garmin food it happens to map
    /// to server-side. Returns the discrepancy note the caller must show
    /// per the food-catalog spec's "shown to the user" requirement.
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
        let target = customFood.resolvedLoggingTarget(quantity: quantity)
        // The backing amount is the quantity times the custom food's own
        // multiplier, which may legitimately be large (a "1 g" backing
        // serving); it only has to be a real, positive number.
        guard target.numberOfUnits.isFinite, target.numberOfUnits > 0 else { throw LogQuantityError.outOfRange }
        // No `source`: a custom food only records its backing food's id, so
        // the namespace is inferred from that id's shape at delivery.
        let entry = try await outbox.logFood(
            date: date,
            mealType: mealType,
            foodId: target.foodId,
            servingId: target.servingId,
            numberOfUnits: target.numberOfUnits,
            regionCode: customFood.backingRegionCode ?? regionCode,
            languageCode: customFood.backingLanguageCode ?? languageCode,
            createdAt: now
        )
        try? await usageHistory.record(
            foodId: customFood.id.uuidString,
            servingId: CustomFoodDraft.servingId,
            numberOfUnits: quantity,
            timestamp: now,
            nutritionDay: date,
            mealType: mealType
        )
        return (entry, customFood.discrepancyNote)
    }

    /// Confirms every ingredient of a meal preset as its own outbox entry,
    /// all sharing the same meal type, date, and timestamp -- see
    /// MealPreset.swift's header for why this is N separate entries rather
    /// than one aggregated custom food. Built entirely on top of `confirm`/
    /// `confirmCustomFood` above, unchanged, so a preset ingredient is
    /// indistinguishable -- to Garmin, to usage history, to quick-pick
    /// ranking -- from that same food logged on its own.
    ///
    /// `servingsMultiplier` scales every ingredient's own preset quantity
    /// together, e.g. `0.5` to log half the preset as composed (a smaller
    /// portion of the same recipe, not a different recipe).
    ///
    /// Not transactional: each ingredient is its own durable local commit
    /// (`Outbox.logFood` only ever appends to a file), so if one throws
    /// partway through, every ingredient before it is already committed and
    /// stays that way -- undoing them to fake atomicity would throw away
    /// real, already-durable entries over an unrelated failure. Rethrows
    /// immediately on the first failure, same as every other method here;
    /// the caller can tell a partial log happened by comparing how many
    /// entries came back (when it doesn't throw) or simply that it threw at
    /// all against `preset.ingredients.count`.
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
        // Checked for every ingredient up front: this path isn't
        // transactional (see above), so finding a bad quantity halfway
        // through would leave the ingredients before it already logged.
        let allValid = preset.ingredients.allSatisfy { ingredient in
            let quantity = ingredient.quantity * servingsMultiplier
            guard LogQuantity.isValid(quantity) else { return false }
            guard let draft = ingredient.customFoodDraft else { return true }
            let backing = draft.resolvedLoggingTarget(quantity: quantity).numberOfUnits
            return backing.isFinite && backing > 0
        }
        guard allValid else { throw LogQuantityError.outOfRange }
        var entries: [OutboxEntry] = []
        entries.reserveCapacity(preset.ingredients.count)
        for ingredient in preset.ingredients {
            let quantity = ingredient.quantity * servingsMultiplier
            if let customFoodDraft = ingredient.customFoodDraft {
                let (entry, _) = try await confirmCustomFood(customFoodDraft, quantity: quantity, mealType: mealType, date: date, now: now, regionCode: regionCode, languageCode: languageCode)
                entries.append(entry)
            } else {
                let entry = try await confirm(food: ingredient.food, serving: ingredient.serving, numberOfUnits: quantity, mealType: mealType, date: date, now: now, regionCode: regionCode, languageCode: languageCode)
                entries.append(entry)
            }
        }
        return entries
    }

    // MARK: - add-log-entry-editing

    /// Changes a logged entry's amount and/or meal (the owner's pick of
    /// editable fields; serving and day are not editable). Returns as soon
    /// as the change is durably queued -- the dashboard shows it at once
    /// (design.md D3).
    ///
    /// - A synced entry becomes a replace: a new entry carrying
    ///   `replaces: (date, logId)`, delivered by `Outbox.drain` as create,
    ///   then delete the old one (D1).
    /// - A still-queued entry (`.syncing`/`.failed` status, not yet accepted
    ///   by Garmin) is swapped in place; any replace it already carried is
    ///   kept, so editing an edit still removes the original Garmin entry.
    ///   One Garmin HAS accepted but that hasn't been read back throws
    ///   `.stillSyncing`: its Garmin id isn't known yet.
    ///
    /// Not recorded in usage history -- an edit isn't another thing eaten,
    /// and would otherwise count toward streaks and XP. The remembered
    /// serving amount is updated.
    ///
    /// `date` is the day the entry is on (`yyyy-MM-dd`); `regionCode`/
    /// `languageCode` are the account-wide fallbacks, used only when the
    /// entry doesn't carry its own.
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
        guard entry.canRelog, let servingId = entry.servingId, let currentMeal = entry.mealType else {
            throw LogEntryEditError.notEditable
        }
        guard abs(newQuantity - entry.servingQty) > Self.quantityTolerance || newMeal != currentMeal else {
            throw LogEntryEditError.noChange
        }

        let result: OutboxEntry
        switch entry.status {
        case .synced(let logId):
            guard !logId.isEmpty else { throw LogEntryEditError.notEditable }
            result = try await outbox.logFood(
                date: date,
                mealType: newMeal,
                foodId: entry.foodId,
                servingId: servingId,
                numberOfUnits: newQuantity,
                source: entry.source,
                regionCode: entry.regionCode ?? regionCode,
                languageCode: entry.languageCode ?? languageCode,
                replaces: ReplacedLog(date: date, logId: logId),
                createdAt: now
            )
        case .syncing(let outboxId), .failed(let outboxId, _):
            do {
                result = try await outbox.replaceQueued(id: outboxId, mealType: newMeal, numberOfUnits: newQuantity, createdAt: now)
            } catch let error as OutboxEditError {
                throw Self.editError(for: error)
            }
        }

        await cacheForDisplay(
            foodId: entry.foodId, name: entry.name, brandName: entry.brandName, source: entry.source,
            serving: entry.serving, regionCode: entry.regionCode, languageCode: entry.languageCode
        )
        try? await servingDefaults.setDefault(foodId: entry.foodId, servingId: servingId, numberOfUnits: newQuantity, updatedAt: now)
        return result
    }

    /// Logs the same food, serving and quantity again into the same meal
    /// ("second coffee"). An ordinary add; for a synced source it records
    /// `duplicateOf` so Reconciliation never mistakes the source for this
    /// entry's own delivery (design.md D2).
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
        let result = try await outbox.logFood(
            date: date,
            mealType: mealType,
            foodId: entry.foodId,
            servingId: servingId,
            numberOfUnits: entry.servingQty,
            source: entry.source,
            regionCode: entry.regionCode ?? regionCode,
            languageCode: entry.languageCode ?? languageCode,
            duplicateOf: entry.syncedLogId,
            createdAt: now
        )
        await cacheForDisplay(
            foodId: entry.foodId, name: entry.name, brandName: entry.brandName, source: entry.source,
            serving: entry.serving, regionCode: entry.regionCode, languageCode: entry.languageCode
        )
        try? await usageHistory.record(foodId: entry.foodId, servingId: servingId, numberOfUnits: entry.servingQty, timestamp: now, nutritionDay: date, mealType: mealType)
        return result
    }

    /// Logs every item (from `CopyMealPlanner.plan`, already filtered to
    /// what the user kept checked) into `mealType` on `date`, each as an
    /// ordinary add with its original serving and quantity (design.md D4).
    ///
    /// Not transactional, same as `confirmMealPreset`: each item is its own
    /// durable commit, so a failure partway leaves the earlier ones logged
    /// and rethrows.
    @discardableResult
    public func copyMeal(
        _ items: [CopyableMealItem],
        to mealType: MealType,
        date: String,
        now: Date = Date(),
        regionCode: String? = nil,
        languageCode: String? = nil
    ) async throws -> [OutboxEntry] {
        var entries: [OutboxEntry] = []
        entries.reserveCapacity(items.count)
        for item in items {
            guard LogQuantity.isValid(item.servingQty) else { continue }
            let entry = try await outbox.logFood(
                date: date,
                mealType: mealType,
                foodId: item.foodId,
                servingId: item.servingId,
                numberOfUnits: item.servingQty,
                source: item.source,
                regionCode: item.regionCode ?? regionCode,
                languageCode: item.languageCode ?? languageCode,
                createdAt: now
            )
            entries.append(entry)
            await cacheForDisplay(
                foodId: item.foodId, name: item.name, brandName: item.brandName, source: item.source,
                serving: item.serving, regionCode: item.regionCode, languageCode: item.languageCode
            )
            try? await usageHistory.record(foodId: item.foodId, servingId: item.servingId, numberOfUnits: item.servingQty, timestamp: now, nutritionDay: date, mealType: mealType)
        }
        return entries
    }

    /// Below this, two quantities are the same amount.
    static let quantityTolerance = 0.0001

    static func editError(for error: OutboxEditError) -> LogEntryEditError {
        switch error {
        case .entryNotFound:
            return .entryGone
        case .entryInFlight, .alreadyDelivered:
            return .stillSyncing
        }
    }

    /// Best-effort: lets the queued row show a name and calories before
    /// Garmin reads it back (`MealDashboard.pendingEntry` looks foods up in
    /// this cache). Never overwrites a food already cached from a search --
    /// at most adds the missing serving to it.
    private func cacheForDisplay(
        foodId: String,
        name: String,
        brandName: String?,
        source: GarminFoodSource?,
        serving: Serving?,
        regionCode: String?,
        languageCode: String?
    ) async {
        guard let foodCache, let serving else { return }
        if let existing = await foodCache.food(forId: foodId) {
            guard !existing.servings.contains(where: { $0.id == serving.id }) else { return }
            await foodCache.upsert([Food(
                id: existing.id,
                name: existing.name,
                brandName: existing.brandName,
                source: existing.source,
                servings: existing.servings + [serving],
                imageURL: existing.imageURL,
                garminIsFavorite: existing.garminIsFavorite,
                garminIsRecent: existing.garminIsRecent,
                regionCode: existing.regionCode,
                languageCode: existing.languageCode
            )])
        } else {
            await foodCache.upsert([Food(
                id: foodId,
                name: name,
                brandName: brandName,
                source: source == .fatSecret ? .fatSecret : .garmin,
                servings: [serving],
                regionCode: regionCode,
                languageCode: languageCode
            )])
        }
    }
}

extension FoodSource {
    /// The namespace to name on the Garmin write, where this food states it
    /// reliably. Only `.fatSecret` does: `FoodSource(garminSourceString:)`
    /// also produces `.garmin` for a MISSING or unrecognised source string,
    /// so `.garmin` can't be trusted to mean a Garmin id -- and naming the
    /// wrong namespace is a 400. Everything else is left to inference from
    /// the id's shape, which is right for both namespaces.
    var garminFoodSource: GarminFoodSource? {
        switch self {
        case .fatSecret:
            return .fatSecret
        case .garmin, .custom, .openFoodFacts:
            return nil
        }
    }
}
