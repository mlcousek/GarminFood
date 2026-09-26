// SupplementSignals.swift
//
// The supplement digest (add-supplements D1/D9): everything the adherence
// calendar (wave 3) and the Gamification package's `supplements` feature
// (wave 6) read, built from the plan + intake log in ONE pure pass. The
// Gamification package never imports the supplement stores; the app builds
// this and hands it in (like `DaySignals`).
//
// Per day (oldest first, `fromDay...today`):
//   - `status`: complete / partial / missed / neutral (SupplementChecklist),
//     against the schedule in effect THAT day (D3), so a backfilled day
//     (D14) simply re-classifies;
//   - `ingredients`: canonical amounts of everything recorded that day,
//     planned + extras (vitamin collection, creatine journey, "Sunshine");
//   - `grantsXP`: the day's planned ticks were all written within the 7-day
//     grace (PastDayLogging.grantsXP) -- history farming pays nothing (D14);
//   - `slotMinutes`: per slot key, the minute of the day the slot was
//     completed (latest `takenAt` of its planned ticks), for challenges such
//     as "evening slot before 22:00".
//
// Plus: `isEnabled`, `hasPlan` (at least one product -- badges, challenges
// and the journey only run then, spec), `refillsBeforeEmpty` ("Never ran
// out"), and `frozenDays`, which the app fills in after the shared freeze
// planner ran (the streak itself is computed in Gamification).
//
// Depends on: SupplementChecklist, IngredientTotals, PastDayLogging,
// SupplementDate. Depended on by: the app's supplements screen and
// FeatureHost; Gamification's SupplementsFeature / SupplementStreak.
// Tests: SupplementSignalsTests.

import Foundation

public struct SupplementDaySignal: Sendable, Equatable {
    public let day: String
    public let status: SupplementDayStatus
    public let plannedCount: Int
    public let takenCount: Int
    /// Canonical-unit amount per ingredient recorded that day.
    public let ingredients: [IngredientID: Double]
    public let grantsXP: Bool
    /// Slot key -> minute of the day the slot was completed.
    public let slotMinutes: [String: Int]

    public init(
        day: String,
        status: SupplementDayStatus,
        plannedCount: Int,
        takenCount: Int,
        ingredients: [IngredientID: Double],
        grantsXP: Bool,
        slotMinutes: [String: Int]
    ) {
        self.day = day
        self.status = status
        self.plannedCount = plannedCount
        self.takenCount = takenCount
        self.ingredients = ingredients
        self.grantsXP = grantsXP
        self.slotMinutes = slotMinutes
    }

    public func took(_ ingredient: IngredientID) -> Bool {
        (ingredients[ingredient] ?? 0) > 0
    }
}

public struct SupplementSignals: Sendable, Equatable {
    public let isEnabled: Bool
    /// At least one product in the stack.
    public let hasPlan: Bool
    public let today: String
    /// Oldest first.
    public let days: [SupplementDaySignal]
    /// Refills recorded while the previous pack still had servings left.
    public let refillsBeforeEmpty: Int
    /// `yyyy-MM-dd` days a streak freeze covers for the supplement streak
    /// (set by the app after the shared freeze planner ran).
    public var frozenDays: Set<String>

    public init(
        isEnabled: Bool,
        hasPlan: Bool,
        today: String,
        days: [SupplementDaySignal],
        refillsBeforeEmpty: Int = 0,
        frozenDays: Set<String> = []
    ) {
        self.isEnabled = isEnabled
        self.hasPlan = hasPlan
        self.today = today
        self.days = days
        self.refillsBeforeEmpty = refillsBeforeEmpty
        self.frozenDays = frozenDays
    }

    /// Whether badges, challenges, the collection and the journey run.
    public var isActive: Bool { isEnabled && hasPlan }

    public func day(_ key: String) -> SupplementDaySignal? {
        days.first { $0.day == key }
    }

    /// Day key -> status, for the freeze planner and the calendar.
    public var statusByDay: [String: SupplementDayStatus] {
        Dictionary(days.map { ($0.day, $0.status) }, uniquingKeysWith: { _, last in last })
    }
}

public enum SupplementSignalsBuilder {
    /// How far back the digest looks by default (badges like "Sunshine"
    /// need a whole winter).
    public static let defaultLookbackDays = 365

    public static func build(
        isEnabled: Bool,
        plan: SupplementPlan,
        records: [IntakeRecord],
        trainingDays: Set<String>,
        fromDay: String,
        today: String,
        calendar: Calendar = .current
    ) -> SupplementSignals {
        let byDay = Dictionary(grouping: records, by: \.day)
        var days: [SupplementDaySignal] = []
        for day in SupplementDate.days(from: fromDay, through: today) {
            let dayRecords = byDay[day] ?? []
            let checklist = SupplementChecklist(day: day, plan: plan, records: dayRecords, trainingDays: trainingDays)
            let totals = IngredientTotals.of(day: day, records: dayRecords, products: plan.products)
            let planned = dayRecords.filter { $0.kind == .planned }
            var slotMinutes: [String: Int] = [:]
            for slot in checklist.slots where checklist.isComplete(slot) {
                let times = planned.filter { $0.slot?.key == slot.key }.map(\.takenAt)
                if let latest = times.max() {
                    slotMinutes[slot.key] = SupplementSlotTimes.minute(of: latest, calendar: calendar)
                }
            }
            days.append(SupplementDaySignal(
                day: day,
                status: checklist.status,
                plannedCount: checklist.entries.count,
                takenCount: checklist.entries.filter(\.isTaken).count,
                ingredients: totals.amounts,
                grantsXP: planned.allSatisfy(PastDayLogging.grantsXP),
                slotMinutes: slotMinutes
            ))
        }
        return SupplementSignals(
            isEnabled: isEnabled,
            hasPlan: !plan.products.isEmpty,
            today: today,
            days: days,
            refillsBeforeEmpty: plan.products.reduce(0) { $0 + ($1.refillsBeforeEmpty ?? 0) }
        )
    }
}
