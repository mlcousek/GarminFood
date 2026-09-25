// SupplementChecklist.swift
//
// A day's checklist and its classification (add-supplements D2, spec "A day
// is stack complete only when every planned item is taken"):
//   - complete: every planned item has a planned intake record;
//   - partial:  some, not all;
//   - missed:   none;
//   - neutral:  nothing was planned (neither complete nor missed -- it
//               neither extends nor breaks the streak, D9).
// Extra doses are listed but never satisfy a planned item.
//
// Rebuilt from the plan + intake log on every evaluation, never stored, so a
// backfilled or corrected past day (D14) simply re-classifies. Whether
// "today, still open" is shown as missed is the caller's call: this type
// judges the records as they are.
//
// Also the per-product adherence percentage (spec "Adherence history is
// shown per product and overall"), which is the same "planned vs ticked"
// question asked over a window of days.
//
// Depended on by: the supplements screen and Today card (wave 3),
// reminders (a slot that `isComplete` gets no reminder, wave 4), the
// gamification digest (wave 6). Tests: SupplementChecklistTests.

import Foundation

public enum SupplementDayStatus: String, Sendable, Equatable, CaseIterable {
    case complete
    case partial
    case missed
    case neutral
}

public struct SupplementChecklist: Sendable, Equatable {
    public struct Entry: Sendable, Equatable {
        public let item: DueItem
        public let isTaken: Bool
    }

    public let day: String
    /// Planned items in slot order.
    public let entries: [Entry]
    /// The day's extra (off-plan) doses.
    public let extras: [IntakeRecord]

    public init(day: String, due: [DueItem], records: [IntakeRecord]) {
        self.day = day
        let dayRecords = records.filter { $0.day == day }
        let takenKeys = Set(dayRecords.compactMap(\.plannedKey))
        self.entries = due.map { Entry(item: $0, isTaken: takenKeys.contains($0.key(on: day))) }
        self.extras = dayRecords.filter { $0.kind == .extra }
    }

    /// The checklist of `day` against the schedule in effect that day.
    public init(day: String, plan: SupplementPlan, records: [IntakeRecord], trainingDays: Set<String>) {
        self.init(day: day, due: ScheduleEvaluator.due(on: day, plan: plan, trainingDays: trainingDays), records: records)
    }

    public var status: SupplementDayStatus {
        guard !entries.isEmpty else { return .neutral }
        let taken = entries.filter(\.isTaken).count
        if taken == entries.count { return .complete }
        return taken == 0 ? .missed : .partial
    }

    /// Slots with at least one planned item, in order.
    public var slots: [TimeSlot] {
        var seen = Set<String>()
        return entries.map(\.item.slot).filter { seen.insert($0.key).inserted }
    }

    public func entries(in slot: TimeSlot) -> [Entry] {
        entries.filter { $0.item.slot.key == slot.key }
    }

    /// Every planned item of `slot` is taken. A slot with nothing planned
    /// counts as complete (nothing to remind about).
    public func isComplete(_ slot: TimeSlot) -> Bool {
        entries(in: slot).allSatisfy(\.isTaken)
    }

    /// The Today card's "current slot" (design D4): the first incomplete
    /// slot at or after `preferred` (the next due slot by clock time, which
    /// the host knows), falling back to the first incomplete slot of the
    /// day; `nil` when the stack is done.
    public func currentSlot(preferring preferred: TimeSlot? = nil) -> TimeSlot? {
        let open = slots.filter { !isComplete($0) }
        if let preferred, let next = open.first(where: { !($0 < preferred) }) {
            return next
        }
        return open.first
    }
}

/// Planned vs ticked servings of one product over a window of days.
public struct SupplementAdherence: Sendable, Equatable {
    /// Planned item occurrences (one per product per slot per day).
    public let planned: Int
    public let taken: Int

    public init(planned: Int, taken: Int) {
        self.planned = planned
        self.taken = taken
    }

    /// 0...100, `nil` when nothing was planned.
    public var percent: Int? {
        guard planned > 0 else { return nil }
        return Int((Double(taken) / Double(planned) * 100).rounded())
    }

    /// Adherence of `productId` (or of the whole stack when `nil`) over
    /// `days`, each checked against the schedule in effect that day.
    public static func over(
        days: [String],
        productId: UUID?,
        plan: SupplementPlan,
        records: [IntakeRecord],
        trainingDays: Set<String>
    ) -> SupplementAdherence {
        let byDay = Dictionary(grouping: records, by: \.day)
        var planned = 0
        var taken = 0
        for day in days {
            let checklist = SupplementChecklist(day: day, plan: plan, records: byDay[day] ?? [], trainingDays: trainingDays)
            for entry in checklist.entries where productId == nil || entry.item.productId == productId {
                planned += 1
                if entry.isTaken { taken += 1 }
            }
        }
        return SupplementAdherence(planned: planned, taken: taken)
    }
}
