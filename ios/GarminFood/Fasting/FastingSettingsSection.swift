// FastingSettingsSection.swift
//
// Settings → Fasting (redesign-fasting-schedule 2.1): an on/off switch,
// "Fast from" / "Fast until" clock times, and the computed "16 h fast ·
// 8 h eating" split. This replaces the old protocol picker + Start/Break/
// End buttons entirely: the window is set once here and repeats daily on
// its own. A window whose start is later than its end (20:00 -> 12:00)
// simply crosses midnight -- `FastingSchedule` handles that, so there's no
// separate "overnight" switch to get wrong.
//
// Its own file (and its own `Section` view) rather than inline in
// SettingsView.swift, so the fasting UI is one self-contained unit that
// SettingsView embeds with a single line -- and that
// `FastingScheduleSettingsView` below can reuse as the "Change schedule"
// destination from the fasting history screen. Values persist through
// `AppPreferences`; every change re-plans the fasting reminders
// (`AppEnvironment.fastingScheduleChanged()`), since those are anchored to
// these exact clock times.

import SwiftUI
import FoodLogCore

@MainActor
struct FastingSettingsSection: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        let preferences = environment.preferences

        Section {
            Toggle("Daily fasting window", isOn: Binding(
                get: { preferences.fastingEnabled },
                set: { newValue in
                    preferences.fastingEnabled = newValue
                    environment.fastingScheduleChanged()
                }
            ))

            if preferences.fastingEnabled {
                DatePicker("Fast from", selection: timeBinding(
                    read: { preferences.fastingStartMinute },
                    write: { preferences.fastingStartMinute = $0 }
                ), displayedComponents: .hourAndMinute)

                DatePicker("Fast until", selection: timeBinding(
                    read: { preferences.fastingEndMinute },
                    write: { preferences.fastingEndMinute = $0 }
                ), displayedComponents: .hourAndMinute)

                HStack {
                    Text("Each day")
                    Spacer()
                    if let schedule = preferences.fastingSchedule {
                        Text(FastingFormat.split(schedule))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Pick two different times")
                            .foregroundStyle(Theme.warning)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        } header: {
            Text("Fasting")
        } footer: {
            Text(footerText(preferences))
        }
    }

    private func footerText(_ preferences: AppPreferences) -> String {
        guard preferences.fastingEnabled else {
            return "Set a fasting window that repeats every day. The home screen shows where you are in it."
        }
        guard let schedule = preferences.fastingSchedule else {
            return "Start and end can't be the same time."
        }
        if schedule.crossesMidnight {
            return "Runs overnight, from \(FastingFormat.clock(FastingFormat.date(minuteOfDay: schedule.startMinute))) until \(FastingFormat.clock(FastingFormat.date(minuteOfDay: schedule.endMinute))) the next day. Logging food inside it shows a gentle note but never blocks."
        }
        return "Logging food inside the window shows a gentle note but never blocks."
    }

    private func timeBinding(read: @escaping () -> Int, write: @escaping (Int) -> Void) -> Binding<Date> {
        Binding(
            get: { FastingFormat.date(minuteOfDay: read()) },
            set: { newDate in
                write(FastingFormat.minuteOfDay(from: newDate))
                environment.fastingScheduleChanged()
            }
        )
    }
}

/// The fasting section on its own screen -- the history screen's "Change
/// schedule" destination, so adjusting the window doesn't mean backing out
/// to Profile → Settings.
@MainActor
struct FastingScheduleSettingsView: View {
    var body: some View {
        Form {
            FastingSettingsSection()
        }
        .navigationTitle("Fasting schedule")
        .navigationBarTitleDisplayMode(.inline)
    }
}
