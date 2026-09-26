// SupplementReminderPlanning.swift
//
// add-supplements D5 / wave 4 (tasks 4.1, 4.3): WHAT supplement reminders
// should be pending right now -- pure, like the rest of
// `NotificationPlanning`. The app's `NotificationScheduler` asks this on
// every foreground, tick and supplement-setting change and diffs the result
// against what is pending (`NotificationPlanning.diff`, which also compares
// title/body, so a language switch re-plans the text -- spec "Language
// switch").
//
// Two kinds:
//   - `.slot`: one reminder per time slot that has planned items on a day,
//     at the slot's reminder time (`SupplementPlan.reminderMinute(for:)`),
//     SKIPPED once every item of the slot is ticked (spec "Slot completed
//     early") or when nothing is due in it (spec "Nothing due in a slot").
//     Planned for today AND tomorrow, so a reminder still fires on a day the
//     app isn't opened (tomorrow's is re-planned the moment the app runs
//     again). Each carries the day + slot in `userInfo` for the "Taken"
//     action (`SupplementSlotTaking`).
//   - `.restock`: at most once per pack (`StockProjection.shouldRemindRestock`
//     against `restockRemindedFor`), when projected days left reach the lead
//     time. The scheduler sends it once and then marks the pack reminded, so
//     it is NOT part of the diffed set (a diff would remove it the moment it
//     is marked) -- see `NotificationScheduler.syncSupplementReminders`.
//
// Nothing is planned while the feature is off (`isEnabled == false`), so the
// scheduler's diff removes every pending supplement reminder (task 4.3,
// spec "Disable and re-enable": no reminder while off).
//
// Depends on: SupplementChecklist, ScheduleEvaluator, SupplementSlotTimes,
// StockProjection, SupplementTexts, NotificationPlanning.NotificationText.
// Depended on by: the app's NotificationScheduler / AppEnvironment.
// Tests: SupplementReminderPlanningTests.

import Foundation

public struct PlannedSupplementReminder: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable {
        case slot(slotKey: String)
        case restock(productId: UUID)
    }

    /// Stable id without the scheduler's prefix: `slot.<day>.<slotKey>` or
    /// `restock.<productId>.<stockSetOn>`.
    public let id: String
    public let kind: Kind
    /// The `yyyy-MM-dd` day the reminder belongs to (fires on).
    public let day: String
    public let title: String
    public let body: String
    public let hour: Int
    public let minute: Int

    public var text: NotificationPlanning.NotificationText {
        NotificationPlanning.NotificationText(title: title, body: body)
    }

    /// What the "Taken" action needs (`SupplementSlotTaking.userInfo`);
    /// empty for a restock reminder.
    public var userInfo: [String: String] {
        guard case .slot(let slotKey) = kind else { return [:] }
        return SupplementSlotTaking.userInfo(day: day, slotKey: slotKey)
    }
}

extension NotificationPlanning {
    /// The notification category of a slot reminder (it carries the
    /// "Taken" action, D5).
    public static let supplementSlotCategory = "SUPPLEMENT_SLOT"
    /// The "Taken" action identifier.
    public static let supplementTakenAction = "SUPPLEMENT_TAKEN"

    /// Slot reminders for `days` (normally today and tomorrow).
    ///
    /// - Parameters:
    ///   - isEnabled: `AppPreferences.supplementsEnabled`.
    ///   - records: intake on those days (ticked items skip the slot).
    ///   - nowMinute / today: a reminder of TODAY whose time has passed is
    ///     left out (it could only fire late); tomorrow's always counts.
    public static func planSupplementSlotReminders(
        isEnabled: Bool,
        plan: SupplementPlan,
        days: [String],
        records: [IntakeRecord],
        trainingDays: Set<String>,
        today: String,
        nowMinute: Int
    ) -> [PlannedSupplementReminder] {
        guard isEnabled else { return [] }
        let names = Dictionary(plan.products.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        var result: [PlannedSupplementReminder] = []
        for day in days {
            let checklist = SupplementChecklist(day: day, plan: plan, records: records, trainingDays: trainingDays)
            for slot in checklist.slots where !checklist.isComplete(slot) {
                guard let minute = plan.reminderMinute(for: slot) else { continue }
                if day == today, minute <= nowMinute { continue }
                if day < today { continue }
                let open = checklist.entries(in: slot).filter { !$0.isTaken }
                let productNames = open.compactMap { names[$0.item.productId] }.filter { !$0.isEmpty }
                result.append(PlannedSupplementReminder(
                    id: "slot.\(day).\(slot.key)",
                    kind: .slot(slotKey: slot.key),
                    day: day,
                    title: slotReminderTitle(slot),
                    body: slotReminderBody(productNames),
                    hour: minute / 60,
                    minute: minute % 60
                ))
            }
        }
        return result
    }

    /// Restock reminders due now: one per product whose projected days
    /// left are at or below `leadTimeDays` and whose current pack wasn't
    /// reminded about yet. Fires at `hour:minute` on `today` (the scheduler
    /// fires it soon instead when that time has passed).
    public static func planSupplementRestockReminders(
        isEnabled: Bool,
        plan: SupplementPlan,
        records: [IntakeRecord],
        trainingDays: Set<String>,
        today: String,
        leadTimeDays: Int = StockProjection.defaultRestockLeadDays,
        hour: Int = 10,
        minute: Int = 0
    ) -> [PlannedSupplementReminder] {
        guard isEnabled else { return [] }
        var result: [PlannedSupplementReminder] = []
        for product in plan.activeProducts(on: today) {
            let daysLeft = StockProjection.daysLeft(of: product, plan: plan, records: records, today: today, trainingDays: trainingDays)
            guard StockProjection.shouldRemindRestock(product, daysLeft: daysLeft, leadTimeDays: leadTimeDays),
                  let daysLeft, let pack = product.stockSetOn
            else { continue }
            result.append(PlannedSupplementReminder(
                id: "restock.\(product.id.uuidString).\(pack)",
                kind: .restock(productId: product.id),
                day: today,
                title: String(localized: "Running low: \(product.name)", bundle: .module, comment: "Supplement restock reminder title. %@ is the product name."),
                body: restockBody(daysLeft: daysLeft),
                hour: hour,
                minute: minute
            ))
        }
        return result
    }

    /// Whole sentences per built-in slot (Czech inflects the slot name, so
    /// no shared "%@ supplements" template).
    static func slotReminderTitle(_ slot: TimeSlot) -> String {
        switch slot {
        case .morning:
            return String(localized: "Morning supplements", bundle: .module, comment: "Supplement slot reminder title.")
        case .withBreakfast:
            return String(localized: "Supplements with breakfast", bundle: .module, comment: "Supplement slot reminder title.")
        case .preWorkout:
            return String(localized: "Pre-workout supplements", bundle: .module, comment: "Supplement slot reminder title.")
        case .evening:
            return String(localized: "Evening supplements", bundle: .module, comment: "Supplement slot reminder title.")
        case .custom(let name, _):
            return String(localized: "Supplements: \(name)", bundle: .module, comment: "Supplement reminder title for a slot the user named. %@ is that name.")
        }
    }

    static func slotReminderBody(_ productNames: [String]) -> String {
        guard !productNames.isEmpty else {
            return String(localized: "Time for your supplements.", bundle: .module, comment: "Supplement slot reminder body when no product name is known.")
        }
        let list = productNames.joined(separator: ", ")
        return String(localized: "Take: \(list)", bundle: .module, comment: "Supplement slot reminder body. %@ is a comma-separated list of product names.")
    }

    static func restockBody(daysLeft: Int) -> String {
        if daysLeft <= 0 {
            return String(localized: "It has run out. Time to restock.", bundle: .module, comment: "Supplement restock reminder body when nothing is left.")
        }
        return String(localized: "About \(daysLeft) days left. Time to restock.", bundle: .module, comment: "Supplement restock reminder body. Plural in Localizable.stringsdict.")
    }
}
