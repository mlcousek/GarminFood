## Context

Written 2026-09-28 against `origin/main` @ `a4ee380`, planned together with
`rebrand-to-jirkas-arc` and `add-vault-connection`, which it builds on.
Reconciled the same day with the vault's **final projection v1 contract**
(see Evidence).

What the owner decided (2026-09-28):

- The vault is the source of truth (A1); the app is the daily surface
  (A2); the plan is the heart of the app (A11).
- Screens (A18): Today, Plan (week and month, session detail with the
  *why*), later Season, Phase, Race and Statistics, plus food and weight.
- Also in (A19): tests as sessions with results, the weekly AI note (with
  approval later), race-week fuelling linked to food, lock-screen
  green/amber/red buttons (later).
- Morning traffic light (T6): up to three options per run day, G/A/R, all
  already on the watch; the pick is the morning check. The light (how he
  felt) and the executed option (what he did) are separate facts.
- Anything computed (adherence, rules, the chosen option, gate status,
  planned-vs-done matching) is computed once on the vault side and read by
  the app and the plugin; the phone never recomputes it.

What the code provides:

- Today is a card screen driven by AppearanceKit's `LayoutCatalog`, with a
  user-editable order, visibility and variants, presets, and
  `LayoutResolver` rule 3 (a card new to the catalog is inserted right
  after its nearest predecessor in the default order).
  `rebrand-to-jirkas-arc` makes the catalog depend on the experience.
- The day switcher on Today (`dayLog.selectedDate`, `isToday`).
- Design system: `Theme` tokens (`success`, `warning`, `danger`, `accent`,
  card styles), `EmptyStateView`, `SectionHeader`, `StatTile`,
  `ProgressRing`; the design-token lint forbids literal colours.
- `add-vault-connection`: `VaultTransport`, `ConditionalFileSync` (commit
  only after a validator accepts), `VaultStatus`, the loud banner.

## Evidence (probes)

No live probe: this change reads one file through `add-vault-connection`,
whose probes (its tasks 1.x) cover GitHub.

The contract evidence is the vault's `add-training-plan-model` change, read
on 2026-09-28: its design's "Contract — `projection.v1.json`" section
(schema plus the table of every deviation from the earlier draft) and its
`hub-projection` spec. The contract is **final** for v1. Its executable
form (a validator and two synthetic fixtures,
`projection.v1.example.json` and `projection.v1.minimal.json`) is being
built in the vault; tasks group 1 mirrors the fixtures once they exist.

Three deviations from the earlier draft change meaning, and the app reads
them accordingly:

| # | Draft | Final v1 | What the app does |
|---|---|---|---|
| 1 | `plan` = the whole plan | `plan` = the **selected phase**; its `weeks` may belong to an adjacent phase and each carries `phaseId`; a top-level `season` lists every phase and race | Week headers name the week's own phase (from `season.phases`); paging spans the season |
| 3 | `generatedAt` = run time | `generatedAt` = when the **content** last changed; `asOf` = the training day the file describes | Freshness uses the last sync and `asOf`, never `generatedAt` (D5) |
| 15 | `done.option` always set, `source: "activity-name"` | `done.option` **nullable**; `source` `"sport-inferred"` or `null`; `matchedBy`; a richer activity | A done session without an option is shown as done with no option highlighted (D7) |

Two optional fields are being added to v1 as this is written and are
treated as final and optional: `days[].habitsDone { habitId: count } |
null` and `targets.hrMin`.

## Goals / Non-Goals

**Goals**
- Read the plan before an early run in two seconds: today's session, its
  three options, the targets in his zones.
- Planned vs done for the week and the month, like Garmin's calendar.
- Never break on a projection the app doesn't fully understand; say so
  loudly only when the app is too old for it.
- View models that later changes extend instead of rewriting.
- The food-first experience, and so the fiancée's install, unchanged.

**Non-goals**: see proposal.md.

## Decisions

### D1 — `TrainingCore`: the training domain package

```
TrainingCore  (depends on VaultKit, GarminKit; Foundation only; no SwiftUI)
  Contract/     ProjectionHeader, Projection v1 models, OpenEnum, LossyArray,
                LocalizedText, LocalDate, ISOWeek, ClockTime, DecodeIssues
  Store/        ProjectionStore (decode cached, validate fresh, last good,
                freshness)
  Plan/         EffectivePlan (+ PendingOverlay, empty here), TrainingDay
                (day boundary), HRZoneMapper
  ViewModels/   TodayTrainingModel, SessionCardModel, OptionCardModel,
                HabitRowModel, RaceChipModel, WeeklyNoteTeaserModel,
                WeekAgendaModel, MonthCalendarModel, SessionDetailModel,
                HabitLadderModel, TrainingFreshnessModel, builders
  Formatting/   TargetFormatter, StepFormatter, CountdownFormatter,
                FuelFormatter
  Resources/    en.lproj, cs.lproj (Localizable.strings, .stringsdict)
```

- The boundary rule of the repository applies: the app's views go through
  TrainingCore, never through VaultKit, for anything training-shaped.
  TrainingCore never imports SwiftUI (Observation is allowed, as GarminKit
  already uses it).
- Linked into the **app target only**; the widget has no training content
  (it can't read the app's data on a free account anyway).
- Localized strings follow the package convention: `String(localized:
  bundle: .module)`, keys in both `.lproj` tables, `.stringsdict` for
  plurals (Czech one/few/many/other). `TrainingCore` is added to
  `tools/check-localizations.mjs`'s `PACKAGES`.

### D2 — Reading projection v1 tolerantly

**Two-step decode.** `ProjectionHeader` (`schema`, `schemaVersion`,
`generatedAt`, `asOf`) is decoded first:

| Header | Result |
|---|---|
| `schema` ≠ `"hub.projection"` | `.invalid("not a plan projection")`; last good kept |
| `schemaVersion` > 1 | `.unsupportedMajor(found)`: **loud** "Update Jirka's Arc to read this plan"; last good kept and shown as "as of <date>" |
| `schemaVersion` = 1 | full decode |
| `schemaVersion` missing or < 1 | `.invalid` |

The file name carries the major (`projection.v1.json`) and the vault writes
`v1` and `v2` side by side during a breaking change, so a higher major
*inside* the v1 file means something went wrong; the loud message is right.
A `supersededBy { schemaVersion, minAppBuild }` hint is **not** part of v1;
the app tolerates it as an optional unknown-to-the-contract field and, if
it ever appears, shows a quiet "A newer app version reads more of your
plan". Nothing depends on it.

**Tolerance rules** (the contract's own consumer rule: ignore unknown
keys, decode unknown enum values as unknown):

- **Unknown fields are ignored** (synthesised `Codable` already does this;
  custom `init(from:)` keeps it).
- **Identity is required, everything else is optional in decoding**, even
  where the contract promises presence: a session needs `id`; a week needs
  `week`, `from`, `to`; a day needs `date`; an option needs `code`; a habit
  needs `id`; a race needs `id` and `date`; a workout needs its map key.
  The contract's "absent facts are `null`" and "lists are `[]`" both decode
  to the same Swift optionals and empty arrays.
- **Open enums**: `OpenEnum<Known>` decodes an unknown string as
  `.unknown(raw)`, never throws. Used for session `sport`, `type` (closed in
  v1, still open here), `slot`, `status`; week `status`; outline `kind`;
  phase `kind` and `status`; option `code`; day `light`; `done.source` and
  `done.matchedBy`; activity `group`; race `priority`; checkpoint `aid`;
  workout `kind`; step `kind`; measure `better`; habit `schedule.kind`,
  `source`, `state`; day `fuel.kind`.
- **Lossy lists and maps**: `LossyArray<T>` / `LossyMap<T>` drop an element
  that fails to decode and record it in `DecodeIssues` (path + reason,
  English). The file still loads; Diagnostics gets one summary line per
  fetch ("2 sessions skipped: missing id").
- **Localized text** (`LocalizedText`) decodes either a plain string or an
  object of language codes. The contract's key is `cz`; the app resolves it
  for its `cs` locale: `cs`, then `cz`, then `en`, then the first non-empty
  value; for English `en`, then any. Plain strings (habit `dose` and
  `why`, race `name`, `goal`) show as they are.
- **Formats**: `LocalDate` (`YYYY-MM-DD`, local to `athlete.tz`),
  `ISOWeek` (`YYYY-Www`), `ClockTime` (`HH:MM`), timestamps ISO 8601 with
  offset, durations in integer minutes, distances in km, heights in m.
  A malformed value drops its element (lossy), never the file.
- **Ids are opaque** (`2026-w43-tue-am`): never parsed for a date, week or
  slot; those come from their own fields.

Any other decoding failure of the whole document (not JSON, not an object,
a top-level section of the wrong type) is `.invalid(reason)`: last good
kept, one Diagnostics line, and a quiet notice on Plan (D11).

### D3 — The model (final projection v1)

Field names and locations follow the vault contract exactly. `?` marks a
value that may be `null`; `[]`/`{}` mark lists and maps that are empty
rather than absent. **R** marks fields the contract reserves (always
present, always empty in v1): decoded, never displayed in this change.

```
Projection
  schema, schemaVersion, generatedAt, generator, asOf
  athlete    tz, dayBoundaryHour, hrMax?, weightKg?, hrZones? { z1…z5: [lo, hi] }
  season?    id, title, period { from, to }, goal?,
             phases[]  PhaseSummary
             races[]   Race                                   (date order)
  plan?      PhaseSummary                                     (the SELECTED phase)
             + goals[] { id, en, cz }, rules[] { id, en, cz }, weeks[] Week
  workouts   { <workoutId>: Workout }
  tests[]    TestHistory
  habits     gate { adherencePct, windowDays }, ladder[] Habit
  acks {} R, outcomes [] R, rejected [] R

PhaseSummary  id, title, period { from, to }, kind (base|build|specific|taper|transition),
              status (draft|active|closed), outline[] OutlineWeek, recap?
OutlineWeek   week, runKmTarget?, kind (build|deload|taper|race|transition|recovery), note?
Week          week, from, to, phaseId, status (proposed|approved|closed), revision,
              absorbed {} R, targets { runKm?, sessions },
              actual? { runKm, sessionsDone, sessionsMissed }, aiNote?, days[7] Day
Day           date, light? R (always null in v1), habitsExpected[],
              habitsDone? { <habitId>: count }                (being added; optional)
              fuel? { kind: carb-load, raceId, carbsGPerKg, carbsG },
              sessions[] Session (am before pm, then id), unplanned[] ActivityRef
Session       id, slot (am|pm), sport, type, title, why?, workout?, targets Targets,
              status (planned|done|missed|skipped), trafficLight, options[] Option (G, A, R),
              done? Done, origin? R, ruleNotes [] R, raceId?, fuel? { carbsPerHour },
              test? { workout, result? { <measureKey>: number }, note?, ref? }
Targets       km?, min?, hrMax?, zone? ("Z2"), hrMin?        (hrMin being added; optional)
Option        code (G|A|R), workout, label, sport, targets Targets, watch? R (null until the push change)
Done          option? (G|A|R), source? (sport-inferred), matchedBy (date-sport-group|test-result),
              activity? ActivityRef
ActivityRef   note, sport, group, start?, km?, min?
Workout       id, sport, kind (session|test), title, why?, targets, steps[] Step,
              measures[] { key, unit, better (higher|lower), label }
Step          kind (warmup|active|interval|recovery|cooldown|exercise|hold|rest),
              km?, min?, sec?, times?, recoverMin?, recoverSec?, zone?, hrMax?, hrLo?, hrHi?,
              pace?, name?, sets?, reps?, tempo?, load?, side?, note?
TestHistory   workout, title, measures[], history[] { date, sessionId, values { key: number }, note? }
Race          id, name, date, dateApprox, priority (A|B|C), hero, phaseId?, folder, category?,
              distanceLabel?, distanceKm?, elevationM?, goal?, prep? Prep, report? { note }
Prep          note, startTime?, cutoffMin?, checkpoints[] { name, km, dPlusM, aid?, cutoffMin?,
              targetMin?, hrCap? }, fuel { carbsPerHour?, intervalMin?, fluidMlPerHour? },
              carbLoad[] { dayOffset, carbsGPerKg }, gear[] { item, mandatory }
Habit         id, step, icon, label, dose, why?, schedule, source (daily-note|activity|plan),
              state (active|next|later), started?, earliest,
              window14? { done, expected, pct, recordedDays }, gateMet?, gateBlockedBy? R
Schedule      daily { perDay } | weekly { days[] } | weeklyCount { times } |
              everyNWeeks { n, day, anchor } | withSessions { sport, types[] }
```

- Vault paths inside the file (`folder`, `note`, `ref`) are decoded but
  never shown or opened; the phone has no vault checkout.
- Race `prep`, `report`, phase `recap`, plan `goals` and `rules`, `tests[]`
  history and `weightKg` are decoded now and used only where D4 says; the
  race and phase screens (`add-season-phase-race-screens`) and statistics
  (`add-training-stats`) read the rest.
- The schedule kinds are written in camelCase (`weeklyCount`,
  `everyNWeeks`, `withSessions`) in the contract's schema; the decoder also
  accepts the snake_case spellings as aliases, since both have appeared in
  the planning notes (tasks 1.3 confirms against the fixtures).

### D4 — Which fields each screen depends on

"If absent" covers `null`, an empty list and a missing key alike; nothing
makes the file fail.

| Screen / element | Fields | If absent |
|---|---|---|
| Any training screen | `schema`, `schemaVersion` | invalid / update-app (D2) |
| Freshness line | `asOf` + VaultKit's last successful sync | "Plan date unknown" |
| Training day resolution | `athlete.dayBoundaryHour`, `athlete.tz` | 0 (midnight), the device's zone |
| "No active plan" state | `plan` (and `season`) | `plan: null` → "No active plan" on Today and Plan |
| Today: session card | `plan.weeks[].days[].sessions[]`: `id`, `slot`, `sport`, `type`, `title`, `status`, `targets`, `trafficLight`, `options[]` | "Rest day" (day with no sessions in a week that exists), "Week not written yet" (outline only), "No active plan" |
| Today: G/A/R option cards | `options[]`: `code`, `label`, `sport`, `targets`; `watch` (reserved, `null` in v1) | one card from the session's `title` and `targets`; no watch line while `watch` is `null` |
| Today: highlighted option | `done.option`, else `days[].light` (reserved, `null` in v1) | no highlight; a done session with `done.option: null` shows "Done" with no option marked |
| Today: fuel line | `days[].fuel` (carb load), sessions' `fuel.carbsPerHour` | no line |
| Today/Plan: targets in zones | `targets.hrMax`, `targets.hrMin`, `targets.zone` + `athlete.hrZones` | bpm without a zone label; no heart-rate text without a heart-rate target |
| Today: habits card | `days[].habitsExpected[]` + `habits.ladder[]` (`label`, `icon`, `dose`, `schedule`, `window14`, `gateMet`) | card hidden |
| Today: habit done count | `days[].habitsDone` | no count shown |
| Today: race chip | `season.races[]`: `name`, `date`, `dateApprox`, `priority`, `hero` | chip hidden (also when `season` is `null`) |
| Today: weekly note teaser | `plan.weeks[].aiNote` | card hidden |
| Plan week: header | `weeks[]`: `week`, `from`, `to`, `phaseId`, `status`, `targets`, `actual`; the week's phase from `season.phases[]` (else `plan`): `title`, `outline[]` row (`kind`, `note`) | fewer header lines; `actual: null` → no progress line |
| Plan week: day rows | `days[]` (always 7): sessions as Today, `unplanned[]` | a day with neither shows "Rest" |
| Plan week: paging | `season.period` and every phase's `outline[]`, else `plan.period` and `plan.outline[]` | the window weeks only |
| Plan month grid | window weeks' `days[].sessions[]` (`sport`, `status`), `unplanned[]`, `light`; outline rows' `runKmTarget`; race dates from `season.races[]` | outline-only rows show the week target |
| Session detail: options, targets | as Today | as Today |
| Session detail: steps | `workouts[<option or session workout>].steps[]` | "Steps not published" |
| Session detail: why | `session.why`, then the workout's `why`; `ruleNotes[]` (reserved, `[]` in v1) | omitted |
| Session detail: origin | `origin` (reserved, `null` in v1) | omitted |
| Session detail: done | `done.option`, `done.source`, `done.matchedBy`, `done.activity` (`sport`, `start`, `km`, `min`) | omitted |
| Session detail: test | `type: test`, `test.result` labelled by `workouts[test.workout].measures[]`; the previous values from `tests[].history[]` | "No result yet" |
| Session detail: race day | `raceId` → `season.races[]` name and date | omitted |
| Habit ladder | `habits.gate`, `habits.ladder[]` (all Habit fields) | "No habits in this plan" |

### D5 — `ProjectionStore`: last good, validate fresh, report freshness

- **Validator**: `ProjectionStore.validate(bytes)` runs the D2 decode and
  throws for `.invalid`/`.unsupportedMajor`; `add-vault-connection`'s
  `ConditionalFileSync` then keeps the last good bytes and remembers the
  rejected ETag. So a bad or too-new file never replaces a good one.
- **Launch**: decodes `ConditionalFileSync.cachedBytes` off the main actor.
  A cold launch offline shows the last plan in well under a second.
- **State** (`ProjectionState`): `.notConnected`, `.waitingForFirstSync`,
  `.notGenerated` (repository reachable, file 404), `.loaded(snapshot)`
  with `issue: .none | .stale | .behind | .invalid(reason, since) |
  .unsupportedMajor(found)`.
- **Freshness never uses `generatedAt`**: the vault writes the file only
  when its content changes, so `generatedAt` can be days old on a perfectly
  current plan. Two signals instead:
  - **`asOf` behind today** (`.behind`): the file describes an earlier
    training day than the phone's, so today's statuses may lag (a run done
    this morning still shows "planned"). Shown as "Plan as of Tue 20 Oct".
  - **No successful sync for 24 hours** (`.stale`, tasks 0.3): "Last synced
    2 days ago".
  Both are subtle lines, never banners. Auth problems are already loud
  through `add-vault-connection`.
- **No new store file**: the only copy of the projection is VaultKit's
  cache (excluded from backups; the vault is the system of record).

### D6 — Dates: the training day and the week

- **Training day**: `TrainingDay.resolve(selectedDate:isToday:now:
  boundaryHour:timeZone:)`. On today's date, a time before
  `dayBoundaryHour` belongs to the previous day, so at 00:40 after a late
  evening the card still shows the evening session. On any other selected
  date, it is that date.
- **Time zone: the projection's `athlete.tz`**, because the contract's
  dates and `asOf` are local to it and the app's "today" must line up with
  them. The device's zone is the fallback when `tz` is absent or unknown to
  the system. Owner may override (tasks 0.5).
- **Today follows the day switcher**: stepping to tomorrow on Today shows
  tomorrow's session, so the evening "what's tomorrow?" look needs no tab
  switch.
- **Weeks are ISO weeks, Monday first**, matching the plan's week keys and
  the contract's seven days per week; the month grid is Monday-first in
  both languages.

### D7 — Today in the training experience

Four new `TodayCardID`s in AppearanceKit, only in
`LayoutCatalog.today(for: .training)`:

| Card | Variants | Default | Shown when |
|---|---|---|---|
| `raceCountdown` | — | visible | a future race qualifies (below) |
| `trainingDay` | `options` (G/A/R cards), `compact` (one line per session) | `options` | always in training (it shows the state: loading, waiting, rest day, …) |
| `habitsToday` | — | visible | the day expects habits |
| `weeklyNote` | — | visible | an `aiNote` exists for this or an earlier window week |

**Default training order** (nothing stored): day switcher (pinned) ·
`raceCountdown` · `trainingDay` · `habitsToday` · `weeklyNote` · summary
(**compact** by default here) · Log again · meals (expanded) · weight &
water · Log a meal · progress strip · fasting · supplements · banners ·
day note · signature (pinned).

- **An existing stored layout** (the owner may have customised Today):
  `LayoutResolver` rule 3 inserts the four training cards right after the
  day switcher, in that order, and leaves every food card where he put it,
  with his variants. No layout is ever rewritten silently.
- **Presets**: a new `training` preset equal to the default training order,
  offered only in the training experience. Full, Minimal and Athlete keep
  their food layouts, with the training cards inserted at the top by rule
  3.
- **The food-first catalog is unchanged** (golden test). Training cards are
  not in it, so a food-first editor never lists them and a food-first
  Today never renders them; a stored placement for one is kept, not
  rendered (rule 2).
- **Quick food logging stays**: "Log again", the toolbar "Log a food" and
  meal "Add food" behave exactly as before. The weight quick-add is the
  existing weight & water card.
- **Title**: "Today" (from `rebrand-to-jirkas-arc`).

**Card behaviour**, all read-only:

- `trainingDay`: one block per session (am before pm, as the file orders
  them). Header: slot, sport symbol, the session `title`, a status chip
  (planned / done / missed; `skipped` is reserved and shown if it ever
  appears), a "Test" or "Race" badge for those `type`s, the morning light
  when the file ever carries one. For a traffic-light session (`options`
  non-empty), **three option cards** side by side (stacked at large Dynamic
  Type): the code chip, the option `label`, 1–2 target lines ("12 km · ≤144
  bpm (Z2)") and, once `watch` is published, the watch state. A session
  without options shows its own `title` and `targets` as one card. Tapping
  any card opens the session detail at that option.
- **Fuel**: a carb-load day shows "Carb load: 680 g carbs (8 g/kg)"; a
  session with `fuel` shows "Fuel: 60 g carbs/h" in its block. Display
  only; linking them to the food targets is later.
- **Highlight**: the done option (with a check), else the option matching
  the morning light (G↔green, A↔amber, R↔red), else none. In v1 the light
  is always `null` and `done.option` is often `null` (G and A are both runs
  and can't be told apart by sport), so most done run days show "Done"
  without a marked option; a ride on a run day shows R marked. The reason is
  part of the model (`.done`, `.morningLight`), so a later check-in adds
  `.pendingCheckIn` without view changes.
- The loading, waiting, not-generated, rest-day, not-written and no-plan
  states each get a designed empty state, not a spinner forever.
- `habitsToday`: one row per expected habit: icon, label, dose, schedule in
  words ("twice a day", "Mon and Wed", "once a week", "every 2 weeks",
  "with easy runs"), a small 14-day ring (`window14.pct` against the gate;
  "not recorded yet" when `window14` is `null`), and the day's done count
  ("1 of 2") when `habitsDone` has it. No checkboxes (D8).
- `raceCountdown`: the next future race in `season.races` with **priority A
  or `hero: true`** (tasks 0.4), as a chip: "🏁 <name> · in 23 days" /
  "tomorrow" / "today"; "about" before the count when `dateApprox`.
  Tapping opens Plan → Month at the race date.
- `weeklyNote`: the `aiNote` of the current week if it has one, else of the
  latest earlier window week that has one; shows the week label and the
  first two lines in the app's language; tapping opens a sheet with the
  full text (plain text, read-only). Which week a Sunday note is attached to
  is confirmed against the fixtures (tasks 1.3).

### D8 — Built to be extended: check-ins and editing slot in

Builders never read the raw file. They take a `TrainingSnapshot`:

```swift
struct TrainingSnapshot {
    let asOf: LocalDate?
    let athlete: Athlete
    let season: Season?
    let plan: EffectivePlan?         // the selected phase's weeks ⊕ overlay
    let workouts: [String: Workout]
    let tests: [TestHistory]
    let habits: HabitLadder
    let freshness: TrainingFreshness
    let capabilities: TrainingCapabilities   // everything false here
}
```

- `EffectivePlan` is built from `plan` plus a `PendingOverlay` (always empty
  in this change). `add-plan-editing` fills the overlay with the phone's
  unacknowledged commands through its `PlanEditApplier`; every screen then
  shows the moved or skipped session with its pending badge, without a
  builder change. `SessionCardModel.pendingBadge` exists and is always
  `nil` here.
- `TrainingCapabilities` (`canCheckIn`, `canTickHabits`, `canEditPlan`,
  `canRateSession`) is all `false`. `add-training-checkins` turns on the
  first two: the option cards become tappable check-in targets
  (`OptionCardModel.action` goes from `.openDetail` to `.checkIn`), and
  `HabitRowModel.tick` goes from `.displayOnly` to `.tickable(done:target:)`.
  The lock-screen Controls reuse the same check-in path.
- The reserved fields (`light`, `watch`, `origin`, `ruleNotes`, `acks`,
  `outcomes`, `rejected`, `absorbed`) already have model slots, so the
  ingest, Garmin-push and command changes only change what the vault
  writes, not the app's models.

### D9 — The option cards: colour is never the only signal

- G, A and R use the theme's `success`, `warning` and `danger` tokens as a
  tinted card background and chip fill, and **also** differ by the letter
  and a shape: G `circle.fill`, A `triangle.fill`, R `square.fill`. With
  "Differentiate Without Color" on, the shapes grow and the tint drops.
- AppearanceKit gets a test that `success`, `warning` and `danger` are
  pairwise distinct (OKLab distance above the policy threshold) in every
  resolved palette of every theme × scheme × contrast. A theme that fails
  gets its roles fitted, as `AccentAdjuster` does for accents; no literal
  colour enters the app (the lint stays clean).
- Text sits on the card surface in `.primary`/`.secondary`, never on the
  saturated fill, so contrast doesn't depend on the traffic colour.
- VoiceOver reads each card as one element: "Option A, easier: easy 8 km
  flat, 8 kilometres. Done." Code letters are spelled with their meaning,
  not just "A".

### D10 — The Plan tab

A segmented control **Week · Month** at the top (a third segment, Season,
is reserved for `add-season-phase-race-screens`), remembered per install.

**Week agenda** (`WeekAgendaModel`):

- Header: the week's phase title (looked up by `phaseId` in
  `season.phases`, else `plan.title`), "W43 · 19–25 Oct", the week's status
  (Proposed / Approved / Closed), the outline row's kind (Build / Deload /
  Taper / Race / Transition / Recovery) and note, and targets vs `actual`
  ("Run 34 of 60 km", "5 done · 1 missed of 9"). `actual: null` (a week
  that hasn't started) shows the targets only. Nothing is summed on the
  phone.
- Seven day rows (the file always has seven), Monday first: weekday and
  date, the morning light dot when present, each session as a row (sport
  symbol, title, key target, status chip, the done option or "Done"), the
  day's fuel, and each **unplanned** activity as a muted row ("Unplanned
  ride · 12.4 km · 45 min"). Today is marked. Tap a session → detail.
- Paging: previous/next week across the season (every phase's outline),
  else across the plan's period. Window weeks show sessions; weeks only in
  an outline show "Sessions for this week aren't written yet" with the
  target and kind; weeks outside every phase show "No plan for this week".
- Opening `garminfood://plan?date=…` (or the race chip) selects the week
  or month containing the date.

**Month calendar** (`MonthCalendarModel`), Garmin-style:

- A 6×7 grid, Monday first, with an ISO week column on the left showing
  "W43" and the week's run-km target.
- Each day cell: the day number, up to three sport glyphs (+n beyond),
  styled by status: done = filled accent, planned = outlined, missed =
  `danger` outline, skipped = tertiary with a strike, unplanned = small
  muted glyph, unknown = secondary. A small dot for the morning light, a
  flag for a race day, a ring for today, dimmed days outside the month.
- Tap a day → a sheet with that day's session and unplanned rows → session
  detail.
- Swipe or arrows between months; months beyond the projection's window
  show outline targets and race flags only.

**Session detail** (`SessionDetailModel`), pushed:

- Title, date and slot, sport, status, "Test" / "Race" badge.
- For a traffic-light session, a G/A/R picker; it opens on the option that
  was tapped, else the done option, else the morning-light option, else G.
- Per option (or the session itself): targets (km, time, heart rate as
  "≤144 bpm · Z2", a range as "129–144 bpm", or a zone as "Z2 · 129–144
  bpm"), the **steps** of its workout ("Warm-up 10 min · Z1", "4 × 5 min ·
  Z3, 2 min recovery", "Calf raises · 3 × 15 · slow", "Hold 45 s · left"),
  and, once published, the watch state.
- **Why this session**: the session's `why`, then its workout's `why`, then
  any rule notes (empty in v1).
- **Where it came from** (`origin`, `null` in v1): "Moved from Mon 19 Oct",
  "Changed by a rule" once the command and rules changes publish it.
- **Done**: the executed option, or "Option not identified" when
  `done.option` is `null`; the activity's sport, start time, km and time;
  and how it was recognised ("inferred from the sport", "recorded as a test
  result").
- **Fuel**: carbs per hour for the session; the day's carb load.
- **Test**: each result value labelled by the test workout's `measures`
  (label, unit), with the previous value from `tests[].history` and whether
  it improved (`better`). "No result yet" before the test.
- **Race day**: the race's name and date when `raceId` is set; the race
  screen itself is later.

**Habit ladder** (`HabitLadderModel`), from a toolbar button on Plan and
from the habits card: every step in order with its state (active, next,
later), its `why`, start date or earliest start, schedule in words, the
14-day window as "25 of 28 · 89 %" against the gate ("80 % over 14 days",
with "over 9 recorded days" when `recordedDays` < 14, "not recorded yet"
when `null`), and "Gate met: the next habit can start at your Sunday
review" when `gateMet` is true. Read-only; starting a step stays a desk
decision.

### D11 — States that aren't the happy path

| State | Today | Plan |
|---|---|---|
| Connection on, first sync pending | `trainingDay` shows "Fetching your plan…" | same, with the Plan empty state |
| Repository reachable, file 404 | "No plan data yet. Your vault hasn't published it." | same |
| `plan: null` (no phase at all) | "No active plan" | same; races still show if `season` has them |
| Loaded | cards | views |
| `asOf` behind today | "Plan as of Tue 20 Oct" under the card | same line in the header |
| Stale (no sync 24 h) | "Last synced 2 days ago" under the card | same |
| Invalid file | last good + "Couldn't read the latest plan; showing <date>" | same |
| Unsupported major | last good (if any) + **"Update Jirka's Arc to read this plan"** | same |
| Loud auth problem | VaultKit's banner on every tab; last good shown | same |

### D12 — Wiring

- `ContentView`'s experience input becomes `vaultServices.isEnabled` (the
  connection switch). The Diagnostics preview toggle from
  `rebrand-to-jirkas-arc` is removed with its preference key.
- `VaultServices` owns the `ProjectionStore` and passes its validator to
  `ConditionalFileSync`. A `@MainActor @Observable TrainingModel` in the
  app holds the current `TrainingSnapshot` and rebuilds it after each
  refresh and on day change; views read it and call the pure builders.
- `AppRouter` keeps the pending plan date; `PlanTabView` consumes it.
- Nothing in food logging, Garmin sync, gamification or backups changes.

### D13 — Mirroring the contract

- **The vault's two contract fixtures are the reference**:
  `projection.v1.example.json` (every field of v1) and
  `projection.v1.minimal.json` (no season, no plan), both generated by the
  vault from a synthetic source season and guarded there against real
  names. They are copied **verbatim** into
  `ios/TrainingCore/Tests/TrainingCoreTests/Fixtures/Contract/vault/`,
  with a `CONTRACT.md` noting the contract version, the date copied and the
  source change's name (no vault path, no repository name).
- **Golden tests**: both decode with zero `DecodeIssues`; the example's
  decoded values are asserted field by field for every field D4 lists; the
  builders produce pinned Today, week, month, detail and ladder models for
  fixed dates; the minimal one produces the "No active plan" states.
- **App-authored edge fixtures**, each a small mutation of the example (so
  they stay synthetic): unknown fields and enum values everywhere; a
  session without `id` and a malformed date (lossy); `schemaVersion: 2`;
  `schema: "something-else"`; a `supersededBy` hint; snake_case schedule
  kinds; `habitsDone` and `hrMin` present.
- **Until the vault publishes the files**, wave 1 works from a
  hand-written synthetic example that follows the contract section field
  for field, labelled as provisional in `CONTRACT.md`, and is replaced by
  the vault's own files in tasks group 1.
- **Synthetic only**: invented seasons, phases, races, heart-rate zones
  (e.g. 0–128 / 129–144 / 145–156 / 157–168 / 169–185) and habits (e.g.
  "mobility-10"). Never a copy of real vault data or real zones.

### D14 — Testing

- TrainingCore (`swift test`): both vault fixtures and every edge fixture
  (D13); `OpenEnum`, `LossyArray`/`LossyMap`, `LocalizedText` (cs → cz →
  en; plain strings); `ProjectionHeader` gates; `TrainingDay` (boundary
  hour, 00:40, other dates, DST days, `athlete.tz` vs device zone);
  `ISOWeek` (year boundaries, W53); `HRZoneMapper` (inside, edges, `Z2` vs
  `z2`, `hrZones: null`); formatters in English and Czech (plural forms,
  every step kind, fuel, schedules); builders for Today (including
  `done.option: null`, carb-load day, test and race sessions), week
  (`actual: null`, unplanned rows, adjacent-phase weeks), month (42 cells,
  week numbers across a year boundary, race flags from `season.races`),
  detail (option pre-selection, steps, test result vs history) and ladder
  (`window14: null`, `recordedDays`, `gateMet` only on the highest active
  step); freshness (`.behind` from `asOf`, `.stale` from last sync);
  `validate` rejecting v2 and non-projections.
- AppearanceKit: training catalog golden order; food-first catalog
  unchanged; rule-3 insertion into a stored food layout; `training`
  preset; readiness colour distinctness (D9).
- App: device checks (tasks group 7), using a synthetic projection on a
  test branch of the vault (the branch field from `add-vault-connection`).

## Fallbacks for private-API dependencies

None added. The only dependency is the vault's own file over GitHub,
covered by `add-vault-connection`'s fallbacks; with no connection, the app
is food-first and unaffected. If the vault stops publishing, Today and Plan
show the last good plan with its date.

## Risks / Trade-offs

- **Reserved fields fill in later** (`light`, `watch`, `origin`,
  `ruleNotes`). Their UI is designed and tested against edge fixtures now,
  but first meets real data when the ingest, push and command changes
  ship. Re-checked on the device then.
- **`done.option` is often unknown in v1.** G and A can't be told apart by
  sport, so a done run day usually shows "Done" without an option until
  check-ins or the Garmin workout link arrive. Stated in the detail as
  "Option not identified", not hidden.
- **Two twins of plan logic later** (the vault's and the app's
  `PlanEditApplier`). Not in this change; the overlay seam (D8) is where it
  will plug in, tested with the vault's golden vectors.
- **Today gets longer** in the training experience. The training default
  shows the summary compact, and the layout editor and presets let the
  owner trim it.
- **Traffic colours in 13 themes** may collide in a theme. The distinctness
  test finds it; shapes and letters make it harmless meanwhile.
- **Display math creeping into the app.** None is needed: `actual`,
  adherence, matching and gate status all come from the file.

## Migration Plan

1. Merge after `add-vault-connection` and `rebrand-to-jirkas-arc`, and
   after tasks group 1 has mirrored the vault's contract fixtures.
2. For the owner: nothing changes until the vault connection is on; then
   Today gains the training cards at the top of his existing layout and the
   Plan tab appears.
3. For the fiancée: nothing changes.
4. Rollback: revert; the stored layout keeps the training card ids, which
   the older build ignores (rule 2).

## Contract details confirmed against the fixtures (2026-09-29)

Tasks 1.3, checked on the vault's `projection.v1.example.json` as mirrored
into `ios/TrainingCore/Tests/TrainingCoreTests/Fixtures/Contract/vault/`:

- **Schedule kinds** are camelCase (`weeklyCount`, `everyNWeeks`,
  `withSessions`). The snake_case aliases stay accepted (D3); no fixture
  uses them.
- **`aiNote` introduces its own week** (contract point 11): the example's
  note "Last week settled well; this week adds one long run." sits on
  2030-W42 itself, and W43 (`asOf`'s week) has none, so Today shows W42's
  note labelled "W42" (D7's "latest earlier week").
- **`days[].habitsDone` and `targets.hrMin` are present** in v1 (a
  `null` map on days the vault knows nothing about; `hrMin` on the tempo
  session). Both are read and tested.
- **`targets.zone` is upper case** (`"Z1"`); the app still accepts `z1`.
- Also settled while mirroring: `reps` and `load` may be numbers or
  strings (`8`, `"8-12"`, `"40 kg"`), read as display text; weekday codes
  are two letters (`"MO"`, `"TH"`, `"SA"`); ids stay opaque.

## Open Questions

Carried into tasks.md group 0 with proposed defaults:

1. Training default: summary compact and meals expanded (default)?
2. Plan tab opens on Week (default) or Month?
3. Stale threshold 24 h since the last successful sync (default)?
4. Race chip: the next race with priority A or `hero` (default), or any
   priority?
5. Time zone for the training day: the projection's `athlete.tz` (default,
   matches the contract's dates) or the device's?
