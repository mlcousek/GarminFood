## Why

The owner's plan lives in the vault and is written at the desk, but the
week happens on the phone: a meeting eats Tuesday, the calf is tight on
Thursday, two amber mornings turn Wednesday's tempo into a ride and he
wants to ride it anyway. Today the app shows all of this read-only
(`add-training-today-and-plan`, spec "Plan screens are read-only"), so
every change waits for the desk.

The vault already understands the answer. Its `add-hub-ingest` (merged
2026-09-29, decisions A48 and A50) folds five plan-edit **commands** and
`event.retracted` from the app's event log into the projection, rebases
them over re-plans and publishes an **outcome** for each one (applied,
absorbed, superseded, refused with a bilingual reason, retracted). The
app's `add-training-checkins` (merged in #110) built the event log, the
outbox and the delivery; it deliberately wrote no commands. This change is
the phone half of plan editing: the commands, an optimistic "pending"
preview until the vault answers, and the vault's answer on screen.

## What Changes

- **The plan commands on the wire** (TrainingCore `Events/HubEvent.swift`,
  still the only file that knows the format): `plan.session.moved`
  `{week, baseRevision, sessionId, from, to}`, `plan.session.swapped`
  `{week, baseRevision, a, aDate, b, bDate}`, `plan.session.skipped`
  `{week, baseRevision, sessionId, reason?}`, `plan.session.unskipped`
  `{week, baseRevision, sessionId}`, `plan.rule.overridden`
  `{week, baseRevision, sessionId, rule}` and `event.retracted`
  `{target, reason?}`. Golden-tested byte for byte against a synthetic app
  fixture and line by line against the vault's mirrored example.
- **What the phone may ask** (TrainingCore, pure): a session's edit
  options from the effective plan and the training day -- move to another
  day of the same ISO week, swap with another session of that week, skip
  (optional reason), unskip, override a rule edit (A17), withdraw a pending
  command. Actions the vault would refuse are not offered: past days (for
  move and swap), another week, race sessions (A50), a week without a
  revision. `baseRevision` is the projection's `week.revision`.
- **Optimistic preview** (TrainingCore `PendingOverlay`, the D8 seam of
  `add-training-today-and-plan`): the phone's commands the vault has not
  acknowledged yet (`seq > acks[device].seq`) are applied over the
  projection, so a moved session shows on its new day at once, marked
  **pending** ("Saved on phone" / "Sent"). Once acknowledged, the
  projection is the truth and the command shows the vault's **outcome**
  from `outcomes[]`, with its reason in the app's language.
- **Plan tab and session detail**: a "Change the plan" card in the session
  detail (Move, Swap, Skip, Unskip, Override the rule, Withdraw), the
  pending badge on the week agenda's session rows and on Today's session
  card, and the week's own plan changes with their outcomes under the week
  header. The rule override shows a big, explicit warning before it is
  recorded (A17).
- **Delivery unchanged**: the same recorder, local log and outbox as the
  check-ins; nothing is sent unless the vault connection is enabled,
  configured, has a token and a device id.
- All new text in English and Czech.

## Capabilities

### New Capabilities

- `training-plan-editing`: plan-edit commands and retractions as events,
  what the app offers and refuses to offer, the pending preview, and the
  vault's outcomes on screen.

### Modified Capabilities

None archived. `training-plan-view` (from `add-training-today-and-plan`,
not yet archived) says "Plan screens are read-only"; this change replaces
that sentence for moving, swapping and skipping (design D9). Its archive
must fold the two together.

## Non-goals

- **Cross-week moves**: the vault refuses them in v1 (its open question 4);
  a later vault change and a later app change.
- **Constraint warnings** ("heavy days 2-3 days apart"), the checker of the
  architecture note section 4.2: a later change on both sides.
- **Running the vault's fold on the phone** (rebasing, `absorbed`, the
  rules): the preview is optimistic and simple; the vault's outcome is the
  answer (design D5).
- **Editing sessions' content** (targets, workouts, options), approving a
  week (`plan.week.approved`) or preselecting an option: not in the v1
  contract.
- **`device.hello`**: still not written; a later change.
- **Retry of failed segments in Settings -> Vault**: still
  `add-training-checkins` task 4.9.
- **Garmin writes**: none.

## Impact

- TrainingCore `Events/`: `HubEvent.swift` (six new payloads),
  `CheckInOverlay.swift` (skips commands), `TrainingRecorder.swift`
  (`planEdits(acks:outcomes:)`), new `PlanCommandOverlay.swift` (the
  pending fold and preview) and `PlanEditPolicy.swift` (what may be asked,
  command builders).
- TrainingCore view models: `TrainingSnapshot`/`EffectivePlan` fill
  `PendingOverlay`; `TrainingCapabilities.recording(enabled:)` turns on
  `canEditPlan`; new `ViewModels/PlanEditModels.swift`
  (`SessionEditModel`, `PlanChangeLineModel`); `SessionDetailModel.editing`,
  `SessionRowModel.pendingText`, `WeekAgendaModel.planChanges`,
  `SessionCardModel.pendingBadge` filled. Strings in both `.lproj` tables.
- Tests: `PlanEditingTests`, `HubEventTests` (plan commands), a synthetic
  golden `Fixtures/Events/plan-commands.v1.app.jsonl`.
- App: `TrainingModel` (actions, the plan overlay), `SessionDetailView`
  (the "Change the plan" card), `WeekAgendaView` (badges, plan changes),
  `TrainingTodayCards` (the pending badge), `Localizable.xcstrings`.
- No new package, no `project.yml` or CI change; no Garmin route; writes
  only into the install's own events folder, as today.

**Depends on**: `add-training-checkins` (#110, merged: event log, outbox,
delivery, acks), `add-training-today-and-plan` (#108: Plan tab, session
detail, the `PendingOverlay` seam) and the vault's `add-hub-ingest`
(merged: commands, outcomes, the race rule A50), whose fixtures are already
mirrored.

**Unblocks**: the vault's "Hub" scheduled task (its open question 7), which
only matters once the phone edits the plan; a later cross-week move.
