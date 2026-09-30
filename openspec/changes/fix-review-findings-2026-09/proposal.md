## Why

An external review and the owner reported sixteen findings (items 1-16 below)
against `main` at e2d871a. Each was checked against the code before anything
was changed. Eight are real and are fixed here; eight are not real in the
current code (most were fixed by earlier changes) and are recorded with the
evidence, so nobody re-opens them.

| # | Sev | Finding | Verdict |
|---|-----|---------|---------|
| 1 | High | Quick Pick / Siri log bypasses `GamificationEngine` | **Real** |
| 2 | High | 2xx custom-food create with an unexpected body shows as failed; retry duplicates | **Real** |
| 3 | Medium | Background scheduling/drain handles only food | **Real, partly** (drain was fixed 2026-09-23; scheduling still read a stale count) |
| 4 | Medium | Weight/water enqueued before the local save; a failed save still syncs | **Real** |
| 5 | High | Deleting a syncing entry orphans it in Garmin | Not real |
| 6 | High | Reconciliation deletes a legitimate later identical entry | Not real |
| 7 | Medium | Quick Pick opens the confirm screen at 1x, not the remembered amount | Not real |
| 8 | Medium | Background reconciliation strands accepted (`.sent`) food entries | **Real** |
| 9 | High | Queued entries of account A are delivered to account B after sign-in | **Real** |
| 10 | Medium | The first enabled reminder may never schedule (permission prompt) | **Real** |
| 11 | Medium | Daily reminders stop after midnight while the app stays closed | **Real** |
| 12 | Medium | Deleting a delivered weigh-in is local-only | Not real |
| 13 | Medium | A cancelled food search overwrites newer results | Not real |
| 14 | Medium | Profile shows a UUID `displayName` over a valid `fullName` | Not real |
| 15 | High | A transiently unreadable JSON store is overwritten as empty | Not real |
| 16 | High | An accepted write is re-sent after a restart when `.sent` wasn't saved | **Real** |

## What Changes

- **1** A quick-pick Control, "Log usual food" and "Log <food>" Siri log now
  reach `GamificationEngine.handleLogConfirmed` -- the same award path as an
  in-app confirm -- exactly once, through FoodLogCore's `ConfirmedLogRelay`
  (held until the app attaches, deduplicated by entry id).
- **2** A 2xx custom-food create is always a create: an unreadable body is
  `.createdDetailsPending` (GarminKit `CustomFoodCreation`), never an error, and
  the create button never re-enables after a 2xx (FoodLogCore
  `CustomFoodCreateGate`). The user is told it exists and to find it in search.
- **3** Leaving the app schedules the background refresh from the outboxes
  themselves (`OutboxBacklog`), not a cached count; the background pass is the
  tested `BackgroundOutboxDelivery` for food, weight and water.
- **4** Weigh-ins and drinks are saved locally first, then enqueued under an id
  chosen up front; a failed save queues nothing, and the stores roll back in
  memory on a failed save.
- **8** The background pass reconciles every `.sent` food entry (not only its
  own deliveries), and an unreconciled `.sent` entry keeps a refresh scheduled.
- **9** Every outbox entry is stamped with the Garmin account it was logged
  under (hashed) and only delivered to that account; another account's entries
  are held, never sent or dropped. Signing out ties unstamped entries to the
  outgoing account.
- **10** Granting the notification prompt re-syncs every reminder.
- **11** Food reminders cover a rolling 7-day window; training reminders a week
  from the cached projection.
- **16** Each outbox saves a send marker before sending; an entry that reloads
  with it set is never blindly re-sent (food -> Reconciliation, weigh-in ->
  looked up first, drink -> failed with a note for the user).

## Capabilities

### New Capabilities

- `garmin-sync`: account-scoped delivery, no blind re-send, background delivery
  of every outbox kind (findings 3, 8, 9, 16).

### Modified Capabilities

- `siri-and-shortcuts` (finding 1), `garmin-food-matching` (2),
  `weight-tracking` and `hydration-tracking` (4), `reminder-notifications`
  (10, 11) -- each gains an ADDED requirement.

## Impact

- GarminKit: `CustomFoodCreation.swift`, `DeliverySafety.swift` (new);
  `Outbox`, `WeightSync`, `HydrationSync`, `Reconciliation`, `GarminClient`.
  Entry files gain two optional fields (`sendStartedAt`, `accountKey`),
  decode-safe both ways for older files.
- FoodLogCore: `ConfirmedLogRelay`, `CustomFoodCreateGate`,
  `BackgroundOutboxDelivery` (new); weight/water coordinators and stores;
  `NotificationPlanning.planWindow`.
- TrainingCore: `TrainingReminderPlanner.plan(days:)` (default unchanged).
- App: intents, `AppServices`, `AppEnvironment`, `BackgroundRefresh`,
  `NotificationScheduler`, `ProfileLoader`, the create-in-Garmin screen; one new
  EN + CS string (and one retired).
- No new Garmin route. Every request already existed; the weigh-in lookup uses
  the live-probed day view.
