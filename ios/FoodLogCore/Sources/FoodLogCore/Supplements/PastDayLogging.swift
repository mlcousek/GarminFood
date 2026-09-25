// PastDayLogging.swift
//
// Logging intake for past days (add-supplements D14, owner request
// 2026-09-25: "yesterday, a week ago, a month ago").
//
//   - Any day from today - 365 days through today can be filled in or
//     corrected; future days can't. The date picker uses
//     `earliestEditableDay`, and `SupplementIntakeStore` enforces
//     `editability` on every write, so a stale screen can't slip past it.
//   - A past day's checklist is evaluated against the schedule in effect
//     THAT day (`PlanItem` history, D3) -- nothing extra is needed here.
//   - Stock: only intake on/after `stockSetOn` drains the current pack
//     (`StockProjection`), so backfilling a day before it changes nothing.
//   - XP: to keep the levelling pace and stop history farming, a record
//     written more than 7 days after its day still counts for history,
//     streaks, badges and statistics but grants no XP (wave 6 applies it).
//     Grants are keyed by day, so re-entering a day never pays twice.
//
// Depended on by: SupplementIntakeStore (write guard), the supplements
// screen's date picker (wave 3), the gamification digest (wave 6).
// Tests: PastDayLoggingTests.

import Foundation

public enum PastDayLogging {
    /// How far back a day can be edited.
    public static let maxDaysBack = 365
    /// A record written more than this many days after its day grants no XP.
    public static let xpGraceDays = 7

    public enum Editability: Sendable, Equatable {
        case editable
        case future
        case tooFarBack
        case invalidDay
    }

    /// Whether intake for `day` can be recorded on `today`.
    public static func editability(of day: String, today: String) -> Editability {
        guard let target = SupplementDate.ordinal(day), let now = SupplementDate.ordinal(today) else { return .invalidDay }
        if target > now { return .future }
        if now - target > maxDaysBack { return .tooFarBack }
        return .editable
    }

    /// The oldest day the picker offers (today - 365 days).
    public static func earliestEditableDay(today: String) -> String? {
        SupplementDate.adding(-maxDaysBack, to: today)
    }

    /// Whether a record for `day` written on `recordedOn` may grant XP.
    public static func grantsXP(day: String, recordedOn: String) -> Bool {
        guard let delay = SupplementDate.daysBetween(day, recordedOn) else { return false }
        return delay <= xpGraceDays
    }

    /// `grantsXP(day:recordedOn:)` for a stored record. A record without
    /// `recordedOn` (none are written that way) counts as on time.
    public static func grantsXP(_ record: IntakeRecord) -> Bool {
        grantsXP(day: record.day, recordedOn: record.recordedOn ?? record.day)
    }
}
