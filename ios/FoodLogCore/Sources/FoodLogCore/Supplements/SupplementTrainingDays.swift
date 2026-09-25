// SupplementTrainingDays.swift
//
// Which days count as "training days" for the `.trainingDays` schedule
// pattern (add-supplements D3, task 2.4) -- the `trainingDays` set that
// `ScheduleEvaluator.due(on:plan:trainingDays:)`, `StockProjection` and the
// checklist take as input.
//
// Built only from data this app already has; NO new Garmin route:
//   - `ActivityCacheStore`: the days with at least one Garmin activity, as
//     cached from the confirmed read-only activities route
//     (docs/garmin-routes.json `activitiesSearch`) by
//     `GamificationSignalsSync` on foreground. A day never read
//     (`activities == nil`) or read as empty (`[]`) is not a training day.
//   - `DayNoteStore`: days tagged `race` (add-day-notes), which count in
//     every mode -- a race is a training day even without a watch.
//
// Standalone mode has no Garmin activities, so it uses the race tags only
// (spec "Training days without activity data"); the schedule editor shows a
// hint about that (wave 3). Activity data left in the cache from an earlier
// Garmin period is ignored there, so the rule doesn't depend on history.
//
// Pure `days(...)` for tests; `load(...)` is the one-call convenience the
// app uses. Both are cheap local reads, never a network wait.
//
// Depended on by: the supplements screen, Today card and reminders
// (waves 3-4). Tests: SupplementTrainingDaysTests.

import Foundation

public enum SupplementTrainingDays {
    /// Training days among `activityDays` and `notes`. `includeActivities`
    /// is `false` in standalone mode (race tags only).
    public static func days(activityDays: [DayActivity], notes: [DayNote], includeActivities: Bool) -> Set<String> {
        var result = Set(notes.filter { $0.tags.contains(.race) }.map(\.day))
        if includeActivities {
            for entry in activityDays where !(entry.activities ?? []).isEmpty {
                result.insert(entry.day)
            }
        }
        return result
    }

    /// Reads both stores and returns the training days in
    /// `startDay...endDay` (inclusive, `yyyy-MM-dd`).
    public static func load(
        from startDay: String,
        to endDay: String,
        activityCache: ActivityCacheStore,
        dayNotes: DayNoteStore,
        mode: DataMode
    ) async -> Set<String> {
        let includeActivities = mode != .standalone
        var activityDays: [DayActivity] = []
        if includeActivities {
            activityDays = await activityCache.all()
        }
        let notes = await dayNotes.notes(from: startDay, to: endDay)
        return days(activityDays: activityDays, notes: notes, includeActivities: includeActivities)
            .filter { $0 >= startDay && $0 <= endDay }
    }
}
