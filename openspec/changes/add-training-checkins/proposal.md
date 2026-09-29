## Why

`add-training-today-and-plan` made the owner's plan readable on the phone;
nothing on the phone can yet say how the morning went. His plan depends on
exactly that (decision T6): every run day offers three options, **G** (the
planned session), **A** (easier) and **R** (an alternative without
running), and the 4:00 morning check, green, amber or red,
decides which one he runs. The vault's rules read the light; its habit
ladder reads the daily habit ticks; the Sunday review reads how hard each
session felt. Today these facts live in his head or in daily-note
checkboxes.

`add-vault-connection` built the write path (a durable queue, create-only
uploads, the device's own events folder) and deliberately enqueues nothing.
This change is its first production writer: every app action becomes an
**event**, committed on the phone first and delivered to the vault later as
an immutable file, exactly as the training hub's architecture describes
(event log, "seal, then send"). The vault's parallel change `add-hub-ingest`
reads those files.

## What Changes

- **An event log in TrainingCore** (never SwiftUI):
  - `HubEvent`, the envelope v1 (`v`, `id` (UUIDv7), `deviceId`, `seq`,
    `at` with its offset, `type`, `payload`) and four typed payloads:
    `checkin.morning` `{date, light, sessionId?}`, `habit.tick`
    `{date, habitId, done}` (on/off, decision A42), `session.rpe`
    `{date, sessionId, rpe}` and `session.note` `{date, sessionId, text}`.
    The whole wire format sits in **one file**, so the vault contract can
    move it in one place.
  - `TrainingEventLog`: an append-only local store (the outbox). An action
    is durable on return; nothing waits for the network.
  - `EventSegment`: seals the unsent events into one JSONL segment,
    `events/<deviceId>/<yyyy>/<mm>/<yyyymmddThhmmssZ>-<firstSeq>.jsonl`,
    and hands it to VaultKit's existing write queue; `CreateOnlyFileUploader`
    delivers it (create-only PUT, blob-SHA idempotency).
  - `CheckInOverlay`: the phone's own recent events folded into "latest
    wins" state per day, merged over the projection, so a check-in, a tick,
    an RPE or a note shows at once and keeps showing until the vault
    reflects it.
  - `TrainingRecorder`: the one entry point for the four actions (resolves
    the training day and the session from the cached projection, reserves
    the sequence number, commits), used by the app's views and by the
    Controls.
  - `TrainingReminderPlanner`: the morning check-in and evening habit
    reminders, planned from the projection and the overlay.
- **Today (training experience)**:
  - a **morning check-in** row on the training card: three buttons G, A,
    R (green, amber, red), letter and shape as well as colour; the chosen
    light marks the matching option card and shows "Saved on phone" until it
    is uploaded, then "Sent";
  - **habit ticks**: each expected habit gets an on/off toggle (A42);
  - the option cards keep opening the session detail (they never record
    anything by accident).
- **Session detail**: **RPE** (1–10) and a **note** for the session.
- **Lock-screen Controls**: three Controls "Morning check-in: G / A / R" in
  the existing widget extension (no new App ID). Each opens the app and
  commits `checkin.morning` there (a Control can't reach the app's data on
  a free account).
- **Local notifications**: "How do you feel today?" at 04:05 on run days
  without a check-in, and "Evening habits" at 20:10 when habits are still
  open. One switch in Settings → Notifications, training experience only.
- **Delivery**: the unsent events are sealed and drained on foreground, on
  backgrounding and two minutes after an action; Settings → Vault shows the
  pending count and failures. **Nothing is written to GitHub unless the
  vault connection is enabled, configured and has a device id**.
- All new text in English and Czech.

## Capabilities

### New Capabilities

- `training-event-log`: the event envelope, the local log, segments, delivery
  and its guards.
- `training-checkins`: the morning check-in (Today and Controls), habit
  ticks, RPE and notes, optimistic state and the training reminders.

### Modified Capabilities

None archived. `training-today` (from `add-training-today-and-plan`, not yet
archived) described the option cards and habits as read-only; this change
adds the check-in row and the habit toggles beside them without changing
what an option card does (design D8).

## Non-goals

- **Plan edits** (move, swap, skip) and the pending-edit overlay:
  `add-plan-editing`.
- **Running the traffic-light rules** on the phone. Picking amber shows the
  light; the week adapts when the vault's rules run.
- **Tendon score, `device.hello`, `event.retracted`**: later event types.
  A correction here is a newer event of the same kind (latest wins).
- **The optimistic "done" from the Garmin activity list**: needs an
  activity route and matching rules the vault owns; later.
- **Showing the vault's acknowledgements** (`acks`, `rejected`): reserved
  in projection v1; this change shows "Saved on phone" / "Sent" only.
- **Background delivery** through `BGAppRefresh`: foreground, backgrounding
  and the debounce are enough for a check-in that the vault ingests every
  ~30 min at best.
- **Garmin writes**. None.

## Impact

- `ios/TrainingCore/Sources/TrainingCore/Events/` (new): `HubEvent.swift`,
  `UUIDv7.swift`, `TrainingEventLog.swift`, `EventSegment.swift`,
  `CheckInOverlay.swift`, `TrainingRecorder.swift`,
  `TrainingReminderPlanner.swift`, plus `ViewModels/CheckInModels.swift`;
  tests and a synthetic JSONL golden
  fixture under `Tests/TrainingCoreTests/Fixtures/Events/`.
- TrainingCore view models: `TrainingSnapshot` gains the overlay and real
  capabilities; `TodayTrainingModel` gains `checkIn`; `HabitTick` gains
  `.tickable`; `SessionDetailModel` gains `rating`.
- App: `GarminFood/Training/TrainingEventsService.swift` (the process's one
  recorder), `TrainingModel` (actions, overlay), `TrainingTodayCards`
  (check-in row, habit toggles), `SessionDetailView` (RPE and note),
  `NotificationScheduler` + `NotificationSettingsView` (training
  reminders), `AppEnvironment` (drain triggers); Settings → Vault's
  existing "Pending writes" row now counts the events not yet uploaded.
- `Shared/MorningCheckInIntents.swift` (app + widget) and
  `GarminFoodWidget/Controls/MorningCheckInControls.swift`.
- `Localizable.xcstrings` (app and widget), TrainingCore `.lproj`.
- No new package, no `project.yml` or CI change: TrainingCore already has
  its `swift test` step and is linked into the app only.
- No Garmin route. The first vault writes, into the install's own events
  folder only (`VaultPathPolicy`).

**Depends on**: `add-training-today-and-plan` (PR #108: TrainingCore, Today,
session detail), `add-vault-connection` (write queue, uploader, device id),
and the vault's `add-hub-ingest` for the event contract v1 (design D2: the
envelope is coded to the architecture note and the owner's brief; it is
re-checked against the vault's fixture before merge, tasks group 1).
