// ScheduleEvaluator.swift
//
// "What is due on this day?" (add-supplements D3) -- the one question the
// checklist, the Today card, reminders, stock projection, adherence and the
// streak all ask. Pure and exhaustively tested, because every one of those
// silently goes wrong if it does.
//
// Rules:
//   - A product's schedule on a day is the version in effect THAT day
//     (`PlanItem.schedule(on:)`), so an edit made today never rewrites what
//     was due on an earlier day, and a backfilled past day (D14) is checked
//     against the schedule that was active then.
//   - Patterns are pure arithmetic on day numbers (`SupplementDate`); a
//     cycle has no stored per-day state.
//   - `.trainingDays` asks the `trainingDays` set the host builds from the
//     activity cache and `race` day-note tags (`SupplementTrainingDays`).
//   - An unknown pattern (written by a later build) is never due.
//
// Depended on by: SupplementChecklist, StockProjection, the app's
// supplements screen and Today card (wave 3), reminders (wave 4).
// Tests: ScheduleEvaluatorTests.

import Foundation

/// One planned item on one day: `servings` of a product in a slot.
public struct DueItem: Hashable, Sendable {
    public let productId: UUID
    public let slot: TimeSlot
    public let servings: Double

    public init(productId: UUID, slot: TimeSlot, servings: Double) {
        self.productId = productId
        self.slot = slot
        self.servings = servings
    }

    /// The intake key a tick of this item is stored under.
    public func key(on day: String) -> PlannedIntakeKey {
        PlannedIntakeKey(day: day, productId: productId, slotKey: slot.key)
    }
}

public enum ScheduleEvaluator {
    /// Every planned item on `day`, ordered by slot, then by the product's
    /// position in the stack. Products without a schedule that day (not yet
    /// added, removed, or not due by pattern) contribute nothing.
    public static func due(on day: String, plan: SupplementPlan, trainingDays: Set<String>) -> [DueItem] {
        guard SupplementDate.ordinal(day) != nil else { return [] }
        var productOrder: [UUID: Int] = [:]
        for (index, product) in plan.products.enumerated() where productOrder[product.id] == nil {
            productOrder[product.id] = index
        }
        var result: [DueItem] = []
        for item in plan.items {
            guard productOrder[item.productId] != nil, let schedule = item.schedule(on: day) else { continue }
            let servings = servingsPerSlot(schedule, on: day, trainingDays: trainingDays)
            guard servings > 0 else { continue }
            var seenSlots = Set<String>()
            for slot in schedule.slots where seenSlots.insert(slot.key).inserted {
                result.append(DueItem(productId: item.productId, slot: slot, servings: servings))
            }
        }
        return result.sorted { lhs, rhs in
            if lhs.slot != rhs.slot { return lhs.slot < rhs.slot }
            return (productOrder[lhs.productId] ?? 0) < (productOrder[rhs.productId] ?? 0)
        }
    }

    /// Servings per slot `schedule` plans on `day`; 0 when not due.
    public static func servingsPerSlot(_ schedule: SupplementSchedule, on day: String, trainingDays: Set<String>) -> Double {
        guard let today = SupplementDate.ordinal(day) else { return 0 }
        let base = max(0, schedule.servingsPerSlot)
        switch schedule.pattern {
        case .daily:
            return base
        case .everyNDays(let n, let anchor):
            guard n >= 1, let start = SupplementDate.ordinal(anchor) else { return 0 }
            let offset = today - start
            return offset >= 0 && offset % n == 0 ? base : 0
        case .weekdays(let weekdays):
            guard let weekday = SupplementDate.weekday(day) else { return 0 }
            return weekdays.contains(weekday) ? base : 0
        case .trainingDays:
            return trainingDays.contains(day) ? base : 0
        case .cycle(let phases, let anchor, let repeats):
            guard let start = SupplementDate.ordinal(anchor) else { return 0 }
            return cycleServings(phases: phases, offset: today - start, repeats: repeats)
        case .unknown:
            return 0
        }
    }

    /// The servings of the cycle phase `offset` days after the anchor.
    /// Before the anchor nothing is due. Phases shorter than a day are
    /// ignored. Without `repeats` the last phase continues for good.
    static func cycleServings(phases: [CyclePhase], offset: Int, repeats: Bool) -> Double {
        let usable = phases.filter { $0.days >= 1 }
        guard offset >= 0, let last = usable.last else { return 0 }
        let length = usable.reduce(0) { $0 + $1.days }
        var position = offset
        if repeats {
            position = offset % length
        } else if offset >= length {
            return max(0, last.servingsPerSlot)
        }
        for phase in usable {
            if position < phase.days { return max(0, phase.servingsPerSlot) }
            position -= phase.days
        }
        return 0
    }
}
