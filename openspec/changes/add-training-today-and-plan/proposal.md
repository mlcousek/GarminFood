## Why

The owner's training plan is the heart of the renamed app (his decisions
A11 and A18, 2026-09-28). Every run day of his winter plan has up to three
prepared options on the watch: **G** (the planned session), **A** (easier)
and **R** (an alternative without running). He picks one each morning from
how he feels (a green, amber or red morning check, decision T6). The
vault on his PC plans the weeks, tracks habits and publishes the result as
one generated file, the **projection** (`projection.v1.json`).

`rebrand-to-jirkas-arc` gives the app a training experience with a Plan
tab, and `add-vault-connection` fetches the projection safely. Nothing yet
turns that file into something he can read half-awake before an early run. This
change does: a training-first **Today** and a **Plan** tab, read-only, on
top of a new domain package that decodes the projection tolerantly.

The contract is now fixed. The vault's `add-training-plan-model` change
defines the final projection v1: `plan` is the selected training phase,
a `season` lists every phase and race (with structured race preparation),
weeks carry their own phase, actual volume and the weekly AI note, days
carry carb-load fuelling and unplanned activities, sessions carry a title,
a *why*, a workout, targets, fuelling and test results, and a workout
library and test history sit at the top level. Several fields are reserved
(present but empty) until later vault changes fill them: the morning light,
the watch state, a session's origin and rule notes. The app reads exactly
that contract, tolerates anything it doesn't know, and mirrors the vault's
two synthetic contract fixtures.

## What Changes

- **New SPM package `TrainingCore`** (the training domain; never imports
  SwiftUI; depends on `VaultKit` for the transport and on `GarminKit` for
  the shared store helpers):
  - Codable models for the **final projection v1** contract. Decoding is
    tolerant: unknown fields are ignored, unknown enum values decode as
    `.unknown`, a broken element of a list is dropped and counted rather
    than failing the file, and a major version above 1 is a loud "update
    the app". Reserved fields already have model slots.
  - `ProjectionStore`: decodes the cached projection at launch, validates
    fresh downloads before `VaultKit` commits them, keeps the last good
    copy, and reports freshness and problems.
  - Pure view-model builders for every screen, taking an *effective plan*
    rather than the raw file, so later check-ins and plan edits slot in as
    an overlay without changing the screens.
  - Localized formatting (distances, durations, heart-rate targets in the
    athlete's zones, countdowns) in English and Czech.
- **Today (training experience), read-only**, as new cards on the existing
  card screen, leading it:
  - **the day's session(s)** with the three option cards G / A / R: label,
    targets, the done option highlighted (and, once the vault publishes
    them, the watch state and the morning light), plus the day's
    carb-load or session fuelling;
  - **today's habits**, display only;
  - **the next A (or hero) race** as a countdown chip;
  - **the weekly AI note** teaser (the week's `aiNote`);
  - the existing **food cards** below: the calorie summary (compact by
    default), "Log again" quick picks, meals, "Log a meal", weight and
    water, so a food still logs in two taps.
- **Plan tab**, read-only: a **week agenda** (planned vs done per day and
  session, unplanned activities, week targets vs the vault's `actual`), a
  **Garmin-style month calendar**, a **session detail** (the options, their
  workout steps, targets in the athlete's heart-rate zones, the *why*, the
  done activity, fuelling, and test results against the test history), and
  the **habit-ladder status**.
- **Wiring**: the training experience turns on when the vault connection is
  enabled (the preview toggle from `rebrand-to-jirkas-arc` is removed);
  `VaultKit`'s validator becomes the projection decoder; `garminfood://plan`
  opens the right week.
- **Contract mirror**: the vault's two synthetic contract fixtures
  (`projection.v1.example.json`, `projection.v1.minimal.json`) copied
  verbatim into the app repository, with golden decode and builder tests,
  plus small app-authored mutations of them for the edge cases.
- All new text in English and Czech.

## Capabilities

### New Capabilities

- `training-projection`: reading, validating and keeping the vault's
  projection; versioning, tolerance, freshness and localized content.
- `training-today`: the training cards on Today and their relation to the
  food cards and the food-first experience.
- `training-plan-view`: the Plan tab's week agenda, month calendar, session
  detail and habit-ladder status.

### Modified Capabilities

None. `experience-shell` (from `rebrand-to-jirkas-arc`, unarchived) already
specifies that the training experience turns on with an enabled vault
connection; this change supplies that input.

## Non-goals

- **Writing anything**: morning check-ins, habit ticks, RPE and notes, the
  lock-screen green/amber/red Controls, local notifications. Owned by
  `add-training-checkins`. The view models expose disabled slots for them
  (design D8).
- **Editing the plan** (move, swap, skip) and the pending-edit overlay.
  Owned by `add-plan-editing`.
- **Season, phase and race screens**, race preparation, and linking
  race-week fuelling to the food targets. Owned by
  `add-season-phase-race-screens`. Here the countdown chip only links to the
  race day in the month calendar, and fuelling is shown as text.
- **Training statistics.** Owned by `add-training-stats`.
- **Running the traffic-light rules, matching activities to sessions or
  computing adherence and weekly volume** on the phone. Everything computed
  is computed once, on the vault side, and read here.
- **Approving next week** from the weekly note. Owned by a later
  `add-week-approval`.
- **Writing Garmin workouts.** The vault side owns the watch calendar.
- **Background refresh** of the projection; foreground only, as in
  `add-vault-connection`.
- **Training gamification.** Later (`add-training-gamification`).

## Impact

- New `ios/TrainingCore/` package: models, `ProjectionStore`, builders,
  formatting, `Resources/{en,cs}.lproj`, tests and mirrored contract
  fixtures.
- `AppearanceKit`: four new `TodayCardID` cases (`raceCountdown`,
  `trainingDay`, `habitsToday`, `weeklyNote`), the training catalog and its
  default order, a `training` layout preset, and a distinctness test for
  the three readiness colours in every theme. The food-first catalog is
  unchanged (golden test).
- App: `GarminFood/Training/` (the observable model, the four Today cards,
  option cards), `GarminFood/Plan/` (week, month, day sheet, session
  detail, habit ladder), `TodayView` (new arms, title), `ContentView`
  (experience input), `AppRouter` (plan date), `VaultServices`
  (projection store, validator), removal of the preview toggle.
- `ios/project.yml`: `TrainingCore` package, app target only.
- `.github/workflows/build.yml`: "Run TrainingCore unit tests".
- `tools/check-localizations.mjs`: `TrainingCore` added to `PACKAGES`.
- No Garmin route, no vault write, no new store file (the projection bytes
  live in `VaultKit`'s cache).

**Depends on**:
- `add-vault-connection` (transport, cache, settings, loud failures);
- `rebrand-to-jirkas-arc` (the training experience, the Plan tab, the
  experience-dependent Today catalog);
- the vault's `add-training-plan-model`: its projection v1 contract is
  final; the merge waits for its two contract fixtures to be mirrored
  (tasks group 1).

**Unblocks**: `add-training-checkins` (fills the check-in and habit slots),
`add-plan-editing` (supplies the overlay), `add-season-phase-race-screens`
and `add-training-stats`.
