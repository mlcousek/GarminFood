// SupplementReminderTimesView.swift
//
// add-supplements task 3.1 / design D5: one reminder per time slot, at a
// time the user picks, sent only if that slot isn't done yet. Defaults are
// the design's open-question answers (tasks 0.3, defaulted): morning 08:00,
// evening 21:00, with-breakfast and pre-workout off until set. The times
// live in the plan (`SupplementPlan.slotReminders`); planning and the
// "skip once done" rule are FoodLogCore's `NotificationPlanning`.
//
// Depends on: SupplementsController, FoodLogCore (SupplementSlotTimes).
// Depended on by: SupplementsView, SupplementsOnboardingView.

import SwiftUI
import FoodLogCore

@MainActor
struct SupplementReminderTimesView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        Form {
            SupplementReminderTimesSection()
        }
        .navigationTitle("Reminder times")
        .task {
            await NotificationScheduler.shared.requestAuthorizationIfNeeded()
        }
    }
}

@MainActor
struct SupplementReminderTimesSection: View {
    @Environment(AppEnvironment.self) private var environment

    private var supplements: SupplementsController { environment.supplements }

    var body: some View {
        Section {
            ForEach(SupplementSlotTimes.builtInSlots, id: \.key) { slot in
                let minute = supplements.plan.reminderMinute(for: slot)
                Toggle(isOn: Binding(
                    get: { minute != nil },
                    set: { isOn in
                        let value = isOn ? (SupplementSlotTimes.defaultReminderMinute(for: slot) ?? 7 * 60) : nil
                        Task { await supplements.setReminderMinute(value, for: slot) }
                    }
                )) {
                    Label(slot.displayName, systemImage: slot.symbolName)
                }
                if let minute {
                    DatePicker(
                        selection: Binding(
                            get: { Self.date(minute) },
                            set: { date in
                                Task { await supplements.setReminderMinute(SupplementSlotTimes.minute(of: date), for: slot) }
                            }
                        ),
                        displayedComponents: .hourAndMinute
                    ) {
                        Text("Time")
                    }
                }
            }
        } header: {
            Text("Reminders")
        } footer: {
            Text("A reminder comes only if that slot isn't ticked yet, and its Taken button ticks it without opening the app.", comment: "Supplement reminder times: footer.")
        }
    }

    private static func date(_ minute: Int) -> Date {
        Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: Date()) ?? Date()
    }
}
