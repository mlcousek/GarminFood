// FastingSchedule.swift
//
// The daily fasting window (redesign-fasting-schedule, owner decision
// 2026-09-23). Replaces the manual start/break/end `FastingSession` flow
// (FastingSession.swift, now retired except for a one-time migration read):
// the owner sets "fast from HH:MM until HH:MM" once, and the window repeats
// every day on its own. Nothing here is ever persisted as a session -- the
// schedule is two minutes-of-day, and every concrete window, phase and
// kept/broken verdict is DERIVED from it plus the wall clock plus the food
// log's own timestamps. Purely local, no Garmin route involved (Garmin has
// no fasting concept at all -- see FastingSession.swift's header).
//
// Why minutes-of-day and wall-clock math rather than "start + N hours":
// a 20:00 -> 12:00 window must start at 20:00 and end at 12:00 on the
// clock every day, including the two Europe/Prague DST nights where the
// same window is actually 15 h (spring) or 17 h (autumn) long. Every
// concrete moment is therefore built with `Calendar.date(bySettingHour:...)`
// on the relevant calendar day (never by adding seconds to a start), and
// every function takes an explicit `Calendar` so the tests can pin
// `TimeZone(identifier: "Europe/Prague")` instead of depending on the CI
// runner's zone. A skipped wall-clock time (02:30 on the spring-forward
// day) resolves to the next existing moment (`.nextTime`); a repeated one
// (02:30 on the fall-back day) resolves to its first occurrence.
//
// A window is identified by the calendar day it ENDS on
// (`window(forFastEndingOn:)`): for an overnight 20:00 -> 12:00 schedule
// "Wednesday's fast" is Tue 20:00 -> Wed 12:00, the fast you break at
// Wednesday lunch. `FastingDayEvaluator` judges each such window kept or
// broken from food-log timestamps (`FastingLogMoments` turns the app's
// usage history / cached Garmin day logs into those timestamps).
//
// Depended on by: the app's `FastingHomeCard`, `FastingHistoryView`,
// `FastingSettingsSection`, the confirm screens' fasting note, and
// `NotificationPlanning.planFastingReminders`. `FastingPhase`/
// `FastingPhaseKind` moved here from FastingSession.swift unchanged, since
// they describe "fasting vs eating right now" and are now derived from a
// schedule instead of a session.

import Foundation

// MARK: - Phase

public enum FastingPhaseKind: Sendable, Equatable {
    case fasting
    case eating
}

/// The phase in effect at a given moment -- always derived, never stored.
/// `scheduledEndAt` is when this phase flips to the other one.
public struct FastingPhase: Sendable, Equatable {
    public let kind: FastingPhaseKind
    public let startedAt: Date
    public let scheduledEndAt: Date

    public init(kind: FastingPhaseKind, startedAt: Date, scheduledEndAt: Date) {
        self.kind = kind
        self.startedAt = startedAt
        self.scheduledEndAt = scheduledEndAt
    }

    public var duration: TimeInterval { scheduledEndAt.timeIntervalSince(startedAt) }

    public func elapsed(at now: Date) -> TimeInterval { max(0, now.timeIntervalSince(startedAt)) }

    /// Can go negative once `isOverdue(at:)` is true.
    public func remaining(at now: Date) -> TimeInterval { scheduledEndAt.timeIntervalSince(now) }

    public func isOverdue(at now: Date) -> Bool { now > scheduledEndAt }

    /// 0...1, clamped -- straight into `ProgressRing.fraction`.
    public func fraction(at now: Date) -> Double {
        guard duration > 0 else { return 0 }
        return min(max(elapsed(at: now) / duration, 0), 1)
    }
}

// MARK: - Window

/// One concrete fasting window: `[start, end)` in absolute time.
public struct FastingWindow: Sendable, Equatable, Hashable {
    public let start: Date
    public let end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }

    public var duration: TimeInterval { end.timeIntervalSince(start) }

    /// Half-open: the first instant of `start` is inside, the instant of
    /// `end` is already the eating window -- so a food logged at exactly
    /// 12:00 on a fast "until 12:00" is fine.
    public func contains(_ date: Date) -> Bool {
        date >= start && date < end
    }
}

// MARK: - Schedule

public struct FastingSchedule: Sendable, Equatable, Hashable {
    public static let minutesPerDay = 24 * 60

    /// Minute of the day the fast begins, `0..<1440`.
    public let startMinute: Int
    /// Minute of the day the fast ends (eating opens), `0..<1440`.
    public let endMinute: Int

    /// `nil` when start and end are the same clock time (after wrapping
    /// into `0..<1440`) -- that's either a zero-length or a 24 h fast,
    /// neither of which is a meaningful daily window, so it's rejected at
    /// construction rather than special-cased in every function below.
    public init?(startMinute: Int, endMinute: Int) {
        let start = Self.normalized(startMinute)
        let end = Self.normalized(endMinute)
        guard start != end else { return nil }
        self.startMinute = start
        self.endMinute = end
    }

    private init(validStartMinute: Int, validEndMinute: Int) {
        self.startMinute = validStartMinute
        self.endMinute = validEndMinute
    }

    /// 20:00 -> 12:00 (16:8), the fallback when there's nothing to migrate
    /// from (redesign-fasting-schedule task 1.3).
    public static let standard = FastingSchedule(validStartMinute: 20 * 60, validEndMinute: 12 * 60)

    public static func normalized(_ minute: Int) -> Int {
        ((minute % minutesPerDay) + minutesPerDay) % minutesPerDay
    }

    /// True when the fast starts on one calendar day and ends on the next
    /// (e.g. 20:00 -> 12:00).
    public var crossesMidnight: Bool { startMinute > endMinute }

    /// Nominal fasting length in minutes, as the settings label shows it.
    /// The real length differs by an hour on DST nights (see
    /// `FastingWindow.duration`).
    public var fastingMinutes: Int {
        Self.normalized(endMinute - startMinute)
    }

    public var eatingMinutes: Int {
        Self.minutesPerDay - fastingMinutes
    }

    // MARK: Concrete windows

    /// The window that STARTS on the calendar day containing `day`.
    public func window(startingOn day: Date, calendar: Calendar) -> FastingWindow? {
        let dayStart = calendar.startOfDay(for: day)
        guard let start = Self.moment(minuteOfDay: startMinute, onDayStarting: dayStart, calendar: calendar) else { return nil }
        let endDayStart: Date
        if crossesMidnight {
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return nil }
            endDayStart = calendar.startOfDay(for: nextDay)
        } else {
            endDayStart = dayStart
        }
        guard let end = Self.moment(minuteOfDay: endMinute, onDayStarting: endDayStart, calendar: calendar),
              end > start
        else { return nil }
        return FastingWindow(start: start, end: end)
    }

    /// The window that ENDS on the calendar day containing `day` -- "that
    /// day's fast", the unit `FastingDayEvaluator` judges and the history
    /// screen lists.
    public func window(forFastEndingOn day: Date, calendar: Calendar) -> FastingWindow? {
        let dayStart = calendar.startOfDay(for: day)
        guard crossesMidnight else { return window(startingOn: dayStart, calendar: calendar) }
        guard let previousDay = calendar.date(byAdding: .day, value: -1, to: dayStart) else { return nil }
        return window(startingOn: previousDay, calendar: calendar)
    }

    /// The window `date` falls inside, or `nil` when `date` is in the
    /// eating window.
    public func window(containing date: Date, calendar: Calendar) -> FastingWindow? {
        windows(around: date, calendar: calendar).first { $0.contains(date) }
    }

    /// Fasting or eating at `date`, with that phase's own start and end.
    /// `nil` only if the calendar can't produce the surrounding windows
    /// (not expected for any real time zone).
    public func phase(at date: Date, calendar: Calendar) -> FastingPhase? {
        let around = windows(around: date, calendar: calendar)
        if let current = around.first(where: { $0.contains(date) }) {
            return FastingPhase(kind: .fasting, startedAt: current.start, scheduledEndAt: current.end)
        }
        guard let previous = around.last(where: { $0.end <= date }),
              let next = around.first(where: { $0.start > date })
        else { return nil }
        return FastingPhase(kind: .eating, startedAt: previous.end, scheduledEndAt: next.start)
    }

    /// The fast that would be broken by logging food for `day` right now,
    /// if any: the end of the window `now` falls inside -- the confirm
    /// screens' "You're fasting until 12:00" note. Uses the same "which
    /// logs count as eating" rule as the history screen
    /// (`FastingLogMoments.countsAsEating`), so the note appears exactly
    /// when the log would later mark the day broken, and not for a
    /// back-filled entry for some other day.
    public func fastEndIfLogging(at now: Date, forDay day: Date, calendar: Calendar) -> Date? {
        guard let window = window(containing: now, calendar: calendar) else { return nil }
        let nutritionDay = NutritionDate.string(from: day, calendar: calendar)
        guard FastingLogMoments.countsAsEating(timestamp: now, nutritionDay: nutritionDay, calendar: calendar) else { return nil }
        return window.end
    }

    /// Windows starting yesterday, today and tomorrow (relative to `date`),
    /// sorted by start. Enough to answer any "now" question: a window is
    /// under 24 h long, so whatever contains `date`, ended just before it,
    /// or starts just after it is among these three.
    private func windows(around date: Date, calendar: Calendar) -> [FastingWindow] {
        let dayStart = calendar.startOfDay(for: date)
        return (-1...1).compactMap { offset -> FastingWindow? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: dayStart) else { return nil }
            return window(startingOn: day, calendar: calendar)
        }
        .sorted { $0.start < $1.start }
    }

    /// Wall-clock `minuteOfDay` on the day beginning at `dayStart`.
    /// `.nextTime` / `.first` pin down what the DST edge cases resolve to
    /// (see file header) instead of leaving it to the defaults.
    static func moment(minuteOfDay: Int, onDayStarting dayStart: Date, calendar: Calendar) -> Date? {
        calendar.date(
            bySettingHour: minuteOfDay / 60,
            minute: minuteOfDay % 60,
            second: 0,
            of: dayStart,
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        )
    }
}

// MARK: - Daily verdict

public enum FastingDayResult: Sendable, Equatable {
    /// The window is over and nothing was logged inside it.
    case kept
    /// Food was logged inside the window; `at` is the first such log.
    /// Can be reported while the window is still running -- once broken,
    /// it stays broken.
    case broken(at: Date)
    /// The window is running and nothing has been logged in it yet.
    case inProgress
    /// The window hasn't started yet (a same-day schedule, early in the
    /// morning).
    case upcoming
    /// The window started before fasting was switched on, or before the
    /// earliest moment the log data is known to be complete -- judging it
    /// either way would be a guess.
    case notTracked
}

public struct FastingDay: Sendable, Equatable, Identifiable {
    /// Start of the calendar day this fast ends on.
    public let day: Date
    public let window: FastingWindow
    public let result: FastingDayResult

    public init(day: Date, window: FastingWindow, result: FastingDayResult) {
        self.day = day
        self.window = window
        self.result = result
    }

    public var id: Date { day }
}

public enum FastingDayEvaluator {
    /// Kept or broken for one window. `logTimestamps` can be every eating
    /// moment known (any order, any days) -- only those inside `window`
    /// matter.
    public static func evaluate(window: FastingWindow, logTimestamps: [Date], now: Date) -> FastingDayResult {
        if let firstInside = logTimestamps.filter({ window.contains($0) }).min() {
            return .broken(at: firstInside)
        }
        if now < window.start { return .upcoming }
        if now < window.end { return .inProgress }
        return .kept
    }

    /// The last `days` fasts, newest first -- the one ending today first.
    ///
    /// - Parameter trackedSince: windows STARTING before this are
    ///   `.notTracked` (fasting was off, or the log data doesn't reach back
    ///   that far). `nil` means "track everything".
    public static func history(
        schedule: FastingSchedule,
        days: Int,
        logTimestamps: [Date],
        trackedSince: Date?,
        now: Date,
        calendar: Calendar
    ) -> [FastingDay] {
        guard days > 0 else { return [] }
        let today = calendar.startOfDay(for: now)
        return (0..<days).compactMap { offset -> FastingDay? in
            guard let dayDate = calendar.date(byAdding: .day, value: -offset, to: today),
                  let window = schedule.window(forFastEndingOn: dayDate, calendar: calendar)
            else { return nil }
            let day = calendar.startOfDay(for: dayDate)
            if let trackedSince, window.start < trackedSince {
                return FastingDay(day: day, window: window, result: .notTracked)
            }
            return FastingDay(day: day, window: window, result: evaluate(window: window, logTimestamps: logTimestamps, now: now))
        }
    }

    /// Consecutive kept days, counting back from the most recent. A fast
    /// still running (or not started) is skipped rather than counted or
    /// treated as a break -- it can't be judged yet -- but one already
    /// broken ends the streak immediately (spec: "that day is marked broken
    /// and the kept-days streak resets to 0"). An untracked day ends it
    /// too: a streak never reaches back past what the data can vouch for.
    public static func keptStreak(days: [FastingDay]) -> Int {
        var streak = 0
        for fastingDay in days.sorted(by: { $0.day > $1.day }) {
            switch fastingDay.result {
            case .inProgress, .upcoming:
                continue
            case .kept:
                streak += 1
            case .broken, .notTracked:
                return streak
            }
        }
        return streak
    }
}
