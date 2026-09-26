## 1. Domain (FoodLogCore)

- [x] 1.1 Add `FastingSchedule`: start and end as minutes-of-day, `crossesMidnight`, `phase(at:calendar:)`, and `window(containing:)` / `window(forFastEndingOn:)`. Tests: same-day window, overnight window, both DST transition days, and exact boundaries.
- [x] 1.2 Add `FastingDayEvaluator.evaluate(window:logTimestamps:)` → kept/broken(at:), and `keptStreak(days:)`. Tests.
- [x] 1.3 Migration: a one-time read of `fasting-sessions.json`. If a last protocol exists, seed the schedule, e.g. 16:8 ending at the last `fastingEndedAt` time-of-day; otherwise use 20:00–12:00. Mark it migrated. Tests.

## 2. App

- [x] 2.1 Settings → Fasting section: toggle, two time pickers, and the computed hours label. Store in `AppPreferences`.
- [x] 2.2 `FastingHomeCard` on `TodayView`, driven by `TimelineView(.periodic(by: 60))`, with a progress ring and phase copy. Tapping opens `FastingHistoryView`.
- [x] 2.3 `FastingHistoryView`: the last 30 days kept/broken, and the streak. It reads the day logs already loaded or cached.
- [x] 2.4 Warning note in `LogEntryConfirmView` and `MealPresetConfirmView` when the log time falls inside the window.
- [x] 2.5 `NotificationPlanning`: plan "fast ends soon" and optionally "fast starts in 15 min" from the schedule. Update `NotificationSettingsView`.
- [x] 2.6 Remove the manual session UI, the protocol picker, the Profile Fasting row, and the `AppEnvironment` start/break/end methods.

## 3. Verify

- [x] 3.1 CI green. *Ticked 2026-09-26: merged to `main`, whose `Build iOS app` CI (package tests + app/widget build) is green (run on 0de2d46).*
- [ ] 3.2 On device:
  - Set 20:00–12:00.
  - The home card is correct morning and evening.
  - The warning shows when logging at 09:00.
  - Tomorrow the day shows as kept or broken.
