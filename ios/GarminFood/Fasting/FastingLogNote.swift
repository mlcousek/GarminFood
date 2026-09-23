// FastingLogNote.swift
//
// The gentle, non-blocking "You're fasting until 12:00 — log anyway?" note
// on the food confirm screens (redesign-fasting-schedule 2.4: added to
// `LogEntryConfirmView` and `MealPresetConfirmView`, deliberately NOT to the
// water sheet -- water doesn't break a fast). It is only a note: nothing
// here disables the confirm button or adds a step, since the owner chose
// "warn, never block" (proposal.md), and the confirm path must stay
// local-first and instant regardless.
//
// Whether to show it is `FastingSchedule.fastEndIfLogging(at:forDay:)`,
// the same rule the history screen judges with -- so the note appears
// exactly when confirming would later mark today's fast broken, and not
// when back-filling an entry for another day. Its own file so each confirm
// screen only gains one line.

import SwiftUI
import FoodLogCore

@MainActor
struct FastingLogNoteSection: View {
    @Environment(AppEnvironment.self) private var environment

    /// The day the entry is being logged FOR (the confirm screen's date
    /// picker).
    let logDate: Date

    /// Read at render time rather than through a `TimelineView`: a
    /// `TimelineView` wrapped around a `Form` `Section` doesn't reliably lay
    /// out as a section, and a confirm screen is on screen for seconds --
    /// any edit (quantity, date) re-renders it anyway.
    var body: some View {
        if let schedule = environment.preferences.activeFastingSchedule,
           let fastEnd = schedule.fastEndIfLogging(at: Date(), forDay: logDate, calendar: .current) {
            Section {
                Label("You're fasting until \(FastingFormat.clock(fastEnd)) — log anyway?", systemImage: "moon.stars")
                    .font(.footnote)
                    .foregroundStyle(Theme.warning)
            }
        }
    }
}
