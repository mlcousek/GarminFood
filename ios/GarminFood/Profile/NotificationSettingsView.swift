// NotificationSettingsView.swift
//
// Reminder settings: a toggle + time picker per reminder (breakfast, lunch,
// dinner, streak-at-risk, today's challenges), plus a toggle + minutes-before
// stepper for each fasting reminder -- "fast ending soon" and "fast starting
// soon", both anchored to the daily fasting window from Settings → Fasting
// (redesign-fasting-schedule; see `FastingReminderSetting`'s header for why
// those are steppers, not time pickers). Turning any one of these on for the first time requests
// notification permission; a denied/off system setting is shown plainly
// with a link to fix it in Settings, per this project's existing
// loud-failure convention (never a reminder that's silently never going to
// fire).
//
// add-training-checkins D8: in the training experience, one "Training
// reminders" switch (on by default) for the morning check-in reminder and
// the evening habits reminder; TrainingModel plans them.
// add-daily-checkin-and-pain-mode: the check-in reminder fires every day
// (not only on run days), and both have a time picker next to the switch
// (04:05 and 20:10 until changed), kept by TrainingModel like the food
// reminders' times.

import SwiftUI
import UIKit
import UserNotifications
import FoodLogCore
import TrainingCore

@MainActor
struct NotificationSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @State private var trainingRemindersOn = true
    @State private var trainingTimes = TrainingReminderTimes.standard

    var body: some View {
        Form {
            if authorizationStatus == .denied {
                Section {
                    Label("Notifications are off for Jirka's Arc in iOS Settings, so reminders below won't fire.", systemImage: "bell.slash")
                        .font(.footnote)
                        .foregroundStyle(Theme.warning)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            }

            Section {
                reminderRow(
                    title: String(localized: "Breakfast"),
                    setting: environment.notificationPreferences.preferences.breakfastReminder,
                    onChange: { environment.setBreakfastReminder($0) }
                )
                reminderRow(
                    title: String(localized: "Lunch"),
                    setting: environment.notificationPreferences.preferences.lunchReminder,
                    onChange: { environment.setLunchReminder($0) }
                )
                reminderRow(
                    title: String(localized: "Dinner"),
                    setting: environment.notificationPreferences.preferences.dinnerReminder,
                    onChange: { environment.setDinnerReminder($0) }
                )
            } header: {
                Text("Meal reminders")
            } footer: {
                Text("Reminds you at the chosen time only if that meal hasn't been logged yet that day.")
            }

            Section {
                reminderRow(
                    title: String(localized: "Streak at risk"),
                    setting: environment.notificationPreferences.preferences.streakReminder,
                    onChange: { environment.setStreakReminder($0) }
                )
            } footer: {
                Text("Only fires on a day you haven't logged anything yet, if you have a streak to lose.")
            }

            Section {
                reminderRow(
                    title: String(localized: "Today's challenges"),
                    setting: environment.notificationPreferences.preferences.dailyChallengeReminder,
                    onChange: { environment.setDailyChallengeReminder($0) }
                )
            } footer: {
                Text("A daily nudge to check today's challenges.")
            }

            if environment.experience == .training {
                Section {
                    Toggle("Training reminders", isOn: Binding(
                        get: { trainingRemindersOn },
                        set: { newValue in
                            trainingRemindersOn = newValue
                            Task {
                                if newValue {
                                    await environment.requestNotificationPermissionIfNeeded()
                                    await refreshStatus()
                                }
                                await environment.training.setRemindersEnabled(newValue)
                            }
                        }
                    ))
                    if trainingRemindersOn {
                        DatePicker("Check-in reminder", selection: trainingTimeBinding(morning: true), displayedComponents: .hourAndMinute)
                        DatePicker("Habits reminder", selection: trainingTimeBinding(morning: false), displayedComponents: .hourAndMinute)
                    }
                } header: {
                    Text("Training")
                } footer: {
                    Text("A check-in reminder every morning until you check in, and a habits reminder in the evening while habits are still open.")
                }
            }

            Section {
                fastingReminderRow(
                    title: String(localized: "Fast ending soon"),
                    setting: environment.notificationPreferences.preferences.fastingReminder,
                    onChange: { environment.setFastingReminder($0) }
                )
                fastingReminderRow(
                    title: String(localized: "Fast starting soon"),
                    setting: environment.notificationPreferences.preferences.fastingStartReminder,
                    onChange: { environment.setFastingStartReminder($0) }
                )
            } header: {
                Text("Fasting")
            } footer: {
                Text(fastingFooter)
            }
        }
        .navigationTitle("Reminders")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            trainingRemindersOn = environment.training.remindersEnabled
            trainingTimes = environment.training.reminderTimes
            await refreshStatus()
        }
    }

    /// add-daily-checkin-and-pain-mode: the check-in (`morning`) or the
    /// habits reminder time; a change is saved and the reminders re-planned.
    private func trainingTimeBinding(morning: Bool) -> Binding<Date> {
        Binding<Date>(
            get: {
                morning
                    ? Self.date(hour: trainingTimes.morningHour, minute: trainingTimes.morningMinute)
                    : Self.date(hour: trainingTimes.eveningHour, minute: trainingTimes.eveningMinute)
            },
            set: { newDate in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                let old = trainingTimes
                // Through the initialiser, which clamps into a day; a `let`,
                // so the task below captures a value, not a variable.
                let times = morning
                    ? TrainingReminderTimes(
                        morningHour: comps.hour ?? old.morningHour,
                        morningMinute: comps.minute ?? old.morningMinute,
                        eveningHour: old.eveningHour,
                        eveningMinute: old.eveningMinute
                    )
                    : TrainingReminderTimes(
                        morningHour: old.morningHour,
                        morningMinute: old.morningMinute,
                        eveningHour: comps.hour ?? old.eveningHour,
                        eveningMinute: comps.minute ?? old.eveningMinute
                    )
                guard times != old else { return }
                trainingTimes = times
                Task { await environment.training.setReminderTimes(times) }
            }
        )
    }

    @ViewBuilder
    private func reminderRow(title: String, setting: ReminderSetting, onChange: @escaping (ReminderSetting) -> Void) -> some View {
        let isOnBinding = Binding<Bool>(
            get: { setting.isEnabled },
            set: { newValue in
                if newValue {
                    Task {
                        await environment.requestNotificationPermissionIfNeeded()
                        await refreshStatus()
                    }
                }
                onChange(ReminderSetting(isEnabled: newValue, hour: setting.hour, minute: setting.minute))
            }
        )
        let timeBinding = Binding<Date>(
            get: { Self.date(hour: setting.hour, minute: setting.minute) },
            set: { newDate in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                onChange(ReminderSetting(isEnabled: setting.isEnabled, hour: comps.hour ?? setting.hour, minute: comps.minute ?? setting.minute))
            }
        )

        Toggle(title, isOn: isOnBinding)
        if setting.isEnabled {
            DatePicker("Time", selection: timeBinding, displayedComponents: .hourAndMinute)
        }
    }

    /// Same on/off + one-value shape as `reminderRow` above, but the value
    /// is "minutes before the boundary" rather than a clock time -- the
    /// boundary itself is the daily fasting window set in Settings → Fasting
    /// (redesign-fasting-schedule), so a `Stepper` instead of a
    /// `DatePicker`.
    @ViewBuilder
    private func fastingReminderRow(title: String, setting: FastingReminderSetting, onChange: @escaping (FastingReminderSetting) -> Void) -> some View {
        let isOnBinding = Binding<Bool>(
            get: { setting.isEnabled },
            set: { newValue in
                if newValue {
                    Task {
                        await environment.requestNotificationPermissionIfNeeded()
                        await refreshStatus()
                    }
                }
                onChange(FastingReminderSetting(isEnabled: newValue, minutesBefore: setting.minutesBefore))
            }
        )
        let minutesBinding = Binding<Double>(
            get: { Double(setting.minutesBefore) },
            set: { newValue in
                onChange(FastingReminderSetting(isEnabled: setting.isEnabled, minutesBefore: Int(newValue)))
            }
        )

        Toggle(title, isOn: isOnBinding)
        if setting.isEnabled {
            Stepper("\(setting.minutesBefore) minutes before", value: minutesBinding, in: 5...60, step: 5)
        }
    }

    private var fastingFooter: String {
        guard let schedule = environment.preferences.activeFastingSchedule else {
            return String(localized: "Turn on a daily fasting window in Settings → Fasting first; these only fire while it's on.")
        }
        let start = FastingFormat.clock(FastingFormat.date(minuteOfDay: schedule.startMinute))
        let end = FastingFormat.clock(FastingFormat.date(minuteOfDay: schedule.endMinute))
        return String(localized: "Every day, before your fast ends at \(end) and before it starts at \(start).")
    }

    private func refreshStatus() async {
        authorizationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    private static func date(hour: Int, minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }
}
