## Context

Written 2026-09-29 on `mlcousek/add-training-today-and-plan` (PR #108,
TrainingCore and the read-only Today/Plan), with `add-vault-connection`
(#107) and `rebrand-to-jirkas-arc` (#106) on `main`.

What the owner decided (vault Decisions Log):

- T6: up to three options per run day, G/A/R, already on the watch; the
  morning check is the pick. The light (how he felt) and the executed
  option (what he did) are separate facts.
- A11/A18: the plan is the heart of the app; the vault is the source of
  truth; the app is the daily surface.
- A40: logging on a future day is fine.
- A42: habit ticks are **on/off** booleans per habit per day (not counts).
- A44: this change and the vault's `add-hub-ingest` start together.

What the code provides:

- VaultKit (`add-vault-connection` D5, D7): `DeviceIdentityStore`
  (`ios-xxxxxxxx`, `reserveSequence` persists before returning),
  `DurableQueue<SealedFile>` (`VaultWriteQueue`, lazily created),
  `CreateOnlyFileUploader` (create-only PUT, 422 → compare blob SHAs),
  `VaultPathPolicy` (writes only under `events/<ownDeviceId>/…/*.jsonl`),
  `VaultTransport`. Nothing enqueues in production yet.
- TrainingCore (`add-training-today-and-plan` D8): builders read a
  `TrainingSnapshot` with an `EffectivePlan` and `TrainingCapabilities`
  (all false); the view models carry slots for check-ins (`HabitTick`,
  the morning-light highlight, `pendingBadge`).
- The widget extension already hosts Controls that open the app
  (`openAppWhenRun`) because a free account has no App Group
  (`QuickPickLoggingIntents.swift`); `Shared/` is compiled into both
  targets and the widget never links VaultKit or TrainingCore.
- `NotificationScheduler`: replan-and-diff cycles per identifier prefix.

The design source is the vault's *Training Hub Architecture* note, §2.4
(event log), §3.2 (outbox), §4.4 (optimistic UI), §6.3 (Controls,
notifications).

## Goals / Non-Goals

**Goals**
- The 4:00 check-in in one tap from the lock screen, recorded even in
  airplane mode.
- Habit ticks, RPE and a note in one or two taps on Today and the session
  detail.
- Every action durable on the phone before anything else happens; delivery
  is a drain, never awaited by a confirm path.
- The wire format in one file, golden-tested, ready to be re-checked
  against the vault's contract.
- Food-first and standalone installs unchanged; nothing written to GitHub
  without an enabled, configured connection and a device id.

**Non-goals**: see proposal.md.

## Decisions

### D1 — Where the code lives

`ios/TrainingCore/Sources/TrainingCore/Events/`, not a new package:

```
Events/
  HubEvent.swift              the envelope v1 + payloads + JSONL codec (ONE file)
  UUIDv7.swift                time-ordered ids (RFC 9562)
  TrainingEventLog.swift      the local append-only log (the outbox)
  EventSegment.swift          seal unsent events into a SealedFile segment
  CheckInOverlay.swift        latest-wins fold of the phone's events
  TrainingRecorder.swift      record / seal / drain / overlay; the one entry point
  TrainingReminderPlanner.swift  morning + evening reminders (pure)
```

- A new package would need its own `project.yml` entry, CI step and
  localization wiring, and would still depend on TrainingCore for the
  training day and the projection (the check-in resolves its session from
  it). TrainingCore already depends on VaultKit, is app-only and has its
  `swift test` step. The wire format is isolated by file (D2), which is
  what the contract needs.
- Never SwiftUI. Tests with real stores on temp files (house convention).

### D2 — The envelope v1 (app side), one file

The vault's event contract v1 comes from its `add-hub-ingest` change
("Event log v1" in its Training Hub Contract, executable as
`validateEvent`). Its two fixtures appeared while this was being built and
are mirrored verbatim (see "Contract details confirmed" below). The
envelope:

```json
{"at":"2030-10-23T04:07:31.482+02:00","deviceId":"ios-0000beef","id":"01f2…","payload":{"date":"2030-10-23","light":"amber","sessionId":"2030-w43-wed-am"},"seq":7,"type":"checkin.morning","v":1}
```

| Field | Meaning |
|---|---|
| `v` | envelope version, `1` |
| `id` | UUIDv7, lowercase; time-sortable, generated offline; dedupe key |
| `deviceId` | `ios-xxxxxxxx`, the folder the file lives in |
| `seq` | per-device, monotonic, never reused (`reserveSequence`) |
| `at` | producer wall clock with its UTC offset, milliseconds |
| `type` | `checkin.morning`, `habit.tick`, `session.rpe`, `session.note` |
| `payload` | per type, below; always carries `date`, the training day |

| Type | Payload |
|---|---|
| `checkin.morning` | `{date, light: green\|amber\|red, sessionId?, option?: G\|A\|R}` |
| `habit.tick` | `{date, habitId, done: bool}` (A42) |
| `session.rpe` | `{date, sessionId, rpe: 1…10, feel?: 1…5}` |
| `session.note` | `{date, sessionId, text}` (1–2000 characters) |

- **Optional keys are written, as `null` when unknown** (the contract:
  absent and `null` mean the same, "the app should write them"). `option`
  is the option he intends: the light's letter when the day has a
  traffic-light session, else `null`. `feel` is `null` (not asked yet,
  tasks 0.5). The light is `green|amber|red`, never the workout letter.
- **Serialisation is deterministic**: `JSONEncoder` with sorted keys and
  unescaped slashes, one object per line, `\n` line ends, a trailing
  newline. The same events always make the same bytes, which is what
  "seal, then send" and the blob-SHA idempotency need.
- **Decoding is tolerant** of unknown fields; a type this app doesn't
  write (`device.hello`, `event.retracted`, the `plan.*` commands) decodes
  as `.other(type)` and is never encoded.
- Corrections are newer events of the same kind: the vault and the app take
  the **latest by `seq`** per (date) for a light, per (date, habit) for a
  tick, per session for an RPE or a note. No `event.retracted` yet.
- **Golden fixture**: `Tests/TrainingCoreTests/Fixtures/Events/
  events.v1.app.jsonl`, synthetic (the vault example's 2030 season ids,
  device `ios-0000beef`); encode must reproduce it byte for byte and decode
  must read it back. The vault's `events.v1.example.jsonl` and
  `events.v1.minimal.jsonl` are mirrored verbatim under
  `Fixtures/Contract/vault/` and decoded by `HubEventTests`.
- **Segments stay under the contract's limits**: at most 500 events and
  900 KiB per file (the vault quarantines a segment over 1 MiB), lines far
  under 16 KiB, note texts 1–2000 characters (an empty note is never
  sent).

### D3 — The local log is the outbox

- `TrainingEventLog` (actor): `Application Support/VaultKit/
  training-events.json`, a JSON array of `LoggedEvent {event, recordedAt,
  segmentId?}`, loaded through `PersistedJSON` (quarantine, never wipe;
  `ensureSafeToWrite`). **Durable on return** from `append`.
- Recording: `TrainingRecorder.record(payload)` reserves one `seq` from
  `DeviceIdentityStore` (persisted first), builds the envelope and appends
  it. No network, no projection write.
- Kept 21 days after recording once sealed (the overlay's window, D5);
  unsealed events are never pruned.
- **Backups**: the whole `VaultKit/` directory is already excluded
  (`BackupExclusions`), and this file lives there. A restore on a new phone
  gets a new device id and starts a fresh log; anything unsent on the old
  phone is lost. Accepted: a check-in is a daily fact, and the vault's
  dedupe by `id` would make a re-send harmless, but a re-send under a new
  device id would be a second folder for the same facts. *Defaulted, owner
  may override* (tasks 0.4).
- **No device id, no recording**: the id appears on the first successful
  "Test connection" (`add-vault-connection` D5). Until then the
  capabilities stay off (D7) and the Controls answer "Connect the vault
  first".

### D4 — Segments and delivery

- `TrainingRecorder.seal` (with `EventSegment`) takes the unsealed events of this device, at
  most 500 per segment, oldest first, and makes one `SealedFile`:
  - path `events/<deviceId>/<yyyy>/<mm>/<yyyymmddThhmmssZ>-<firstSeq>.jsonl`
    (UTC seal time; `yyyy/mm` of that time), which `VaultPathPolicy`
    allows;
  - bytes: the JSONL of D2; commit message
    `hub: 3 events (ios-0000beef, seq 7-9)`;
  - enqueued in VaultKit's `VaultWriteQueue`, **then** the events are
    marked with the segment's id. A crash between the two can put an event
    in two segments; the vault dedupes by `id`. The other order could lose
    it.
- `TrainingRecorder.drain(transport)` seals, then drains the queue with
  `CreateOnlyFileUploader`. Auth, offline and rate limits stop the cycle
  without spending attempts; a `failed` segment is visible and retryable
  in Settings → Vault (VaultKit's rules, unchanged).
- **Triggers** (app): launch and foreground, backgrounding, and 120 s after
  an action (debounced; a burst of ticks becomes one file). All
  unstructured tasks; no confirm path awaits them.
- **Guards**: the app only calls `drain` when the connection is enabled,
  configured, has a token and its request gate is open (the same gate the
  projection fetch uses); `VaultPathPolicy` refuses anything outside the
  install's own folder regardless.
- Settings → Vault's existing "Pending writes" row shows the events not
  yet uploaded (unsealed, or in a segment still pending or failed), through
  `VaultStatus.pendingWrites`. A `failed` segment stays in the queue and
  is retried by hand later (`DurableQueue.retry`); a Retry control for it
  is left for a follow-up (tasks 4.9).
- After a drain: a delivered segment records a success in the vault
  status; a rate limit is recorded (so the request gate waits); an auth
  stop forces one projection fetch, whose response names the exact loud
  problem for the banner (the queue only knows "auth").

### D5 — Optimistic state: the overlay over the projection

`CheckInOverlay.fold(events, sentSegments)` keeps, per key, the latest
event by `seq` and whether it has reached the vault:

- `light(on:)`, `habitTick(on:habit:)`, `rpe(session:)`, `note(session:)`,
  each with `delivery: .savedOnPhone | .sent` (`.sent` once its segment's
  queue entry is `sent`, or the segment is no longer in the queue).
- `TrainingSnapshot` carries it; `EffectivePlan` applies the local light to
  each day's `light`, so every builder (Today's highlight and light line,
  the month glyph, the detail's pre-selection) shows the phone's check-in
  without a builder change (the D8 seam of the previous change).
- Habits: a local tick wins; else the projection's `habitsDone[id]`
  (≥ 1 is on, 0 is off, absent is off and "unknown").
- A third state, `.received` ("Received by the vault"), once the cached
  projection's `acks[deviceId].seq` reaches the event's `seq` (the
  contract: `seq` is the highest `n` with `1…n` all received; a gap holds
  it).
- **Local wins while it is kept** (21 days). The vault folds the very same
  events, so after ingest both agree. The phone never runs the rules: amber
  shows the light, and the week adapts at the next desk sync.

### D6 — Today and the session detail

- **Check-in row** on the training card, above the sessions, when the
  capabilities allow it and the plan has the day (rest days included: the
  check is about how the morning feels, not the run): the prompt "Morning check-in",
  three buttons **G · A · R** with the letter, the D9 shape of the previous
  change (circle, triangle, square) and the token tint (`success`,
  `warning`, `danger`); the chosen one filled and marked selected; under
  it "Saved on phone" or "Sent". Tapping another light records a new event
  (latest wins). One VoiceOver element per button: "Green: planned session".
- **The option cards still open the detail.** Design D8 of the previous
  change sketched `.checkIn` as the option card's action; a mis-tap on a
  card you tapped to read would then record a light. The separate row
  keeps reading and recording apart. The matching card is highlighted
  through the morning-light highlight that already exists.
- **Habit rows** get an on/off toggle (`HabitTick.tickable(done:, pending:)`)
  when ticking is allowed; the row's text is unchanged. Any selected day,
  past or future (A40).
- **Session detail** gets "How did it feel?": RPE 1–10 as a row of
  buttons, and a note (multi-line text field, Save). Both show the phone's
  latest value and its delivery state.
- `TrainingCapabilities`: `canCheckIn`, `canTickHabits`, `canRateSession`
  are true when the connection is enabled and a device id exists;
  `canEditPlan` stays false.

### D7 — The Controls

- Three `ControlWidget`s in the existing widget extension (no new App ID):
  "Check-in: Green", "Amber", "Red", symbols `circle.fill`,
  `triangle.fill`, `square.fill`; kinds
  `com.mlcousek.garminfood.widget.control.checkin.{green,amber,red}`.
- Their action is `MorningCheckInIntent(light:)` in `Shared/` (compiled
  into both targets, like the quick-pick intents), `openAppWhenRun = true`
  and `authenticationPolicy = .alwaysAllowed`, so it runs in the app's
  process with the app's files. `Shared/` must not import TrainingCore
  (the widget doesn't link it), so the intent calls a hook,
  `MorningCheckInControlAction.handler` (a `@MainActor` closure), which the
  app installs in `GarminFoodApp.init()` before any scene exists. The
  intent's light enum uses case names without colour words
  (`greenLight`...), because the design-token lint forbids `.red` and
  friends; the raw values are the contract's words.
- The handler (`TrainingEventsService`, app-only) checks the connection is
  on and has a device id, reads the cached projection (no network),
  resolves the training day and session (`CheckInPlanning`), records the
  event, and asks the running app to reload its overlay and schedule the
  debounced drain. A failure throws a localized error, so the Control
  shows it (loud, not silent).
- iOS 18+ like the other Controls. Unconfirmed until a device check, as for
  the quick picks: whether `.alwaysAllowed` avoids an unlock prompt when
  the app must come forward (tasks 7).

### D8 — Reminders

- `TrainingReminderPlanner.plan(snapshot, overlay, today, settings)`:
  - **morning**: on each of today and tomorrow that has a session with
    options and no check-in yet, "How do you feel today?" at **04:05**
    (defaulted);
  - **evening**: on each of today and tomorrow with expected habits not
    all ticked, "Evening habits" at **20:10** (defaulted).
- `NotificationScheduler.syncTrainingReminders` replans and diffs with
  its own prefix `training.` (one-shot dated requests, as the supplement
  slots do), and removes them all when the switch is off or the
  experience is food-first. No actions on the notification (a tap opens
  the app on Today); no new notification category (the supplement
  category registration replaces categories).
- One switch "Training reminders" in Settings → Notifications, shown in the
  training experience, **on by default** once notifications are allowed.

### D9 — Strings

TrainingCore strings go through `TrainingKey` + both `.lproj` tables
(CRLF, appended byte-safely). App and widget strings are added to the two
`Localizable.xcstrings` catalogs as text insertions (the app catalog has
duplicate keys that a JSON round-trip would drop), with Czech in the
informal register. Keys used in `Shared/` are in both catalogs.

## Contract details confirmed (2026-09-29)

Against the vault's `add-hub-ingest` event contract v1, still in progress
on the vault side when mirrored:

- Envelope `v, id, deviceId, seq, at, type, payload` -- as built. `id` is
  a UUID compared case-insensitively (v7 recommended); `deviceId` must
  equal the segment's folder; `at` has an optional fraction.
- `checkin.morning` has `option?` (the intended letter) -- added;
  `session.rpe` has `feel?` 1–5 -- added, written `null`; texts 1–2000
  characters -- empty notes refused; segment ≤ 1 MiB -- 900 KiB cap added.
- The segment path and name are exactly D4's.
- `acks[deviceId] = {seq, maxSeq}` -- read for `.received` (D5).
- The vault's `validateEvent` accepts every line of
  `events.v1.app.jsonl` (run locally with Node on 2026-09-29).
- Not written by this app yet: `device.hello`, `event.retracted`, the
  `plan.*` commands (`add-plan-editing`).
- Re-mirrored from the vault's main branch once `add-hub-ingest` merged
  (tasks 1.4): the event fixtures were unchanged; the projection example
  now carries what the ingest fills. TrainingCore reads, tolerantly, only
  what the app uses: `day.lightSource` (a light inferred from the executed
  option is not shown as a check-in), `session.feedback` (the rating falls
  back to it), week `ruleNotes` (shown in the week agenda), `origin.kind`
  (`swapped` reads "Swapped from …"), and `acks` (D5). `outcomes` and
  `rejected` stay undecoded JSON.

## Risks / Trade-offs

- **The contract may still move** before the vault's change merges. One
  file changes (`HubEvent.swift`); the mirrored fixtures and the golden
  file catch drift. Re-mirror when the vault's change lands (tasks 1.4).
- **Duplicate events after a crash** during sealing: harmless by id.
- **A lost phone loses unsent events** (D3). Acceptable for daily facts.
- **Lock-screen Controls may ask for Face ID** before opening the app
  (unconfirmed, as for the quick picks). Still one tap plus unlock.
- **Two sources of habit truth** during the cut-over from daily-note
  checkboxes: the vault decides which it reads for a day (architecture
  §11 Q8); the app shows its own tick first.

## Migration Plan

1. Merge after #108; nothing changes for a food-first or standalone
   install, and nothing is written until the connection has a device id.
2. The first check-in creates `training-events.json`; the first drain
   creates the queue file and the first file in the vault's
   `events/<deviceId>/` folder.
3. Rollback: revert. The log and queue files stay unread in `VaultKit/`;
   events already delivered stay in the vault (immutable facts).

## Open Questions

Carried into tasks.md group 0 with defaults:

1. Morning reminder at 04:05 and evening at 20:10 (default)?
2. Reminders on by default in the training experience (default yes)?
3. Debounce 120 s after an action (default) or deliver only on
   backgrounding?
4. The event log excluded from backups (default) or included?
5. RPE scale 1–10 (default) or the 1–5 "feel" as well?
