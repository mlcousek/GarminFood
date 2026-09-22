## Why

Two unrelated-but-cheap gaps, both raised directly by the owner:

1. **No reminders.** The app has a genuinely deep engagement layer (streaks, levels, 226 challenge templates, 122 achievements) but nothing ever nudges the user to actually open it — no "you haven't logged dinner," no "your streak is at risk tonight." That's a lot of investment in habit mechanics with no habit trigger.
2. **No way to see what went wrong on a real device.** This project has no Mac (openspec/config.yaml's hard constraint): no Console.app, no attached debugger. When something breaks, the only recourse today is the owner re-describing symptoms from memory. Every confirm screen's error path already collapses to a generic "couldn't save, try again" — the real underlying error has never been kept anywhere.

Both are implementable entirely within the free-tier constraint: local (not push) notifications need no paid capability, and an in-app diagnostics log needs no App Group or special entitlement — it is genuinely local to each process's own sandbox, same as `Outbox`'s existing JSON-file store.

## What Changes

- Add **reminder notifications**: per-meal (breakfast/lunch/dinner) reminders that only fire if that meal hasn't been logged yet that day, a streak-at-risk reminder that only fires when there's a real streak to lose, and a daily "today's challenges are ready" nudge — each independently toggleable with its own time, in a new Settings screen.
- Add a **persistent, in-app diagnostics log**: every Garmin API failure, every outbox delivery outcome, and every confirm-screen error is recorded (in addition to the generic message already shown to the user), viewable and copyable from a new Settings screen — the "there is no Mac" gap, closed.

## Capabilities

### New Capabilities

- `reminder-notifications` — configurable local reminders for meals, streak risk, and daily challenges.
- `diagnostics-log` — a persistent, in-app-visible, shareable log of what actually happened.

## Non-goals

- **Push notifications.** Everything here is a local `UNUserNotificationCenter` schedule; there is no server component and none is added. (Push would also require the paid-tier APNs capability this project has explicitly declined — see openspec/config.yaml.)
- **Remote crash reporting / analytics (Crashlytics, Sentry, etc.)** Those require either a paid third-party service account or, for some, capabilities this free-tier setup doesn't have. The diagnostics log is local-only, by design, matching this project's existing "no App Group, no paid tier" posture.
- **Server-conditioned or push-triggered reminders** (e.g. "remind me based on what I usually eat"). Every reminder here is a fixed, user-set time; smarter timing is a possible future refinement, not built now.
- **A remote log viewer or export destination.** The diagnostics screen has a "Copy all" action (system pasteboard) so the log can be pasted anywhere the user chooses; no built-in upload/share-to-a-service integration is added.

## Impact

Affected surfaces: `FoodLogCore` gains `NotificationPlanning.swift` (pure); `GarminKit` gains `DiagnosticsLog.swift` (used by `GarminClient`/`Outbox` internally) and two new logging call sites inside `GarminClient.perform`/`throwIfNotSuccessful`, plus one summary log per `Outbox.drain`; the `GarminFood` app target gains `NotificationPreferencesStore`, `NotificationScheduler`, `NotificationSettingsView`, `DiagnosticsLogView`, two new `SettingsView` rows, and a handful of `DiagnosticsLog.log(...)` calls at existing confirm-screen error sites. No changes to any Garmin write contract, no new entitlements, no new Info.plist keys.

**Depends on**: `add-food-log-core` (meal-logged-today state, meal types) and `add-gamification` (streak-at-risk state, consumed as a plain boolean the app layer computes — see design.md).

**Unblocks**: nothing further planned.
