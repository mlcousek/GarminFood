// SupplementSlotTimes.swift
//
// Clock times of the supplement time slots (add-supplements D4/D5/D10):
//   - the reminder time per slot the user picks in onboarding and the
//     schedule editor (wave 3 stores it on `SupplementPlan.slotReminders`,
//     wave 4's reminder planner reads it back through `reminderMinute(for:)`);
//   - the Today card's "next due slot" (D4): which slot the clock says is
//     current, handed to `SupplementChecklist.currentSlot(preferring:)`.
//
// Defaults follow the design's open question 0.3 until the owner confirms
// them: morning 08:00, evening 21:00, pre-workout none (manual). "With
// breakfast" has no default reminder either -- breakfast time varies too
// much to guess -- but can be given one.
//
// Kept on the plan (not in UserDefaults) so the times travel with the
// supplement data in a backup/restore (add-data-safety copies the data
// directory) and stay next to the slots they belong to.
//
// Pure; tests: SupplementSlotTimesTests.

import Foundation

/// A reminder time the user set for one slot. `minute == nil` means "no
/// reminder for this slot" (explicitly off), which is different from a
/// slot without an entry (the default applies).
public struct SlotReminder: Codable, Sendable, Equatable {
    /// `TimeSlot.key`.
    public var slotKey: String
    /// Minute of the day, 0..<1440.
    public var minute: Int?

    public init(slotKey: String, minute: Int?) {
        self.slotKey = slotKey
        self.minute = minute
    }
}

public enum SupplementSlotTimes {
    public static let minutesPerDay = 24 * 60

    /// The built-in slots in their fixed order (the editor's choices).
    public static let builtInSlots: [TimeSlot] = [.morning, .withBreakfast, .preWorkout, .evening]

    /// The default reminder time of `slot`, `nil` for none.
    public static func defaultReminderMinute(for slot: TimeSlot) -> Int? {
        switch slot {
        case .morning: return 8 * 60
        case .evening: return 21 * 60
        case .withBreakfast, .preWorkout: return nil
        case .custom(_, let minute): return validMinute(minute)
        }
    }

    /// `minute` when it is a minute of the day, else `nil`.
    public static func validMinute(_ minute: Int?) -> Int? {
        guard let minute, minute >= 0, minute < minutesPerDay else { return nil }
        return minute
    }

    /// The slot the clock says is current at `nowMinute` among `slots`: the
    /// one with the latest reminder time at or before now. Slots without a
    /// time are never picked here (they still show as the fallback of
    /// `SupplementChecklist.currentSlot(preferring:)`). `nil` before the
    /// first timed slot of the day.
    public static func preferredSlot(among slots: [TimeSlot], atMinute nowMinute: Int, plan: SupplementPlan) -> TimeSlot? {
        var best: (slot: TimeSlot, minute: Int)?
        for slot in slots {
            guard let minute = plan.reminderMinute(for: slot), minute <= nowMinute else { continue }
            if let current = best, current.minute > minute { continue }
            best = (slot, minute)
        }
        return best?.slot
    }

    /// Minute of the day of `date` in `calendar`.
    public static func minute(of date: Date, calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}

extension SupplementPlan {
    /// The reminder time of `slot`: the user's choice, else the default.
    public func reminderMinute(for slot: TimeSlot) -> Int? {
        if let reminder = slotReminders?.first(where: { $0.slotKey == slot.key }) {
            return SupplementSlotTimes.validMinute(reminder.minute)
        }
        return SupplementSlotTimes.defaultReminderMinute(for: slot)
    }

    /// Sets (or, with `nil`, turns off) the reminder time of `slot`. An
    /// invalid minute counts as off.
    public mutating func setReminderMinute(_ minute: Int?, for slot: TimeSlot) {
        var list = slotReminders ?? []
        let entry = SlotReminder(slotKey: slot.key, minute: SupplementSlotTimes.validMinute(minute))
        if let index = list.firstIndex(where: { $0.slotKey == slot.key }) {
            list[index] = entry
        } else {
            list.append(entry)
        }
        slotReminders = list
    }

    /// Every distinct slot used by a schedule in effect on `day`, in slot
    /// order (whether or not its pattern is due that day).
    public func slotsInUse(on day: String) -> [TimeSlot] {
        var seen = Set<String>()
        var result: [TimeSlot] = []
        for item in items {
            guard product(id: item.productId) != nil, let schedule = item.schedule(on: day) else { continue }
            for slot in schedule.slots where seen.insert(slot.key).inserted {
                result.append(slot)
            }
        }
        return result.sorted()
    }

    /// Products with a schedule in effect on `day`, in stack order ("My
    /// stack"). A product taken out of the stack is still in `products`
    /// (its history needs the label) but not here.
    public func activeProducts(on day: String) -> [SupplementProduct] {
        products.filter { schedule(of: $0.id, on: day) != nil }
    }

    /// Products without a schedule on `day`: added but not planned, or
    /// taken out of the stack.
    public func inactiveProducts(on day: String) -> [SupplementProduct] {
        products.filter { schedule(of: $0.id, on: day) == nil }
    }
}
