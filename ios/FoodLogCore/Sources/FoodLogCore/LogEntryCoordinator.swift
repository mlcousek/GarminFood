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

import Foundation
import GarminKit

public struct LogEntryCoordinator: Sendable {
    private let outbox: Outbox
    private let usageHistory: UsageHistoryStore
    private let servingDefaults: ServingDefaultStore

    public init(
        outbox: Outbox,
        usageHistory: UsageHistoryStore = UsageHistoryStore(),
        servingDefaults: ServingDefaultStore = ServingDefaultStore()
    ) {
        self.outbox = outbox
        self.usageHistory = usageHistory
        self.servingDefaults = servingDefaults
    }

    /// Confirms a catalog (Garmin-search-backed) food. Returns as soon as
    /// the entry is durably enqueued -- callers may show success
    /// immediately, per the spec.
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
        let entry = try await outbox.logFood(
            date: date,
            mealType: mealType,
            foodId: food.id,
            servingId: serving.id,
            numberOfUnits: numberOfUnits,
            source: food.source.garminFoodSource,
            regionCode: regionCode,
            languageCode: languageCode,
            createdAt: now
        )
        // Best-effort: a failure recording usage/defaults must never undo an
        // already-committed, already-enqueued entry -- the entry existing is
        // the durability guarantee the spec cares about, not this
        // bookkeeping.
        try? await usageHistory.record(foodId: food.id, servingId: serving.id, numberOfUnits: numberOfUnits, timestamp: now, nutritionDay: date)
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
        let target = customFood.resolvedLoggingTarget(quantity: quantity)
        // No `source`: a custom food only records its backing food's id, so
        // the namespace is inferred from that id's shape at delivery.
        let entry = try await outbox.logFood(
            date: date,
            mealType: mealType,
            foodId: target.foodId,
            servingId: target.servingId,
            numberOfUnits: target.numberOfUnits,
            regionCode: regionCode,
            languageCode: languageCode,
            createdAt: now
        )
        try? await usageHistory.record(
            foodId: customFood.id.uuidString,
            servingId: CustomFoodDraft.servingId,
            numberOfUnits: quantity,
            timestamp: now,
            nutritionDay: date
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
