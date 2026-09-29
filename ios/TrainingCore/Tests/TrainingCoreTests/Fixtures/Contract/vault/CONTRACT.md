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

| File | What it is |
|---|---|
| `projection.v1.example.json` | Every field of v1, with the reserved fields present and empty. |
| `projection.v1.minimal.json` | No season and no plan (`season: null`, `plan: null`). |

Do not edit these files. When the vault changes its fixtures (additive
changes only within v1), copy them again verbatim, update the date above and
re-run `swift test` (ProjectionDecodingTests, TodayBuilderTests,
PlanBuilderTests). App-authored edge cases are mutations of the example made
in the tests (`Fixtures.mutatedExample`), never hand-copied vault data.
