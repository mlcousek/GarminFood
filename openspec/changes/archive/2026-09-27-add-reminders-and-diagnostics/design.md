## Context

Local notifications have one structural limitation this design has to work around: a `UNNotificationRequest` cannot ask "has this already happened?" at fire time — that hook (`UNNotificationServiceExtension`) only exists for remote/push notifications, which this project doesn't have. Diagnostics logging has no such limitation, but this project's own "no Mac" constraint means the log has to be readable entirely on-device, with no external tooling.

## Decisions

### D1 — Replan-and-diff instead of a fire-and-forget schedule

Each reminder is decided fresh by `FoodLogCore.NotificationPlanning.plan(...)` (pure) every time `AppEnvironment.syncNotifications()` runs (foreground, right after a confirm, and after a reminder setting changes). The app layer's `NotificationScheduler` diffs that plan against what's actually pending in `UNUserNotificationCenter` and adds/removes to match — the same "replan and reconcile" shape `Outbox`/`Reconciliation` already use for Garmin delivery, applied here instead of a single set-and-forget schedule. This is what lets a meal reminder correctly stop firing the moment that meal is logged, without any push infrastructure.

### D2 — Each reminder is a single, date-scoped request, not a repeating one

A naive `repeats: true` `UNCalendarNotificationTrigger` can't be selectively suppressed for "just today" without cancelling (and later re-adding) the whole repeating series. Instead, every planned notification becomes a one-time request for TODAY only, identified as `reminder.<kind>.<yyyy-MM-dd>`. Tomorrow's instance doesn't exist until tomorrow's replan creates it — which happens on the next foreground, which happens whenever the app is actually opened (i.e., in practice, daily for anyone using it).

### D3 — `NotificationPlanning` takes plain booleans, not `Gamification` types

`Gamification` already depends on `FoodLogCore` (its own `Package.swift`), so `FoodLogCore` importing `Gamification` back would be circular. `isStreakAtRiskToday` is computed once by the app layer (which already depends on both) from `GamificationEngine.streakStatus.isAtRiskToday` and passed in as a `Bool` — the planner itself has zero knowledge of streaks as a concept, just "is this one reminder's condition true."

### D4 — Diagnostics logging lives in GarminKit, at two central choke points

Rather than adding a log call at every one of GarminClient's ~15 route methods, logging is added once in `perform` (network-level failures) and once in `throwIfNotSuccessful` (HTTP error responses) — both already called by every route. `Outbox.drain` adds one summary log per drain cycle. The app layer adds a handful more at confirm-screen `catch` blocks, where the user-facing message is necessarily generic but the real error is worth keeping. This covers the overwhelming majority of "something silently went wrong" scenarios without touching every call site.

### D5 — The diagnostics log is local-only, capped, and user-clearable

No remote destination, no third-party SDK (would need a paid account or an opaque network dependency neither of which fits this project's constraints). Capped at 500 entries (oldest dropped first) so it can't grow unbounded on a device that's never manually cleared. A "Copy all" action puts the whole log on the system pasteboard as plain text — the user decides where it goes from there (e.g. pasting it into a chat), rather than this project picking a destination for them.

## Risks / Trade-offs

- **A reminder scheduled today at 8am won't fire if the user enables it at 10am** (D2's accepted behavior for `UNTimeIntervalNotificationTrigger` fired against a past time) → by design; it fires the next day instead, same as any calendar-based daily reminder.
- **The diagnostics log won't capture a crash** (only errors the app itself catches and logs) → true, and out of scope; a hard crash needs a crash reporter (explicitly a non-goal here, see proposal.md).
- **Background app refresh is best-effort** (`BackgroundRefresh.swift`'s own existing caveat) → `syncNotifications()` is NOT hooked into the background refresh task; it only runs on foreground/log/setting-change. Accepted: reminders self-heal on the next time the app is actually opened, which is inherent to how the person would see a reminder anyway.
