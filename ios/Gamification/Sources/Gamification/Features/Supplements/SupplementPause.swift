// SupplementPause.swift
//
// add-supplements D9/D10: "when disabled ... the streak is frozen in place
// (it is neither lost nor extended)". The digest can't tell a day the
// owner skipped from a day the feature was switched off, so the feature
// records it (SupplementsStore): the first run that sees the digest
// inactive (off, or no product in the stack) stores `inactiveSince`; the
// first run that sees it active again closes the pause as a range ending
// yesterday. `apply` then reads every paused day that isn't stack complete
// as neutral -- it neither counts nor breaks the streak, and the shared
// freeze planner never spends a freeze on it.
//
// Runs are not daily (only while the app is used), so a pause starts on
// the first day a run saw the feature off; a day before that still counts
// as it was. Ranges older than the digest window are pruned.
//
// Pure: state and digest in, state and digest out.
//
// Depends on: FoodLogCore (SupplementSignals, SupplementDate),
// SupplementsState. Depended on by: SupplementsFeature.prepare.
// Tests: SupplementStreakTests.

import Foundation
import FoodLogCore

enum SupplementPause {
    /// Ranges ending more than this many days ago are dropped (the digest
    /// looks back 365 days).
    static let keptDays = 400

    /// Updates the pause bookkeeping for a run on `today`; `true` when the
    /// state changed (and must be saved).
    static func record(isActive: Bool, today: String, state: inout SupplementsState) -> Bool {
        if !isActive {
            guard state.inactiveSince == nil else { return false }
            state.inactiveSince = today
            return true
        }
        guard let since = state.inactiveSince else { return false }
        state.inactiveSince = nil
        var ranges = state.pausedRanges ?? []
        if let yesterday = SupplementDate.adding(-1, to: today), since <= yesterday {
            ranges.append(SupplementPausedRange(from: since, through: yesterday))
        }
        if let cutoff = SupplementDate.adding(-keptDays, to: today) {
            ranges.removeAll { ($0.through ?? "") < cutoff }
        }
        state.pausedRanges = ranges
        return true
    }

    /// Whether `day` falls in a pause (closed, or still open).
    static func isPaused(_ day: String, state: SupplementsState) -> Bool {
        if let since = state.inactiveSince, day >= since { return true }
        return (state.pausedRanges ?? []).contains { $0.contains(day) }
    }

    /// `signals` with every paused, not-complete day read as neutral.
    static func apply(_ state: SupplementsState, to signals: SupplementSignals) -> SupplementSignals {
        guard state.inactiveSince != nil || !(state.pausedRanges ?? []).isEmpty else { return signals }
        let days = signals.days.map { day -> SupplementDaySignal in
            guard day.status != .complete, day.status != .neutral, isPaused(day.day, state: state) else { return day }
            return SupplementDaySignal(
                day: day.day,
                status: .neutral,
                plannedCount: day.plannedCount,
                takenCount: day.takenCount,
                ingredients: day.ingredients,
                grantsXP: day.grantsXP,
                slotMinutes: day.slotMinutes
            )
        }
        return SupplementSignals(
            isEnabled: signals.isEnabled,
            hasPlan: signals.hasPlan,
            today: signals.today,
            days: days,
            refillsBeforeEmpty: signals.refillsBeforeEmpty,
            frozenDays: signals.frozenDays
        )
    }
}
