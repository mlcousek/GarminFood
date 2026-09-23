## Why

The owner doesn't like the current fasting feature. Right now it works like
this:

- You pick a protocol (16:8, 18:6, …).
- You tap Start and Break Fast every time.
- It lives behind the Profile tab.
- It only reaches the home screen while a fast is running.

The owner wants something different. In Settings they set "fasting from HH:MM
to HH:MM". The window repeats every day on its own, is visible on the home
screen, and the app works with it.

Decisions from the grilling session (2026-09-23):
- The window is automatic and daily.
- The window is the same every day.
- Logging food during the fast gets a gentle warning.
- The old manual start/stop flow and the protocol picker are removed.

## What Changes

- **Settings.** A new "Fasting" section in Settings:
  - an on/off switch;
  - a "Fast from" time and a "Fast until" time;
  - the window may cross midnight, e.g. 20:00 → 12:00;
  - the fasting and eating hours are shown, e.g. "16 h fast · 8 h eating".
- **Home card.** The home screen shows an always-on fasting card when fasting
  is enabled:
  - While fasting: "Fasting · 11 h 20 m in · eating opens at 12:00", with a
    progress ring.
  - While eating: "Eating window · closes at 20:00 (3 h 10 m)".
  - The card updates live using `TimelineView`, with no timers in state.
- **Warning when logging.** If the user logs food during the fasting window,
  the confirm screen shows a gentle inline note: "You're fasting until
  12:00 — log anyway?". It does not block the log, and it doesn't appear for
  water.
- **Daily result.** Each day's fast is judged automatically:
  - A day counts as **kept** if no food was logged inside that day's window.
  - Otherwise it is marked **broken** at the time of the first log.
  - The existing "N in a row" stat becomes a streak of kept days, computed from
    the food log, with no manual sessions.
- **Reminders.** The "Fasting window ending soon" reminder is re-planned from
  the schedule, and a new optional reminder is added: "Fasting starts in
  15 min".
- **Removed.** `FastingView`'s Start, Break Fast and End buttons, the
  protocol picker, and the Profile → Fasting row are removed.
- **Migration.** The old `fasting-sessions.json` is left on disk. It is read
  once to seed the schedule from the last-used protocol if one exists, then
  ignored.

## Non-goals

- Different windows per weekday. The owner chose the same window every day.
- Syncing fasting to Garmin. Garmin has no fasting API.
- Blocking food logging during a fast. It only warns.

## Capabilities

### New Capabilities

- `fasting-schedule`: daily fasting window, home card, logging warning, and
  kept/broken days.

## Impact

- **FoodLogCore:**
  - New pure `FastingSchedule`: start/end minutes, which handles
    midnight-crossing, plus `phase(at:)`, `window(for day:)`, and
    `evaluate(day:logTimestamps:)` → kept/broken.
  - A kept-days streak.
  - Tests for DST days and midnight-crossing windows.
  - `FastingSession.swift`'s store is retired (migration read only).
- **App:**
  - Settings Fasting section; preferences are stored in `AppPreferences`.
  - A new `FastingHomeCard` on `TodayView`.
  - `LogEntryConfirmView` and `MealPresetConfirmView` get the warning note.
  - `NotificationPlanning` is updated.
  - `Fasting/*` is rewritten as a small detail screen (history of kept/broken
    days), reached from the home card.
- **Depends on**: nothing.
- **Unblocks**: nothing.
