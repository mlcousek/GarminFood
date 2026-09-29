## Why

Statistics are one of the screens the owner asked for (decisions A12 and
A18), and tests as sessions with results and history (A19). Today, Plan,
Season, Phase and Race show what the plan is and what happened day by
day; nothing yet answers **"did I do what was planned, and is the plan
working?"** over a phase or the season: how many sessions were done or
missed, how often the easier (A) or no-running (R) option was taken, how
each week's running compared with its target, and how the tests
(including the calf's left against right) are moving.

All of it is in the projection v1 the app already decodes: session
statuses and the done option (computed by the vault), each week's
`targets` and `actual`, and `tests[]` with every week's results. The
vault's Obsidian planner has the same view (`planStats.ts`); this change
gives the phone the same meaning. What the planner draws from the desk's
diary or activity details (intensity against 80/20, weeks outside the
file) is not on the phone and is named as such, never guessed.

## What Changes

- **TrainingCore** (pure, tested): `PlanBuilder.stats(scope:)` ->
  `TrainingStatsModel` for one phase or the whole season:
  - **adherence**: per week and per phase, sessions done, missed, skipped
    and still planned as the vault published their statuses, "Done 90 %
    of the sessions due so far", and the started weeks of the scope that
    the plan file doesn't hold listed as "Not in the app's window: W36,
    W37 …", never counted as zero;
  - **the G/A/R split** of the done traffic-light sessions, with "Option
    not identified" as its own share;
  - **volume vs target** per week through `PhaseRamp` (from
    `add-season-phase-race-screens`), with the difference in km and %,
    and a summary (planned in total, run of planned, weeks within 10 %,
    the weekly mean);
  - **tests**: every test's history per measure (latest, first -> last,
    judged in the measure's better direction) and `_l`/`_r` measures
    paired with their left/right asymmetry |L - R| / max(L, R) on every
    date and the latest;
  - English and Czech text.
- **App**: a **Statistics** screen (Swift Charts, as Weight and Trends
  already use): a This phase / Whole season picker, adherence as stacked
  weekly bars with rows per week and per phase, the G/A/R share bar with
  lettered rows, weekly target vs run bars with rows, and one card per
  test with its line chart, verdicts and the asymmetry. Opened from a
  **Plan toolbar button** (current phase) and from the **Phase screen**
  (that phase).

## Capabilities

### New Capabilities

- `training-stats`: plan-relative statistics for a phase or the season.

### Modified Capabilities

None. The Phase screen's link to its statistics is part of this
capability.

## Non-goals

- **Intensity against 80/20** (planned by type, executed by average heart
  rate) and the **morning-light strip**: the executed split needs the
  activities' heart rate and time, which the projection doesn't carry; the
  light is always `null` in v1. The vault planner shows both. A later
  change, once the projection or check-ins provide the inputs
  (`add-training-checkins` owns the light).
- **"What did I do" statistics** (volume by sport, load, bests,
  consistency): the maps plugin's training dashboard.
- **Sleep, recovery, gear mileage** (A12: out). Weight stays on the food
  side's Progress tab.
- **Phase vs phase comparison table**: the per-phase adherence rows and
  each phase's recap (`add-season-phase-race-screens`) cover it for now.
- **Computing anything the vault computes**: statuses, `actual`, the done
  option, matching. The phone counts and does display arithmetic only.
- **Check-ins, habit ticks, RPE, notes**: `add-training-checkins`.

## Impact

- `ios/TrainingCore`: `ViewModels/StatsModels.swift` (`StatsScope`,
  `StatusCounts`, the adherence, option, volume and test models,
  `TestAsymmetry`, `PlanBuilder.stats(scope:)`); 14 `TrainingKey` cases
  with en/cs entries (one plural); `Tests/.../TrainingStatsTests.swift`.
- App: `Plan/TrainingStatsView.swift` (new); `Plan/PlanTabView.swift`
  (toolbar button), `Plan/PhaseDetailView.swift` (link); 13 new keys in
  `Resources/Localizable.xcstrings`.
- No new package, store, route, `project.yml` or workflow change.

**Depends on**: `add-season-phase-race-screens` (`PhaseRamp`,
`TestVerdict`, the Phase screen; same branch, committed first).

**Unblocks**: an intensity split once activities' heart rate reaches the
projection; a light strip once check-ins fill `days[].light`; training
gamification (`add-training-gamification`) reading the same counts.
