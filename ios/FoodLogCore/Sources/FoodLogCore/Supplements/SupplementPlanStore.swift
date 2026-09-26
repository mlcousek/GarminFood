// SupplementPlanStore.swift
//
// The user's stack -- products and their schedule histories
// (add-supplements D1/D2/D3, task 2.1). One small JSON file
// (`supplement-plan.json`), actor-isolated, with the package's store
// contract (SupplementStoreSupport.swift's header).
//
// Removing a product from the stack ends its schedule from a day
// (`removeFromStack`), keeping the product itself: past intake still needs
// its label for totals, adherence and stock history, and disabling the
// feature must keep every piece of data (D10). `deleteProduct` really
// deletes, for a product added by mistake.
//
// Local only: nothing here talks to Garmin (proposal non-goal).
//
// Depended on by: AppServices (one instance per process), the supplements
// screen and editors (wave 3), reminders (wave 4).
// Tests: SupplementStoresTests.

import Foundation
import GarminKit

public actor SupplementPlanStore {
    private let fileURL: URL
    private var current = SupplementPlan()
    private var loaded = false

    public init(fileURL: URL = SupplementPlanStore.defaultFileURL()) {
        self.fileURL = fileURL
    }

    public static func defaultFileURL() -> URL {
        FoodLogCoreStorage.directory().appendingPathComponent("supplement-plan.json")
    }

    // MARK: Reads

    /// The whole stack. Throws when the file exists but can't be read yet
    /// -- an honest "couldn't load", never an empty stack that isn't.
    public func plan() throws -> SupplementPlan {
        try readable()
    }

    // MARK: Writes

    /// Adds `product`, or replaces the product with the same id.
    public func upsertProduct(_ product: SupplementProduct) throws {
        var next = try loadedForWrite()
        if let index = next.products.firstIndex(where: { $0.id == product.id }) {
            next.products[index] = product
        } else {
            next.products.append(product)
        }
        try save(next)
    }

    /// Sets a product's schedule from `day` onward (design D3); `nil`
    /// stops planning it from that day. Earlier days keep their schedule.
    public func setSchedule(_ schedule: SupplementSchedule?, for productId: UUID, from day: String) throws {
        var next = try loadedForWrite()
        guard SupplementDate.ordinal(day) != nil else { throw SupplementStoreError.dayNotEditable(day) }
        next.setSchedule(schedule, for: productId, from: day)
        try save(next)
    }

    /// Takes a product out of the stack from `day` on, keeping the product
    /// and its history.
    public func removeFromStack(_ productId: UUID, from day: String) throws {
        try setSchedule(nil, for: productId, from: day)
    }

    /// Deletes a product and its schedule history for good.
    public func deleteProduct(_ productId: UUID) throws {
        var next = try loadedForWrite()
        next.products.removeAll { $0.id == productId }
        next.items.removeAll { $0.productId == productId }
        try save(next)
    }

    /// Sets a product's stock to `servingsOnHand` now, on `day`
    /// (`SupplementProduct.setStock`). `records`: that product's intake on
    /// or after `day`, so earlier ticks of the day aren't subtracted twice.
    public func setStock(of productId: UUID, servingsOnHand: Double, on day: String, records: [IntakeRecord]) throws {
        try mutateProduct(productId) { $0.setStock(servingsOnHand: servingsOnHand, on: day, records: records) }
    }

    /// Adds full packs to what is left (`SupplementProduct.refill`).
    public func refill(_ productId: UUID, packs: Double = 1, on day: String, records: [IntakeRecord]) throws {
        try mutateProduct(productId) { $0.refill(packs: packs, on: day, records: records) }
    }

    /// Records that the restock reminder for the current pack was sent
    /// (at most one per pack, design D5).
    public func markRestockReminded(_ productId: UUID) throws {
        try mutateProduct(productId) { $0.restockRemindedFor = $0.stockSetOn }
    }

    /// Sets (or, with `nil`, turns off) the reminder time of `slot`
    /// (`SupplementPlan.setReminderMinute`, wave 3). No write when
    /// unchanged.
    public func setReminderMinute(_ minute: Int?, for slot: TimeSlot) throws {
        var next = try loadedForWrite()
        next.setReminderMinute(minute, for: slot)
        guard next != current else { return }
        try save(next)
    }

    // MARK: Files

    private func mutateProduct(_ productId: UUID, _ change: (inout SupplementProduct) -> Void) throws {
        var next = try loadedForWrite()
        guard let index = next.products.firstIndex(where: { $0.id == productId }) else { return }
        let before = next.products[index]
        change(&next.products[index])
        guard next.products[index] != before else { return }
        try save(next)
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        let result = FoodLogCoreStorage.loadPersistedJSON(SupplementPlan.self, from: fileURL, decoder: JSONDecoder(), category: "SupplementPlanStore")
        current = result.value ?? SupplementPlan()
        // Unreadable (e.g. before first unlock): retry on next access.
        loaded = !result.isUnreadable
    }

    private func readable() throws -> SupplementPlan {
        loadIfNeeded()
        guard loaded else { throw PersistedJSONUnreadFileError(fileName: fileURL.lastPathComponent) }
        return current
    }

    /// Loads, then refuses to go on when the file couldn't be read.
    private func loadedForWrite() throws -> SupplementPlan {
        loadIfNeeded()
        try FoodLogCoreStorage.ensureSafeToWrite(loaded: loaded, fileURL: fileURL, category: "SupplementPlanStore")
        return current
    }

    private func save(_ next: SupplementPlan) throws {
        try SupplementStoreIO.write(next, to: fileURL, category: "SupplementPlanStore")
        current = next
    }
}
