// FastingScheduleMigration.swift
//
// The one-time bridge from the retired manual fasting flow
// (FastingSession.swift, `fasting-sessions.json`) to the daily
// `FastingSchedule` (redesign-fasting-schedule task 1.3). Pure: the app
// reads the legacy file once through the now read-only
// `FastingSessionStore`, hands the sessions to `seed(...)`, stores the
// result in its preferences and records that the migration ran -- the file
// itself is left on disk untouched and never read again.
//
// The rule: if the owner ever used the old flow, keep the protocol they
// used last and anchor it on the time of day they last actually broke
// their fast (e.g. 16:8 last broken at 12:00 -> 20:00-12:00), and switch
// fasting on, since they were already using it. With no history at all,
// fall back to `FastingSchedule.standard` (20:00-12:00) and leave fasting
// off -- turning on a home-screen card nobody asked for would be a
// surprise, not a migration.

import Foundation

public enum FastingScheduleMigration {
    public struct Seed: Sendable, Equatable {
        public let schedule: FastingSchedule
        public let isEnabled: Bool

        public init(schedule: FastingSchedule, isEnabled: Bool) {
            self.schedule = schedule
            self.isEnabled = isEnabled
        }
    }

    public static func seed(active: FastingSession?, history: [FastingSession], calendar: Calendar) -> Seed {
        var sessions = history
        if let active { sessions.append(active) }
        guard let last = sessions.max(by: { $0.startedAt < $1.startedAt }) else {
            return Seed(schedule: .standard, isEnabled: false)
        }

        let fastingMinutes = Int((last.protocolKind.fastingHours * 60).rounded())
        guard fastingMinutes > 0, fastingMinutes < FastingSchedule.minutesPerDay else {
            // A `.custom` protocol with a nonsensical length -- keep the
            // user's intent (fasting on) with the default window.
            return Seed(schedule: .standard, isEnabled: true)
        }

        // The real break time when there is one; otherwise (a fast still
        // running when the app updated) where the protocol said it would end.
        let endMoment = last.fastingEndedAt ?? last.startedAt.addingTimeInterval(Double(fastingMinutes) * 60)
        let components = calendar.dateComponents([.hour, .minute], from: endMoment)
        let endMinute = (components.hour ?? 12) * 60 + (components.minute ?? 0)

        guard let schedule = FastingSchedule(startMinute: endMinute - fastingMinutes, endMinute: endMinute) else {
            return Seed(schedule: .standard, isEnabled: true)
        }
        return Seed(schedule: schedule, isEnabled: true)
    }
}
