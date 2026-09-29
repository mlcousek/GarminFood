## Context

Written 2026-09-29 against `origin/main` @ `2d76ef5`, which has
TrainingCore and the read-only Today and Plan (`add-training-today-and-
plan`, #108), VaultKit (#107) and the rebrand (#106).

What the owner decided (the vault's Winter Arc decisions log):

- A11: the plan is the heart of the app; modern style, easy to work with.
- A12: in -- phases (each viewed as one section with a summary), a season
  view, races, statistics, race prep for each race as part of the plan,
  weight (already in the app). Out -- sleep and recovery, gear and shoe
  mileage.
- A18: screens -- Today · Plan · Season timeline · Phase (+ recap at the
  end) · Race (prep, countdown, race-day timeline, result) · Statistics ·
  Food and weight.
- A19: race week linked to food (carb loading, long-run fuelling); tests
  as sessions with results and history.
- The anti-duplication rule: anything computed (adherence, rules, the
  chosen option, gate status, `actual`) is computed once on the desk; the
  app and the plugin read it.

What the code provides:

- TrainingCore decodes every field these screens need (`Season`,
  `PhaseSummary` with `outline` and `recap`, `Race` with `prep` and
  `report`, `Plan` with `goals`, `rules` and weeks with `actual`,
  `TestHistory`, `Athlete.weightKg`) and gives builders a
  `TrainingSnapshot` with lookups (`phase(id:)`, `race(id:)`,
  `outlineRow(for:)`).
- `PlanBuilder` (week, month, session detail, ladder), `TrainingFormatting`
  (targets, dates, countdowns, fuel), `TrainingText` (en/cs tables with
  `.stringsdict` plurals) and the test fixtures (the vault's synthetic
  2030/31 example).
- The Plan tab with a `PlanMode` segmented control (Week · Month, the
  third segment reserved), a `NavigationStack` per tab, the router's
  pending plan date, and Today's race chip.
- Swift Charts is already used (Weight, Trends); the design system has
  `.card()`, `SectionHeader`, `StatTile`, `TrainingEmptyStateView` and the
  theme tokens (`accent`, `success`, `warning`, `danger`, `stroke`).

## Evidence (probes)

No live probe: nothing new is fetched. The evidence is the contract and
its executable form:

- The vault's Training Hub Contract document (read
  2026-09-29): the shape of `season`, `prep`, `recap`, `tests`, and
  semantics 1 (`plan` is the selected phase), 4 (week `actual` and
  `targets.runKm`, else the outline row) and 6 (carb-load grams are
  `round(g/kg x weight)`, "the app may recompute").
- The vault planner's pure modules `seasonTimeline.ts`, `phasePlan.ts`
  and `racePlan.ts` (read 2026-09-29): the meaning this change ports
  (fractions, gaps, lanes, clamping; the ramp and its totals; checkpoint
  anchors, buffers, paces, fuel totals, carb-load rows, taper weeks).
- The mirrored contract fixture `projection.v1.example.json` (2030/31):
  every golden value in `SeasonPhaseRaceTests` comes from it.

## Goals / Non-Goals

**Goals**
- See the season as one arc: which phase is now, what's next, what isn't
  planned, when the races are.
- A phase as a section with a summary: goals, rules, weeks planned vs
  run, the key sessions and tests, and a recap once it's closed.
- Everything about one race in one place before race week, including
  what to eat on the carb-load days, one tap away from that day's food
  log.
- The same meaning as the vault's planner, from the same file.

**Non-goals**: see proposal.md.

## Decisions

### D1 -- Builders on `PlanBuilder`, models in TrainingCore

The three screens are `PlanBuilder` extensions in new files, taking the
same `TrainingSource` and `today` (the training day) as Week and Month,
so they share empty states, notices, the language and the session rows:

```
TrainingCore
  Formatting/SeasonText.swift       dayMonthYear, longRange, monthTick;
                                    NumberText.clock/pace/climb/percent;
                                    phase kind/status, priority, aid names
  ViewModels/SeasonTimelineModel.swift  SeasonTimelineModel, PhaseBandModel,
                                    RaceMarkerModel, TimelineGapModel,
                                    SeasonLanes.assign; seasonTimeline()
  ViewModels/PhaseDetailModel.swift PhaseRamp (series, totals), RampWeek,
                                    PhaseDetailModel, KeySessionModel,
                                    PhaseRecapModel, TestVerdict; phaseDetail(id:)
  ViewModels/RaceDetailModel.swift  RaceDetailModel, CheckpointRowModel,
                                    CarbLoadRowModel, RacePrepMath; raceDetail(id:)
```

No SwiftUI in TrainingCore; the app's views draw the models. Every
string is a `TrainingKey` with en and cs entries.

### D2 -- Navigation: a Season segment, pushed screens, the race chip

- The Plan tab's segmented control becomes **Week · Month · Season**
  (the segment the earlier change reserved). The mode is remembered per
  install as before; Plan still opens on Week the first time.
- Season shows the timeline, then the phases and the races as rows. A
  row pushes the Phase or Race screen (`NavigationLink` with a view
  destination, inside the tab's `NavigationStack`). The Phase screen
  pushes its key sessions (the existing session detail) and its races;
  the Race screen pushes its anchoring phase and its race-day session.
- **Today's race chip opens the race's screen**: `AppRouter.openRace(id:)`
  selects Plan and sets `pendingRaceID`; `PlanTabView` switches to Season
  and pushes the race. The chip used to open Month at the race day; the
  race screen is where the countdown belongs, and the month is one tap
  from Plan. The `plan?date=` link is unchanged (Week at the date).
- Defaulted (tasks 0.2): Season as a third segment rather than a fourth
  tab. The tab bar stays at four (Today, Plan, Progress, Profile; the
  owner's A26 "4 tabs").

### D3 -- The season timeline

Ported from the planner's `seasonTimeline.ts`:

- Everything on the axis is a **fraction of the season's period**
  (`season.period`): 0 at `from`, 1 at `to`. The view multiplies by its
  width. Without a period (or with `season: null`) the screen shows "No
  season yet", never an empty axis.
- **Bands**: every phase with a period, in start order, with kind,
  status, date range, week count (the outline's length, else the
  period's weeks), whether it is the selected phase (the file's `plan`)
  and whether today falls in it.
- **Gaps**: the time before the first phase, between phases and after the
  last is a labelled gap, "No phase planned". What isn't planned is drawn,
  not hidden.
- **Races**: every season race in date order with its priority (A/B/C),
  hero, approximate date, whether a phase anchors it ("No phase covers
  this race yet" otherwise), its distance (the race's `distanceLabel`,
  else km and m+) and a countdown from today ("in 11 days", "in about 241
  days", "32 days ago").
- **Clamping**: a race or phase outside the season is clamped to the edge
  AND flagged (`isClamped`), never dropped.
- **Lanes**: labels that would overlap go on separate lanes
  (`SeasonLanes.assign`, greedy, never drops a label). The label width is
  0.22 of the axis (the planner's 0.12 is for a desk-wide view).
- **Today** is the current training day (`PlanBuilder.today`), the same
  day the race chip counts from, not the file's `asOf`; the freshness
  notices already say when the file lags. (The planner draws both; a phone
  has room for one line.)
- Drawing (app): a rounded bar per band -- the selected phase filled with
  the accent, others lighter, a draft dashed -- over a faint full-season
  track; gaps as dashed outlines; month ticks above; flags below on their
  lanes (filled flag for A or hero, outlined for B/C, the priority letter
  and "★" as text); a vertical line at today labelled "Today". The drawing
  is one VoiceOver element with a spoken summary; the rows below carry
  the detail and the navigation.

### D4 -- The phase screen and `PhaseRamp`

Ported from `phasePlan.ts`:

- **Header**: title, kind, status, date range, and where today is:
  "Week 2 of 16 · 100 days left", "Starts in 12 days", or "Finished" (a
  closed phase, or one whose period has ended), with a progress bar.
- **Goals and rules** come only with the selected phase (the file's
  `plan`). Any other phase says "Goals and rules are published for the
  current phase only." instead of showing empty sections that would read
  as empty facts.
- **Weeks** (`PhaseRamp.series`): one row per outline week, with its kind
  and note, the target and the vault's actual:
  - target = the written week's `targets.runKm`, else the outline row's
    `runKmTarget` (contract semantics 4). **Deliberate difference** from
    the planner, which prefers the outline's figure: the app's Week header
    already shows the written week's target, and the same week must not
    show two targets in one app (tasks 0.3).
  - actual = the written week's `actual.runKm`; `nil` for a future week.
    A week that has started but isn't in the file's window of written
    weeks has **no** actual and says "Not in the app's window" -- never 0.
    (The planner falls back to the vault's diary; the phone has none.)
  - bar lengths as fractions of the phase's largest figure; target drawn
    as an outline, actual filled (shape as well as colour).
- `PhaseRamp.totals` (planned total, like-for-like planned over the weeks
  with a known actual, actual total, known and unknown weeks, deloads,
  weeks within 10 % of target, the biggest week, the weekly mean) is the
  one ramp summary in the app; `add-training-stats` reuses it, so the two
  screens cannot disagree about one phase.
- **Key sessions**: the long, tempo, threshold, intervals, VO2max, test
  and race sessions of the written weeks dated inside the phase, with
  date, status and the done option; each opens the session detail. For a
  phase other than the selected one these are the window weeks that fall
  in it (usually few or none).
- **Tests**: every test result from `tests[].history` dated inside the
  phase ("Left 22 reps · Right 27 reps").
- **Races**: those anchored to the phase, and unanchored ones dated
  inside it.
- **Recap** (a closed phase, or any phase with a `recap` text): the
  vault's recap text; "Ran 22.6 of 30 km planned" (like for like); "0 of
  1 weeks within 10 % of target"; "Biggest week: 22.6 km (W41)"; one line
  per test measure measured twice or more inside the phase, first -> last,
  judged in the measure's `better` direction; the phase's races.

### D5 -- The race screen

Ported from `racePlan.ts`; the desk computes the facts, this is display
arithmetic only:

- **Header**: the countdown from today (past races: "32 days ago"), the
  date ("≈" when approximate), priority and "★" for the hero, category and
  distance, the goal, the anchoring phase (a link) or "No phase covers
  this race yet", "Race report written" when the vault links one.
- **Stub**: a race without prep, or whose prep is empty, shows "Race prep
  not written yet" (the vault's race-prep skill hasn't run).
- **Start and cutoff**: "Start 09:00", "Cutoff 5 h 30 min · 14:30".
- **Checkpoints**: name, km, m+, aid ("Full aid", "Water", "No aid"),
  target ("Target 1 h 5 min · 10:05") and cutoff with clock times from
  the start time ("+1 d" past midnight), the buffer (cutoff - target;
  "… after the cutoff" in `danger` with a warning symbol when negative),
  the **section pace** (min/km from the last checkpoint that has a target;
  the gun is km 0, minute 0 by definition; a checkpoint without a target
  gets no pace and is skipped as an anchor -- never interpolated), and the
  heart-rate cap.
- **Race fuel**: carbs per hour, how often, fluid per hour, and totals to
  the finish (rate x the last checkpoint's target: "About 208 g carbs to
  the finish", "About 1.5 l fluid to the finish") only when the finish has
  a target.
- **Carb load**: one row per `prep.carbLoad` entry on race date +
  `dayOffset`: "2 days before", grams and g/kg. Grams: inside the file's
  window, the day's own `fuel.carbsG` ("From your plan"); outside it,
  `round(g/kg x athlete.weightKg)` ("Estimated for 70 kg"; contract
  semantics 6 allows the app to recompute); without a weight, g/kg only
  and "No body weight in the plan to count grams". The vault's constant
  weight is used, not the phone's latest weigh-in (tasks 0.4).
- **Gear**: mandatory first, then the rest in written order, each tagged
  "Mandatory"/"Optional" (with a symbol, not colour alone).
- **Taper**: the anchoring phase's outline weeks from the last build week
  before the race week up to the race week, each with kind, target and
  note; the race week flagged, the current week marked. Empty for an
  unanchored race.
- **Race day in the plan**: the plan's sessions whose `raceId` is this
  race, opening the session detail.

### D6 -- Race week linked to food

Each carb-load row has an **Open food log** button (a fork-and-knife
icon with that label for VoiceOver). It calls the existing day
navigation -- `goToToday()`, then `stepDay(byDays:)` by the number of
days from the phone's today to the carb-load date -- and selects the
Today tab. Today then shows that day's food log and calorie summary and,
in the training experience, the training card with its carb-load line
("Carb load: 560 g carbs (8 g/kg)"). This is the cheap link the owner
asked for (A19); it records nothing and changes no target. The training
experience's day switcher already steps into the future, so a carb-load
day next week opens.

A carb-load calorie/carbohydrate target on the food side is a later
change (proposal Non-goals).

### D7 -- Text, accessibility and the design system

- All new display text is built in TrainingCore (`TrainingKey`, en and
  cs, plurals for days and weeks in both `.stringsdict` files) or is a
  string-literal key in the app catalog (section headers, titles, the
  segment, VoiceOver hints).
- Theme tokens only (the design-token lint): the accent for the selected
  phase and next race, `danger` only for a negative buffer, `stroke` for
  gaps and tags. Status is never colour alone: filled vs outlined, a flag
  kind, a letter, a word.
- Rows are single VoiceOver elements with spoken summaries built in
  TrainingCore; the timeline is one element listing phases, races and
  today.

### D8 -- Testing

- `SeasonPhaseRaceTests` (`swift test`), golden on the vault's example
  fixture with today = its `asOf` (Wed 23 Oct 2030): the timeline's
  fractions (363-day season), gaps, lanes, ticks, countdowns (past, near,
  approximate) and clamping; `SeasonLanes.assign`; no season; the
  selected and a closed phase (header, goals, ramp with the written
  week's target, key sessions, tests, recap and its test lines);
  `PhaseRamp.totals`; a started week outside the window; the valley race
  (checkpoint clock times, buffers, paces, fuel totals, carb load from the
  plan, gear order, taper), carb load from the weight formula and without
  a weight, a checkpoint without a target, races without prep; Czech for
  our own strings and numbers.
- Assertions never spell CLDR data that may change between OS versions
  (September's abbreviation is "Sep" or "Sept"; Czech list spacing): such
  expectations are built with `DateText` or avoided.
- App views: CI build, `check-localizations --scan`, the design-token
  lint, and the owner's device checks (tasks group 5).

## Fallbacks for private-API dependencies

None added: no Garmin route, no new vault request. With no connection
the training experience (and so the Plan tab) doesn't exist; with a
file that lacks `season`, the Season segment shows "No season yet" and
the race chip is hidden as before.

## Risks / Trade-offs

- **The phone's phase ramp is thinner than the desk's.** Weeks outside
  the projection's window show no distance on the phone (no diary). Said
  in words ("Not in the app's window"), never drawn as zero.
- **Two targets for one week across app and plugin.** The app uses the
  written week's target (as Plan -> Week does); the planner's ramp uses
  the outline's. Flagged for the owner (tasks 0.3); a one-line change
  either way.
- **Carb-load grams outside the window use the vault's constant weight**,
  not today's weight on the phone. Deliberate (the contract's formula and
  constant); flagged (tasks 0.4).
- **The timeline on a narrow phone.** Races close together stack on
  lanes; the rows below are the readable list. Checked on the device.

## Migration Plan

1. Merge after `add-training-today-and-plan` (done).
2. For the owner: Plan gains a Season segment; the race chip opens the
   race. Nothing stored changes; `plan.mode.v1` gains a third value.
3. For the fiancée (food-first): nothing changes.
4. Rollback: revert. A stored `season` mode in `plan.mode.v1` falls back
   to Week in an older build (`PlanMode(rawValue:) ?? .week`).

## Open Questions

Carried into tasks.md group 0 with defaults (built as the default and
flagged):

1. Race chip opens the race screen (default) or the month at the race
   day as before?
2. Season as a third Plan segment (default) or a fifth tab?
3. A week's target: the written week's `targets.runKm`, else the outline
   (default, matches Plan -> Week), or the outline first like the vault's
   planner?
4. Carb-load grams outside the window: the vault's `athlete.weightKg`
   (default, the contract's formula) or the phone's latest weigh-in?
5. "Today" on the timeline: the training day (default) or the file's
   `asOf`?
