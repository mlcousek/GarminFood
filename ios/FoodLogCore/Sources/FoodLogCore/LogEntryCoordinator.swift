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
        now: Date = Date()
    ) async throws -> OutboxEntry {
        let entry = try await outbox.logFood(
            date: date,
            mealType: mealType,
            foodId: food.id,
            servingId: serving.id,
            numberOfUnits: numberOfUnits
        )
        // Best-effort: a failure recording usage/defaults must never undo an
        // already-committed, already-enqueued entry -- the entry existing is
        // the durability guarantee the spec cares about, not this
        // bookkeeping.
        try? await usageHistory.record(foodId: food.id, servingId: serving.id, numberOfUnits: numberOfUnits, timestamp: now)
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
        now: Date = Date()
    ) async throws -> (entry: OutboxEntry, discrepancyNote: String) {
        let target = customFood.resolvedLoggingTarget(quantity: quantity)
        let entry = try await outbox.logFood(
            date: date,
            mealType: mealType,
            foodId: target.foodId,
            servingId: target.servingId,
            numberOfUnits: target.numberOfUnits
        )
        try? await usageHistory.record(
            foodId: customFood.id.uuidString,
            servingId: CustomFoodDraft.servingId,
            numberOfUnits: quantity,
            timestamp: now
        )
        return (entry, customFood.discrepancyNote)
    }
}
