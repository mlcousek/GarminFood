// SupplementSlotTaking.swift
//
// "Tick every planned item of one slot on one day" -- the one write behind
// the Today card's / checklist's "Take all" AND the reminder's "Taken"
// notification action (add-supplements D4/D5, task 4.2, spec "The reminder
// has a 'Taken' action that ticks the slot").
//
// Kept in FoodLogCore (not the app's notification delegate) so it is unit
// tested against real stores: the action can be delivered twice (spec
// "Double tap") and must leave exactly one record per item -- which
// `SupplementIntakeStore.recordPlanned` guarantees by its (day, product,
// slot) key; this type only resolves WHICH items the slot plans that day,
// against the schedule in effect then (D3).
//
// The notification carries the day and slot in `userInfo` (`userInfo(...)`
// / `parse(_:)`), never product ids: whatever the slot plans when the action
// runs is what gets ticked, so an edit made after the reminder was scheduled
// can't tick a product that was removed.
//
// Local only, no network (zero-network-wait rule). A store that can't be
// read (phone locked before first unlock) throws; the caller opens the app
// on the slot and logs to DiagnosticsLog (D5 fallback).
//
// Depends on: SupplementPlanStore, SupplementIntakeStore, ScheduleEvaluator.
// Depended on by: the app's supplements screen, Today card and
// notification delegate. Tests: SupplementSlotTakingTests.

import Foundation

public enum SupplementSlotTaking {
    public static let dayKey = "supplementDay"
    public static let slotKey = "supplementSlot"

    /// The `userInfo` of a slot reminder.
    public static func userInfo(day: String, slotKey: String) -> [String: String] {
        [Self.dayKey: day, Self.slotKey: slotKey]
    }

    /// The day and slot key a notification's `userInfo` names, or `nil`
    /// when it isn't a supplement slot reminder.
    public static func parse(_ userInfo: [AnyHashable: Any]) -> (day: String, slotKey: String)? {
        guard let day = userInfo[Self.dayKey] as? String,
              let slot = userInfo[Self.slotKey] as? String,
              SupplementDate.ordinal(day) != nil, !slot.isEmpty
        else { return nil }
        return (day, slot)
    }

    /// The planned items of the slot `slotKey` on `day`.
    public static func dueItems(plan: SupplementPlan, day: String, slotKey: String, trainingDays: Set<String>) -> [DueItem] {
        ScheduleEvaluator.due(on: day, plan: plan, trainingDays: trainingDays).filter { $0.slot.key == slotKey }
    }

    /// Ticks the slot. Idempotent: items already ticked keep their record.
    /// Returns the records now stored for the slot's items (empty when the
    /// slot plans nothing that day).
    @discardableResult
    public static func take(
        slotKey: String,
        on day: String,
        planStore: SupplementPlanStore,
        intakeStore: SupplementIntakeStore,
        trainingDays: Set<String>,
        today: String,
        now: Date
    ) async throws -> [IntakeRecord] {
        let plan = try await planStore.plan()
        let items = dueItems(plan: plan, day: day, slotKey: slotKey, trainingDays: trainingDays)
        guard !items.isEmpty else { return [] }
        return try await intakeStore.recordPlanned(items, on: day, takenAt: now, today: today)
    }
}
