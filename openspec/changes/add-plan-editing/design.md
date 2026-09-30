## Context

Written 2026-09-30 on `mlcousek/add-plan-editing`, based on `main`
`362e385` (TrainingCore, read-only Today and Plan #108, season/phase/race
and stats #111, check-ins with the event log, outbox and segments #110).

The contract is the vault's `add-hub-ingest`, merged 2026-09-29 (read from
the vault's main branch; its fixtures are mirrored verbatim in
`Tests/TrainingCoreTests/Fixtures/Contract/vault/`):

- Event log v1, six types this app did not write yet:
  `plan.session.moved {week, baseRevision, sessionId, from, to}`,
  `plan.session.swapped {week, baseRevision, a, aDate, b, bDate}`,
  `plan.session.skipped {week, baseRevision, sessionId, reason?}`,
  `plan.session.unskipped {week, baseRevision, sessionId}`,
  `plan.rule.overridden {week, baseRevision, sessionId, rule}`,
  `event.retracted {target, reason?}`. `week` is `YYYY-Www`,
  `baseRevision` the `week.revision` the app showed; commands carry no
  `date`.
- Preconditions are judged against the **command's own training day**
  (from `at`, `athlete.tz`, `dayBoundaryHour`): a move applies when the
  session is in `week`, currently on `from`, `to` is in the same ISO week
  and both dates are on or after that day; a swap likewise for both
  sessions; a skip applies to any existing session, past days included;
  an unskip to a skipped session (else an applied no-op); a
  `baseRevision` above the week's revision is refused ("unknown
  revision").
- **A race session is fixed** (A50, `raceId` set or `type: race`): moving,
  swapping (either side) or skipping it is refused with a bilingual
  reason; the app "should not offer these actions".
- Re-plans at the desk **absorb** the commands their author could see and
  **rebase** the rest (`week.absorbed`).
- The projection publishes `acks {device: {seq, maxSeq}}` and
  `outcomes [{event, deviceId, seq, type, week, sessionId, status, reason}]`
  with `status` in applied, absorbed, superseded, refused, retracted and
  `reason` `{en, cz}` or null, for commands within 30 days of `asOf`. "Show
  an outcome's reason in the user's language; treat `absorbed` like
  `applied`. Clear a pending event when its `seq <= acks[me].seq`."
- `event.retracted` removes its target from the fold (same device, lower
  `seq`); retracting an override restores the rule edit (its D10).
- A17: the human has the last word over a safety rule, "but the app
  shows a big, clear recommendation/warning before the override", which is
  logged for the Sunday review.

The architecture note (section 4.4) sketches the phone side:
`shown = apply(projection.effectivePlan, localCommands.filter { seq > acks[me].seq })`,
with a pending badge that turns into applied, or superseded/refused "tap
for the reason".

## Goals / Non-Goals

**Goals**
- Move, swap, skip, unskip, override a rule edit and withdraw a pending
  command, each one or two taps from the session detail.
- Never offer what the vault would refuse for a reason the phone can
  know: a past day, another week, a race session, a week without a
  revision.
- The effect visible at once, clearly marked pending, until the vault
  answers; then the vault's answer in the app's language.
- The wire format stays in one file, golden-tested against the vault's
  example.
- Food-first and standalone installs unchanged; nothing sent without an
  enabled, configured connection with a device id.

**Non-goals**: see proposal.md.

## Decisions

### D1 -- Where the code lives

All logic in TrainingCore, never SwiftUI:

```
Events/HubEvent.swift            + six payloads (still the ONLY wire-format file)
Events/PlanCommandOverlay.swift  PendingOverlay: the phone's commands, their status, the preview
Events/PlanEditPolicy.swift      what may be asked for a session; command builders
ViewModels/PlanEditModels.swift  SessionEditModel, PlanChangeLineModel, the texts
```

`PendingOverlay` already exists as an empty seam in `TrainingSnapshot.swift`
(`add-training-today-and-plan` D8: "add-plan-editing fills it"); it moves
to its own file and gets content. The app adds actions to `TrainingModel`
and controls to `SessionDetailView`, `WeekAgendaView` and Today's session
card.

### D2 -- The payloads

| Type | Swift | Validation before recording |
|---|---|---|
| `plan.session.moved` | `SessionMovedPayload` | session id non-empty, `baseRevision >= 1`, `from != to`, both in `week` |
| `plan.session.swapped` | `SessionsSwappedPayload` | two different ids, `aDate != bDate`, both in `week` |
| `plan.session.skipped` | `SessionSkippedPayload` | reason `nil` or 1-2000 characters |
| `plan.session.unskipped` | `SessionUnskippedPayload` | session id non-empty |
| `plan.rule.overridden` | `RuleOverriddenPayload` | session and rule id non-empty |
| `event.retracted` | `EventRetractedPayload` | target non-empty; reason `nil` or 1-2000 |

- Optional keys (`reason`) are written as `null` when unknown, as for the
  check-ins. Keys are sorted by `JSONEncoder` (`.sortedKeys`, which on
  Apple platforms compares case-insensitively: `baseRevision` sorts before
  `bDate`); the golden file records the resulting bytes.
- Decoding is typed for all six (they were `.other` until now);
  `device.hello` stays `.other`. A command's `payload.date` stays `nil`
  (commands carry a week, not a day).
- **Golden**: `Fixtures/Events/plan-commands.v1.app.jsonl`, synthetic
  (device `ios-0000beef`, the example season's ids), byte for byte; and
  every command and retraction line of the vault's
  `events.v1.example.jsonl` decodes and re-encodes to the same JSON object
  (key order aside: the vault's lines are not key-sorted).

### D3 -- What the phone offers (`PlanEditPolicy`)

For a session of the effective plan, on the current training day `today`
(the plan's zone and day boundary):

- **Nothing** without `canEditPlan` (connection on and a device id, D8),
  for a week not in the projection's window, or a week without
  `revision`.
- **Race** (`raceId` or `type: race`): no move, swap or skip (A50); a line
  says why ("Race: the organiser sets its date").
- **Move**: the session's date and the target are on or after `today`,
  the target is another day of the same ISO week (Monday to Sunday), the
  session is not done. Days that already hold sessions are fine.
- **Swap**: with another session of the same week on another date, both
  dates on or after `today`, neither a race, neither done, neither with a
  pending command.
- **Skip**: a planned or missed session (past days allowed, like the
  vault). Not a done one: a skip unmatches its activity, which is not what
  "skip" means after the run (*defaulted*, tasks 0.2).
- **Unskip**: a skipped session.
- **Override a rule** (A17): a session the vault changed by a rule
  (`origin.kind == "rule"` with its `rule`, or a session rule note with a
  `rule` id), for each such rule not already overridden by this phone.
  Offered after an explicit warning (D6).
- **Withdraw**: a command of this phone that is still pending, and an
  applied rule override (retracting it restores the rule edit, the vault's
  D10). An applied move, swap or skip is undone by a new command (move
  back, unskip), not by retraction (*defaulted*, tasks 0.3).
- **While a command of this phone on the session is pending**, only
  Withdraw is offered for it (no stacked edits on an unanswered one;
  *defaulted*, tasks 0.1).

`baseRevision` is the projection's `week.revision` for the command's week
(the preview never changes it). The builders (`PlanEditPolicy.move`,
`swap`, `skip`, `unskip`, `overrideRule`, `withdraw`) re-check the same
rules and throw `PlanEditError.notAllowed` instead of recording something
the vault would refuse.

### D4 -- A command's status (`PendingOverlay.fold`)

Each command in the local log (kept 21 days, `TrainingEventLog`) gets one
status, in this order:

1. an outcome in `outcomes[]` for its event id (case-insensitive) ->
   **resolved** (`applied`, `absorbed`, `superseded`, `refused`,
   `retracted`, or an unknown word kept as such) with its reason;
2. else, a retraction of it by this phone: not yet acknowledged ->
   **withdrawing** (delivery of the retraction); acknowledged ->
   resolved `retracted`;
3. else acknowledged (`seq <= acks[deviceId].seq`) -> **received** (the
   vault read it but published no outcome: its week is outside the
   window);
4. else **pending**, `savedOnPhone` or `sent` (segment no longer pending
   in VaultKit's write queue), exactly like the check-ins.

### D5 -- The preview (`PendingOverlay.applying(to:)`)

Only **pending** commands are applied, in `seq` order, onto the
projection's plan -- the vault has already folded everything it
acknowledged:

- move: the session leaves `from` and joins `to` (sessions of a day sorted
  am, pm, then id), `origin` `{kind: moved, from: <first date>, event}`;
- swap: the two sessions trade days, `origin` `{kind: swapped, ...}`;
- skip: `status: skipped`; unskip: a skipped session becomes `planned`;
- rule override: **no preview** -- the phone cannot restore the options a
  rule removed; the session shows the pending badge only.

A command whose preconditions no longer hold in the projection (the
session is gone or elsewhere, a race) is left out of the preview and still
shown pending; the vault's outcome will say what happened. The phone
never runs the vault's rebase or rules (architecture note: "one
implementation"). `EffectivePlan` applies the preview first, then the
check-in lights (unchanged).

### D6 -- Screens

- **Session detail**: a "Change the plan" card when editing is allowed or
  this phone has a command on the session:
  - the latest command's line ("Move to Thu 31 Oct") with its status
    ("Pending · Saved on phone", "Applied", "Refused") and the vault's
    reason in the app language;
  - buttons **Move** (a list of the week's allowed days), **Swap** (a list
    of partners), **Skip** (optional reason), **Unskip**, **Override the
    rule** and **Withdraw**, each shown only when D3 allows it;
  - why nothing is offered, when that is not obvious ("Race: the
    organiser sets its date", "Past days follow the activities").
  - The override asks first, in an alert: "Override the safety rule?"
    with the rule's own note and "The rule changed this session as a
    precaution. You have the last word; the override is logged for the
    Sunday review." The action is destructive-styled ("Override anyway").
- **Week agenda**: a session row with a pending command shows a "Pending"
  badge (clock symbol and text, not colour alone); one refused or not
  applied shows "Not applied" with a warning symbol. Under the week header,
  the week's own changes ("Plan changes") list each command of this phone
  for that week, its status and reason, with Withdraw where D3 allows it.
- **Today**: the session card's `pendingBadge` (reserved since #108) shows
  the same "Pending" text.
- Every action is local and durable, then delivered by the existing
  debounce (120 s), foreground and backgrounding. Errors show in the same
  alert as the check-ins.

### D7 -- Strings

TrainingCore strings through `TrainingKey` + both `.lproj` tables (CRLF,
appended byte-safely); the vault's reasons are shown as the vault wrote
them (`en`, else `cz` for Czech). App strings in `Localizable.xcstrings` as
text insertions (the catalog has duplicate keys a JSON round-trip would
drop), Czech informal.

### D8 -- Capability

`TrainingCapabilities.recording(enabled:)`: check-ins, ticks, ratings and
plan edits together, on when the vault connection is enabled, configured,
Garmin-connected and has a device id (the check-ins' guard, unchanged).
`checkIns(enabled:)` keeps its meaning for existing callers and tests.

### D9 -- `training-plan-view` read-only

`add-training-today-and-plan`'s spec says "The system SHALL NOT offer any
control on the Plan tab that moves, swaps, checks in or rates a session".
Check-ins and ratings already live on Today and in the detail
(`add-training-checkins`); this change adds move, swap and skip to the
detail. The new capability states the edit controls; when the two changes
are archived, `training-plan-view`'s requirement becomes "The Plan tab's
week and month show no edit controls; the session detail does".

## Risks / Trade-offs

- **The preview may disagree with the vault** (a re-plan, a rebase, a
  rule): the badge says "pending" until the answer, and the answer always
  wins. Acceptable: the vault is the source of truth (A11, A18).
- **Sorted-key order** is Foundation's case-insensitive comparison; if a
  platform ever sorted byte-wise the golden file would fail loudly in CI,
  not silently change what the vault reads (it does not depend on key
  order).
- **A withdrawn command may still arrive before its retraction** (two
  segments): the vault folds both and answers `retracted`.
- **Outcomes last 30 days, the log 21**: every command the phone still
  lists can have its outcome.

## Migration Plan

1. Merge after #110 (merged). Nothing changes until a session is edited;
   food-first and standalone installs never see the controls.
2. Rollback: revert. Commands already delivered stay in the vault's log
   (immutable) and keep their effect until retracted from a later build or
   re-planned at the desk.

## Open Questions

Carried into tasks.md group 0 with defaults:

1. While a command on a session is pending, offer only Withdraw for that
   session (default), or allow stacking edits?
2. Skip not offered for a done session (default)?
3. Withdraw offered for pending commands and applied rule overrides only
   (default), or for any applied command?
4. Skip reason optional, free text up to 2000 characters (default)?
5. Delivery of a plan edit on the same 120 s debounce as a check-in
   (default), or sooner?
