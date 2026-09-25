// StockProjection.swift
//
// Stock, days left, restock trigger and cost (add-supplements D2/D5/D14,
// spec "Stock and cost are tracked per product", "A restock reminder fires
// before a product runs out").
//
// Stock model (D14): a product stores `stockServings`, the servings on hand
// at the START of `stockSetOn`. Remaining = that minus every serving
// recorded (planned or extra) on or after `stockSetOn`. So:
//   - each tick drains the pack, with no stored per-tick state;
//   - backfilling a day BEFORE the current pack (D14) doesn't drain it;
//   - setting or refilling the stock mid-day stores the start-of-day
//     figure, so what was already taken that day isn't subtracted twice.
//
// Days left divide what remains by the planned servings per day of the
// schedule in effect, averaged over 28 days so every-N-days, weekday and
// cycle patterns project sensibly: forward from today for patterns known
// in advance; backward over the last 28 days for `.trainingDays`, whose
// future days nobody knows yet. It's an estimate, shown as one.
//
// Restock: once per pack -- `restockRemindedFor` holds the `stockSetOn`
// already reminded about, and a refill (new `stockSetOn`) re-arms it.
//
// Cost: price per pack / servings per pack x planned servings per day;
// per month = 30 days. Formatting (locale decimals, "7,50 CZK") is the
// view's job.
//
// Depended on by: the stock overview and cost views (wave 3), restock
// reminders (wave 4). Tests: StockProjectionTests.

import Foundation

public enum StockProjection {
    public static let rateWindowDays = 28
    public static let defaultRestockLeadDays = 7
    public static let daysPerMonth = 30.0

    /// Servings left, `nil` while no stock was ever set.
    public static func remainingServings(of product: SupplementProduct, records: [IntakeRecord]) -> Double? {
        guard let start = product.stockServings, let since = product.stockSetOn else { return nil }
        return start - servingsTaken(of: product.id, since: since, records: records)
    }

    /// Servings of `productId` recorded on or after `since`.
    static func servingsTaken(of productId: UUID, since: String, records: [IntakeRecord]) -> Double {
        records
            .filter { $0.productId == productId && $0.day >= since }
            .reduce(0) { $0 + max(0, $1.servings) }
    }

    /// Average planned servings per day (see header for the window).
    public static func plannedServingsPerDay(of productId: UUID, plan: SupplementPlan, today: String, trainingDays: Set<String>) -> Double {
        guard SupplementDate.ordinal(today) != nil else { return 0 }
        let window = rateWindowDays
        if let current = plan.schedule(of: productId, on: today), case .trainingDays = current.pattern {
            // Future training days are unknown: use how often the last
            // 28 days were training days, under today's schedule.
            let pastDays = (1...window).compactMap { SupplementDate.adding(-$0, to: today) }
            let total = pastDays.reduce(0.0) { sum, day in
                sum + ScheduleEvaluator.servingsPerSlot(current, on: day, trainingDays: trainingDays) * Double(uniqueSlotCount(current))
            }
            return total / Double(window)
        }
        let futureDays = (0..<window).compactMap { SupplementDate.adding($0, to: today) }
        let total = futureDays.reduce(0.0) { sum, day in
            guard let schedule = plan.schedule(of: productId, on: day) else { return sum }
            return sum + ScheduleEvaluator.servingsPerSlot(schedule, on: day, trainingDays: trainingDays) * Double(uniqueSlotCount(schedule))
        }
        return total / Double(window)
    }

    /// Whole days the remaining stock lasts at the planned rate; `nil` when
    /// no stock is set or nothing is planned (it never runs out).
    public static func daysLeft(
        of product: SupplementProduct,
        plan: SupplementPlan,
        records: [IntakeRecord],
        today: String,
        trainingDays: Set<String>
    ) -> Int? {
        guard let remaining = remainingServings(of: product, records: records) else { return nil }
        let rate = plannedServingsPerDay(of: product.id, plan: plan, today: today, trainingDays: trainingDays)
        guard rate > 0 else { return nil }
        guard remaining > 0 else { return 0 }
        // Small slack so 30 / 2 is 15, not 14.999...
        return Int((remaining / rate + 1e-9).rounded(.down))
    }

    /// Whether to send the restock reminder now: projected days left at or
    /// below the lead time, and not yet reminded for this pack.
    public static func shouldRemindRestock(
        _ product: SupplementProduct,
        daysLeft: Int?,
        leadTimeDays: Int = defaultRestockLeadDays
    ) -> Bool {
        guard let daysLeft, let pack = product.stockSetOn else { return false }
        return daysLeft <= leadTimeDays && product.restockRemindedFor != pack
    }

    public static func costPerServing(of product: SupplementProduct) -> Double? {
        guard let price = product.pricePerPack, let servings = product.packServings, price >= 0, servings > 0 else { return nil }
        return price / servings
    }

    public struct Cost: Sendable, Equatable {
        public let perDay: Double
        public let perMonth: Double
        /// ISO 4217, CZK by default.
        public let currency: String
    }

    /// Cost at the planned rate; `nil` without a price and pack size.
    public static func cost(of product: SupplementProduct, plan: SupplementPlan, today: String, trainingDays: Set<String>) -> Cost? {
        guard let perServing = costPerServing(of: product) else { return nil }
        let perDay = perServing * plannedServingsPerDay(of: product.id, plan: plan, today: today, trainingDays: trainingDays)
        return Cost(perDay: perDay, perMonth: perDay * daysPerMonth, currency: product.effectiveCurrency)
    }

    private static func uniqueSlotCount(_ schedule: SupplementSchedule) -> Int {
        Set(schedule.slots.map(\.key)).count
    }
}

extension SupplementProduct {
    /// Sets the stock to `servingsOnHand` right now, on `day`. Stored as the
    /// start-of-day figure (what was already recorded on `day` added back),
    /// so today's earlier ticks aren't subtracted a second time.
    public mutating func setStock(servingsOnHand: Double, on day: String, records: [IntakeRecord]) {
        let takenToday = records
            .filter { $0.productId == id && $0.day == day }
            .reduce(0) { $0 + max(0, $1.servings) }
        let takenLater = records
            .filter { $0.productId == id && $0.day > day }
            .reduce(0) { $0 + max(0, $1.servings) }
        // Records dated after `day` (only possible when the clock moved)
        // are part of the new pack too; keep "on hand now" true.
        stockServings = max(0, servingsOnHand) + takenToday + takenLater
        stockSetOn = day
    }

    /// Adds `packs` full packs to what is left now (a refill), on `day`.
    /// Without a known pack size nothing changes.
    public mutating func refill(packs: Double = 1, on day: String, records: [IntakeRecord]) {
        guard let packServings, packServings > 0, packs > 0 else { return }
        let left = max(0, StockProjection.remainingServings(of: self, records: records) ?? 0)
        setStock(servingsOnHand: left + packs * packServings, on: day, records: records)
    }
}
