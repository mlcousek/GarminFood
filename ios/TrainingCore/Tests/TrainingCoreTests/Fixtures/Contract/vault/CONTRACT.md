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
  changelog.

| File | What it is |
|---|---|
| `events.v1.example.jsonl` | 22 events of every v1 type, including the plan commands, `device.hello` and `event.retracted` this app doesn't write yet. |
| `events.v1.minimal.jsonl` | 3 events with every optional key omitted. |

`HubEventTests` decodes both: the four types this app writes decode to
their payloads, every other type to `.other`, no line is invalid. The app's
own byte-exact golden file is `../../Events/events.v1.app.jsonl`, which the
vault's validator (`validateEvent`) accepted on 2026-09-29.
