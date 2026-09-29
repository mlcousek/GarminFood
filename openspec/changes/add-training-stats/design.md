## Context

Written 2026-09-29 on the branch of `add-season-phase-race-screens`
(based on `origin/main` @ `2d76ef5`), after that change's commits: it
provides `PhaseRamp` (the planned-vs-run ramp of a phase), `TestVerdict`
and the Phase screen this change links from.

What the owner decided (the vault's Winter Arc decisions log): statistics
are in (A12, A18), tests are sessions with results and history (A19),
sleep/recovery and gear mileage are out (A12), and anything computed
(adherence, the chosen option, `actual`, gate status) is computed once on
the desk and read by the app.

What the code provides: TrainingCore's decoded projection (session
`status`, `trafficLight`, `done.option`; week `targets`, `actual`,
`phaseId`; `tests[]` with measures and history), `PlanBuilder` with the
training day, `TrainingFormatting`, `PhaseRamp`; the app's Swift Charts
style (`WeightComponents`, `TrendsComponents`: Theme tokens, a static tint
per series, accessibility summaries), `OptionStyle`/`OptionCodeBadge`
(G/A/R as colour, letter and shape).

## Evidence (probes)

No live probe. Read on 2026-09-29: the vault's `Training Hub Contract.md`
(semantics 3: the done option and when it is `null`; 4: week `actual`
counts sessions done and missed over days up to `asOf`, and run km) and
the planner's `planStats.ts` (adherence over the weeks the projection
holds, outside weeks listed; the option mix with `unknown`; volume through
the phase ramp; test cards with `_l`/`_r` pairs and asymmetry |L - R| /
max(L, R); `judge` by the measure's `better`). Every golden value in
`TrainingStatsTests` comes from the mirrored example fixture.

## Goals / Non-Goals

**Goals**
- One screen that says whether the plan is being done, for the current
  phase or the season, in numbers the vault would agree with.
- Show what the phone doesn't know as unknown, never as zero.
- Tests over time, with the left/right difference the calf work is about.

**Non-goals**: see proposal.md.

## Decisions

### D1 -- `PlanBuilder.stats(scope:)` in TrainingCore

`ViewModels/StatsModels.swift` adds `StatsScope` (`.phase(id)`,
`.season`), the models and the builder. Like the other screens it takes
the `TrainingSource` and the training day; no SwiftUI. `TestAsymmetry`
holds the pairing and asymmetry arithmetic apart from the text so it is
tested on numbers.

### D2 -- Scope

- **This phase** (default: the selected phase, `defaultStatsScope()`):
  the phase's period. From the Phase screen, that phase.
- **Whole season**: the season's period (else the plan's).
- Adherence and the option split count the days of the plan file's
  written weeks that fall inside the scope; volume covers the scope's
  phases' outline weeks (season: every phase in start order, each week
  once). Tests are shown whole (a test's history spans phases), whatever
  the scope.
- With no plan (`plan: null`) or an unknown phase: the "No active plan"
  state; tests still show.

### D3 -- Adherence: counting the vault's statuses

- Per written week (inside the scope) and per phase (by the week's
  `phaseId`, else the phase containing its Monday): done, missed,
  skipped and planned sessions, as the file states them.
- **Due** = done + missed + skipped; **adherence** = done / due, shown
  as a whole percentage ("Done 90 % of the sessions due so far"); "No
  sessions due yet" before anything was due. Planned sessions (today and
  later) are shown, not counted against.
- This is counting, not computing: the vault decided every status
  (contract semantics 3); a test asserts the per-week done and missed
  counts equal the vault's own `actual.sessionsDone`/`sessionsMissed` on
  every week it counted.
- **Weeks outside the window**: every ISO week of the scope that has
  started (up to the file's `asOf`, else today) and isn't among the
  file's written weeks is listed ("Not in the app's window: W36, W37,
  W38, W39, W40"), never counted as zero. The phone has no diary to fill
  them (the planner's desk does).
- `skipped` is reserved in v1; if it appears it is due and not done, and
  the counts line adds "· 1 skipped".
- Chart: stacked bars per week (done `success`, missed `danger`, skipped
  `warning`, planned `stroke`) with a legend; rows per week and per phase
  carry the same numbers as text for VoiceOver and without colour.

### D4 -- The G/A/R split

- Over the done traffic-light sessions of the scope: how many were G, A
  and R by `done.option`, and how many are "Option not identified" (the
  vault's `null`: an anonymous run on a G/A day, contract semantics 3).
  The unknown share is shown, not spread over G and A.
- Four shares always (zero included, so the bar and rows are stable),
  each "1 session · 33 %"; "No traffic-light session done yet" when there
  are none.
- Drawn as one proportional bar in the option tints with the letter on
  each part (a "?" for unknown), and one row per share with the existing
  `OptionCodeBadge` (letter + shape).

### D5 -- Volume vs target

- `PhaseRamp.series` of the scope's phases: the same targets (the written
  week's, else the outline's) and actuals (the vault's `actual.runKm`) as
  the Phase screen, so the two can't disagree (a test compares them).
- Each week: "60.1 of 55 km" and the difference "+5.1 km (+9 %)"; a
  future week shows its target; a started week outside the window says so;
  a week with neither shows "–".
- Summary from `PhaseRamp.totals`: planned in total, run of planned over
  the weeks with a known distance, weeks within 10 %, the weekly mean.
- Chart: grouped bars per week, target light and run solid (legend
  "Target"/"Run").

### D6 -- Tests and asymmetry

- One card per test in `tests[]` (every `kind: test` workout), in the
  file's order: its title, "No results yet" when its history is empty.
- Per measure: its points (date, value), the latest ("22 reps"), first ->
  last ("18 → 22 reps") and the verdict judged in the measure's `better`
  direction ("Improved", "Worse", "Unchanged"; none without a direction).
- **Asymmetry**: measures whose keys are `<stem>_l` and `<stem>_r` are
  paired (the vault's convention for single-leg tests); on every date
  with both, |L - R| / max(L, R), shown as "L 22 · R 27 · 19 %", and the
  latest as "Asymmetry 19 %". The labels are the measures' own ("Left",
  "Right"; Czech "Levá", "Pravá"); the compact line uses L/R (Czech L/P).
- Chart: one line per measure over the result dates, with symbols per
  series.

### D7 -- Navigation, text, accessibility

- **Plan toolbar**: a Statistics button (chart symbol) next to the habit
  ladder, opening the current phase's statistics; the **Phase screen**
  links to its own. Defaulted (tasks 0.1): not a fourth Plan segment --
  Week · Month · Season stay about the calendar, statistics are a
  drill-down.
- A **This phase / Whole season** picker on the screen.
- Every chart is hidden from VoiceOver and duplicated by rows with
  spoken summaries built in TrainingCore; colour is never the only
  signal (legends, letters, words).
- All new text is `TrainingKey` (en/cs; the sessions count is a plural)
  or an app catalog key (section headers, picker, chart axis names).

### D8 -- Testing

`TrainingStatsTests` (`swift test`), golden on the example fixture
(today = `asOf`): phase adherence (per week, totals, summary), season
adherence (per phase, the outside weeks W36-W40) in English and Czech,
counts agreeing with the vault's `actual`, a `skipped` mutation, the
G/A/R split (A 1, R 1, unknown 1; an empty scope), volume rows and
summary and their equality with the Phase screen's ramp, the season
volume, the calf test's history, verdicts and asymmetry (25 % then 19 %)
in both languages, the empty time-trial test, asymmetry and verdict
arithmetic, and the states without a plan.

## Fallbacks for private-API dependencies

None added: no Garmin route, no new vault request.

## Risks / Trade-offs

- **Adherence covers only the file's window** (about six weeks). Early in
  a phase that is most of it; for a season it is a small part, and the
  screen lists the weeks it can't see. A longer history would need the
  vault to publish per-week counts beyond the window (a contract
  addition, not this change).
- **"Due" excludes today's planned session** until the vault marks it;
  the percentage moves once a day with the file. Stated as "so far".
- **Charts on small screens** with many weeks (a whole season) get dense;
  the rows below are the readable form.

## Migration Plan

Additive: a new screen and two entry points. Rollback: revert.

## Open Questions

Carried into tasks.md group 0 with defaults:

1. Statistics from a Plan toolbar button and the Phase screen (default)
   or as a fourth Plan segment?
2. Default scope: the current phase (default) or the whole season?
3. Adherence as done / (done + missed + skipped) (default), or also
   counting today's still-planned session?
