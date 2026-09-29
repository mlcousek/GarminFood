## Why

The plan is the heart of Jirka's Arc (the owner's decision A11), and he
asked for more than the week in front of him (decisions A12, A18, A19):
the **season** as one view, each **phase** as a section with a summary
at its end, and **race preparation per race as part of the plan**, with
race week linked to the food side (carb loading). `add-training-today-and-
plan` shipped Today and the Plan tab's Week and Month read-only, and
deliberately left these three screens to this change: its Plan tab
reserves a third segment for the season, and its race chip only jumps to
the race day in the month calendar.

Everything these screens need is already in the projection v1 the app
decodes: `season` lists every phase (period, kind, status, outline,
recap) and every race (priority, hero, anchoring phase, structured `prep`
with checkpoints, fuel, carb load and gear, `report`); `plan` carries the
selected phase's goals, rules and written weeks with the vault's
`actual`; `tests[]` holds every test's history; `athlete.weightKg` is the
weight the contract uses for carb-load grams. The vault's Obsidian
planner already draws the same three views from the same file
(`seasonTimeline`, `phasePlan`, `racePlan`); this change gives the phone
the same meaning.

## What Changes

- **TrainingCore** (pure, tested, no SwiftUI), new builders on
  `PlanBuilder`:
  - `seasonTimeline()` -> `SeasonTimelineModel`: phases as bands and races
    as markers on one axis, as fractions of the season's period; month
    ticks; the stretches no phase covers as labelled gaps; races on label
    lanes that never drop a label; anything outside the season clamped
    and flagged; today's mark; an empty state without a season.
  - `phaseDetail(id:)` -> `PhaseDetailModel`: kind, status, dates and
    where today falls ("Week 2 of 16 · 100 days left"); goals and rules
    (selected phase only, and it says so otherwise); the week-by-week run
    target against the vault's `actual` (`PhaseRamp`, the one ramp
    computation the statistics will reuse); key sessions; test results
    in the phase; its races; the recap and a short summary for a closed
    phase.
  - `raceDetail(id:)` -> `RaceDetailModel`: countdown (also for past
    races), priority and hero, distance, goal, the anchoring phase or
    "No phase covers this race yet"; start and cutoff; the checkpoint
    table with clock times, buffers, section paces and heart-rate caps;
    race fuel with totals to the finish; carb-load days with grams (the
    day's own `fuel.carbsG` inside the window, else g/kg x
    `athlete.weightKg`, labelled as an estimate); gear, mandatory first;
    the taper weeks; the plan's race-day session; "Race prep not written
    yet" for an empty prep.
  - English and Czech text for all of it (plurals in `.stringsdict`).
- **App**:
  - Plan tab: a third segment, **Season** (Week · Month · Season), with
    the timeline and the phases and races as rows that open their
    screens.
  - **Phase** and **Race** screens, pushed from Season, from each other
    and from a phase's key sessions and races.
  - Today's **race chip opens the race's screen** (Plan -> Season with
    the race pushed) instead of the month calendar.
  - Race week linked to food: each carb-load day has **Open food log**,
    which switches to Today on that date (its food log, summary and the
    training card's carb-load line) through the existing day navigation.

## Capabilities

### New Capabilities

- `training-season-view`: the season timeline and the Season segment.
- `training-phase-view`: one phase with its goals, rules, weeks, key
  sessions, tests, races and recap.
- `training-race-view`: one race with its countdown and preparation, the
  race chip's destination and the link to the food log.

### Modified Capabilities

None archived. `training-plan-view` and `training-today` (both from the
unarchived `add-training-today-and-plan`) gain behaviour here -- the
Season segment and the race chip's new destination -- and it is specified
as ADDED requirements of the new capabilities above, so the two changes
archive independently.

## Non-goals

- **Statistics** (adherence, the G/A/R split, volume vs target, test
  history with asymmetry). Owned by `add-training-stats`, which reuses
  `PhaseRamp`.
- **Check-ins, habit ticks, RPE, notes, the Outbox.** Owned by
  `add-training-checkins`.
- **Editing** anything: phases, races, preps, the plan. Owned by the vault
  (and `add-plan-editing` for sessions). Every screen here is read-only.
- **Race results and the race-day timeline against a live clock.** The
  report is only acknowledged ("Race report written"); its content lives
  in the vault. Results can come with a later vault field.
- **Logging carb-load food or setting food targets from the plan.** The
  food link opens the day; it changes nothing. Setting a carb-load
  calorie/carb target is a later change on the food side.
- **Sleep, recovery and gear mileage** (the owner's decision A12: out).
- **Anything the vault computes**: adherence, `actual`, matching, the
  selected phase. The phone only does display arithmetic (fractions, clock
  times, buffers, paces, fuel totals, the contract's own carb-load
  formula).

## Impact

- `ios/TrainingCore`: `Formatting/SeasonText.swift`,
  `ViewModels/SeasonTimelineModel.swift`, `ViewModels/PhaseDetailModel.swift`,
  `ViewModels/RaceDetailModel.swift`; 51 new `TrainingKey` cases with
  their en/cs `.strings` and `.stringsdict` entries;
  `Tests/.../SeasonPhaseRaceTests.swift`.
- App: `Plan/SeasonTimelineView.swift`, `Plan/PhaseDetailView.swift`,
  `Plan/RaceDetailView.swift` (new); `Plan/PlanTabView.swift` (Season
  segment, race destination), `App/AppRouter.swift` (`pendingRaceID`,
  `openRace`), `Today/TodayView.swift` (one line: the chip's action);
  23 new keys in `Resources/Localizable.xcstrings`.
- No new package, store, route, `project.yml` or workflow change; no
  Garmin or vault write.

**Depends on**: `add-training-today-and-plan` (TrainingCore, the Plan tab,
the race chip; merged, #108).

**Unblocks**: `add-training-stats` (reuses `PhaseRamp` and the Phase
screen's link), a later carb-load food target, race results once the vault
publishes them.
