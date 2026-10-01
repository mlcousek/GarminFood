## Why

Two things the owner ran into on the first real mornings (30 Sep), and a
contract change of the vault that answers both:

1. **The check-in did not work every day.** The app found a day only in a
   written week of the selected phase. On a day outside the written weeks
   -- an unwritten week, or no active plan at all -- Today had no check-in
   row, the Habits card had nothing to tick, no reminder fired, and a
   lock-screen Control's check-in was recorded but shown nowhere.
2. **The pain features nag a healthy athlete.** `add-checkin-pain-score`
   opens the pain step under the lights every morning and prints
   "Pain: none" on the card. The owner: "pain features are annoying when
   I'm healthy -- show them when pain started and until it's gone."

The vault's projection (still `schemaVersion` 1, its "daily check-in
context" of 2026-09-30) now carries what the app needs:

- top-level `days`: a **day skeleton** for every date of the window that
  no written week holds -- the same `Day` shape with `sessions: []` --
  present even when `plan` is null;
- `athlete.painMode { active, since, sites, reason, clearsAfter }`: the
  vault's switch for every pain feature;
- `day.fuel` on **every** day: `kind` `"carb-load"` or `"daily"`,
  `carbsGPerKg` a number or `{ min, max }`, `proteinGPerKg`, `fasting`
  with `fastingReasons`, `load`, `plannedMin`, `rules`. This is the one
  change that is not purely additive: `fuel` used to be `null` outside
  carb-load days, so "the day has a fuel" no longer means "carb load".

## What Changes

- **Contract (TrainingCore).** Both projection fixtures are re-mirrored
  verbatim. `Projection.days` (skeletons, a repeated or already-planned
  date dropped), `Athlete.painMode` (`PainMode`), and the full `DayFuel`
  (`fastingReasons`, `load`, `plannedMin`, `rules`, `kind` gains `daily`)
  decode tolerantly. `DayFuel.isCarbLoad` is the only carb-load test; every
  place that read "fuel is there" or "kind is missing" as a carb load now
  asks it (the Today carb-load line, the Plan fuel lines, the session
  detail, the race screen's carb-load rows, the food target).
- **Every day works.** `TrainingSnapshot.day(_:)` looks a date up in the
  written weeks, else among the skeletons (with the phone's check-ins laid
  over both). The check-in row, the pain step, the Habits card and its
  ticks, the fuel targets and paused-fasting days, the reward facts, the
  Plan day sheet and month cells, and the reminders use it -- with no plan
  too. The check-in row is offered on every date (a stale copy included).
  A week that is not written lists the days that have something to show.
- **Pain mode.** `TrainingSnapshot.painMode` is on when the vault says so,
  or -- optimistically -- when this phone recorded a pain answer above 0
  that the vault has not read yet. In pain mode everything is as
  `add-checkin-pain-score` built it. Outside it the check-in is the light
  only, with one small "Something hurts?" link that opens the same step;
  no pain line, no pain tags, and a lock-screen Control no longer brings
  Today forward.
- **Reminders.** The morning check-in reminder is planned on every day
  (it needed a G/A/R session before), with a short body, and a body that
  also asks for the pain score in pain mode. Both training reminders get a
  time picker next to their switch (04:05 and 20:10 by default), kept in
  UserDefaults like the food reminders' times.
- **Food screens.** `fuel` on a skeleton day feeds the Today fuel summary
  and "fasting paused" exactly like a written week's day; the adapters no
  longer ask for a plan.
- `add-winter-arc-nutrition-and-rewards` task 5.3 (the golden check of the
  example's fuel, deferred until the vault published it) is done here.

Nothing is persisted in a new file: no `StoreCatalog` entry.

## Impact

- TrainingCore: `Contract/` (Projection, Pain, OpenEnum),
  `Plan/TrainingSnapshot`, new `Plan/PainModeState`, `Plan/DayFuelTargets`,
  `Plan/TrainingRewardFacts`, `Events/CheckInOverlay`,
  `Events/TrainingReminderPlanner`, the Today / Plan / pain / habits /
  race builders, three new strings (one replaced) in both `.lproj`.
- App: `TrainingModel` (reminder times, `isPainMode`),
  `TrainingNutritionBridge`, `TrainingTodayCards` (the link),
  `WeekAgendaView`, `NotificationSettingsView` (time pickers),
  `AppEnvironment` (the Control's hand-off), `Localizable.xcstrings`.
- Behaviour that changes for an existing install: a check-in reminder on
  rest days and unwritten weeks; no pain step, line or tags while pain
  mode is off; the Today fuel summary on every day of the window.
- Not verified here: Swift compiles only in CI; the device check is in
  `tasks.md` section 6.
