# Projection contract fixtures (mirrored)

- **Contract:** `hub.projection`, schema version **1** (final v1).
- **Source:** the vault's `add-training-plan-model` change, which generates
  both files from a synthetic 2030/31 season (no real names, races, zones
  or activities) and checks them byte for byte on its side.
- **Copied:** 2026-09-29, verbatim (byte for byte, LF line endings; see
  `.gitattributes`). Re-mirrored the same day after the vault's
  `add-garmin-workout-push` (additive, still v1): `option.watch` is filled
  (`name`, `state` pending/scheduled/failed, `channel`, `ref`, `at`),
  `done.source` gains `"activity-name"`, every workout has `watchName`.
  Re-mirrored 2026-09-29 from the vault's main branch after its
  `add-hub-ingest` merged (additive, still v1): `day.light` filled with
  `day.lightSource` (`checkin` | `option`), `session.feedback`
  `{ rpe, feel, note }`, week `ruleNotes`, rule edits (`origin` with
  `kind: moved|swapped|rule`, options cut to R, `status: "skipped"`), and
  top-level `acks`, `outcomes`, `rejected` filled from the event log.
  Re-mirrored again the same day (vault main `13c0d987`): the vault now
  refuses moving, swapping or skipping a race session, so the race stays
  on Sun 3 Nov and the command's outcome is `refused` with a bilingual
  reason; the second device's applied move now moves the W43 Sunday walk
  (`2030-w43-sun-pm`) to Fri 25 Oct.
  Re-mirrored 2026-09-30 from the vault's main branch after its morning
  pain score (decision A57; additive, still v1): every day has `pains`
  (`null` = not asked; 2030-10-23 has `achilles-left` 5.5 with a note and
  `knee-right` 1), W43 gains a `pain-high` rule note, and the phone's ack
  is `seq` 24. The minimal projection is unchanged. All four files were
  copied again and checked for anything non-synthetic first (no names,
  repositories, tokens or real dates: season 2030/31 only).

| File | What it is |
|---|---|
| `projection.v1.example.json` | Every field of v1, with the reserved fields present and empty. |
| `projection.v1.minimal.json` | No season and no plan (`season: null`, `plan: null`). |

Do not edit these files. When the vault changes its fixtures (additive
changes only within v1), copy them again verbatim, update the date above and
re-run `swift test` (ProjectionDecodingTests, TodayBuilderTests,
PlanBuilderTests). App-authored edge cases are mutations of the example made
in the tests (`Fixtures.mutatedExample`), never hand-copied vault data.

# Event contract fixtures (mirrored)

- **Contract:** the event log v1 (envelope `v: 1`) -- what the app writes
  into `events/<deviceId>/` (`add-training-checkins` design D2).
- **Source:** the vault's `add-hub-ingest` change (its contract's "Event
  log v1" section and its executable validator), generated synthetic:
  devices `ios-0a1b2c3d` and `ios-00000001`, season 2030, no real names or
  data.
- **Copied:** 2026-09-29, verbatim (byte for byte, LF; see
  `.gitattributes`), first from the change in progress and then again
  from the vault's main branch after it merged (both event files were
  identical). Re-mirror whenever the vault records a change in its fixture
  changelog. Re-mirrored 2026-09-30 for the morning pain score
  (add-checkin-pain-score): the example gained seq 24; the minimal file is
  unchanged.

| File | What it is |
|---|---|
| `events.v1.example.jsonl` | 24 events of every v1 type, including the plan commands (seq 16 a refused race move, seq 23 a superseded move) and `event.retracted`, which this app writes since add-plan-editing, `device.hello`, which it doesn't write yet, and (seq 24, 2026-09-30) a second check-in of 2030-10-23 with `pains`. |
| `events.v1.minimal.jsonl` | 3 events with every optional key omitted. |

`HubEventTests` decodes both: every type this app writes decodes to its
payload (`device.hello` to `.other`), no line is invalid, and each
command and retraction line re-encodes to the same JSON object
(add-plan-editing). `PlanEditingTests` folds the example's commands with
the example projection's `acks` and `outcomes`. The app's
own byte-exact golden files are `../../Events/events.v1.app.jsonl` (every
check-in now carries `"pains":null`), `plan-commands.v1.app.jsonl` and
`checkin-pains.v1.app.jsonl` (add-checkin-pain-score), which the vault's
validator (`validateEvent`) accepted on 2026-09-29 and 2026-09-30.
