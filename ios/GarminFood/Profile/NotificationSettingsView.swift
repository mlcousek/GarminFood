// NotificationSettingsView.swift
//
// Reminder settings: a toggle + time picker per reminder (breakfast, lunch,
// dinner, streak-at-risk, today's challenges), plus a toggle + minutes-before
// stepper for the fasting-window reminder (2026-09-22 -- see
// `FastingReminderSetting`'s header for why that one's a stepper, not a time
// picker). Turning any one of these on for the first time requests
// notification permission; a denied/off system setting is shown plainly
// with a link to fix it in Settings, per this project's existing
// loud-failure convention (never a reminder that's silently never going to
// fire).

import SwiftUI
import UIKit
import UserNotifications
import FoodLogCore

@MainActor
struct NotificationSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        Form {
            if authorizationStatus == .denied {
                Section {
                    Label("Notifications are off for GarminFood in iOS Settings, so reminders below won't fire.", systemImage: "bell.slash")
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
                    title: "Breakfast",
                    setting: environment.notificationPreferences.preferences.breakfastReminder,
                    onChange: { environment.setBreakfastReminder($0) }
                )
                reminderRow(
                    title: "Lunch",
                    setting: environment.notificationPreferences.preferences.lunchReminder,
                    onChange: { environment.setLunchReminder($0) }
                )
                reminderRow(
                    title: "Dinner",
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
                    title: "Streak at risk",
                    setting: environment.notificationPreferences.preferences.streakReminder,
                    onChange: { environment.setStreakReminder($0) }
                )
            } footer: {
                Text("Only fires on a day you haven't logged anything yet, if you have a streak to lose.")
            }

            Section {
                reminderRow(
                    title: "Today's challenges",
                    setting: environment.notificationPreferences.preferences.dailyChallengeReminder,
                    onChange: { environment.setDailyChallengeReminder($0) }
                )
            } footer: {
                Text("A daily nudge to check today's challenges.")
            }

            Section {
                fastingReminderRow
            } footer: {
                Text("Reminds you shortly before your current fasting or eating window ends. Only fires while a fast is running.")
            }
        }
        .navigationTitle("Reminders")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refreshStatus() }
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
    /// is "minutes before the window ends" rather than a clock time, since
    /// `FastingReminderSetting` has no hour/minute (see its header) -- a
    /// `Stepper` instead of `reminderRow`'s `DatePicker`.
    @ViewBuilder
    private var fastingReminderRow: some View {
        let setting = environment.notificationPreferences.preferences.fastingReminder
        let isOnBinding = Binding<Bool>(
            get: { setting.isEnabled },
            set: { newValue in
                if newValue {
                    Task {
                        await environment.requestNotificationPermissionIfNeeded()
                        await refreshStatus()
                    }
                }
                environment.setFastingReminder(FastingReminderSetting(isEnabled: newValue, minutesBefore: setting.minutesBefore))
            }
        )
        let minutesBinding = Binding<Double>(
            get: { Double(setting.minutesBefore) },
            set: { newValue in
                environment.setFastingReminder(FastingReminderSetting(isEnabled: setting.isEnabled, minutesBefore: Int(newValue)))
            }
        )

        Toggle("Fasting window ending soon", isOn: isOnBinding)
        if setting.isEnabled {
            Stepper("\(setting.minutesBefore) minutes before", value: minutesBinding, in: 5...60, step: 5)
        }
    }

    private func refreshStatus() async {
        authorizationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    private static func date(hour: Int, minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }
}
