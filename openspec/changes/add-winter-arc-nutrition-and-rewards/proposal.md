## Why

In the training experience the app still behaves like a diet tracker. The
calorie ring turns orange and red when the owner eats past a fixed calorie
target, "goal met" means landing inside 95–105 % of that target, the
fasting card counts down every day, and the weight card shows a target with
an arrival date. Several rewards push the same way: "Biggest active day" and
"Longest fast" records, fasting-streak badges, weight-loss milestones and
challenges built on the fixed calorie target.

The winter plan says the opposite. Its fuelling rules (PM-FUEL-1..6) set
carbohydrate by the day's load in g/kg, protein at about 1.6 g/kg, and no
energy deficit during a build: weight is an outcome, not a target (PM-FUEL-4:
any loss at most 0.7 % a week, never in a build). On 30 Sep the owner also
switched fasting **off during build weeks**. The vault is adding a per-day
`fuel` object to the projection so the phone can follow this.

## What Changes

Only the **training experience** changes. Food-first (and standalone, which
is always food-first) looks and judges exactly as before.

- **A1 — the food target follows the training day.**
  - TrainingCore decodes the per-day `fuel` object tolerantly (additive in
    v1): `carbsGPerKg` as `{ min, max }` beside the carb-load day's single
    number, `proteinGPerKg`, `fasting: "allowed" | "off"`. It turns them
    into grams with `athlete.weightKg` (else the latest weigh-in).
  - The Today summary leads with carbs against the day's band and protein
    against its target. Calories become a secondary line.
  - "Over" is never a warning colour on a day with training sessions or a
    band. One gentle note appears when carbs are clearly under the band late
    in the day.
  - Goal status is judged by the band: a day at or above the band's lower
    edge meets its calorie and carb goals.
  - Without a band the summary stays as it is today, but "over" is still
    softened on a training day.
- **Fasting follows the plan.** On a day with `fasting: "off"` the fasting
  card shows "Fasting paused — build week". The confirm-screen note and the
  reminders are off that day. The history marks the day as paused, and a
  paused day never breaks the streak. The owner's fasting settings are
  never changed.
- **A4 — weight is a monitor.** The weight card shows the 7-day morning
  average (weigh-ins before 07:00, else all) and its weekly change. The
  target, the ETA and the weight-goal milestones are hidden. One quiet line
  appears only when the average falls more than 0.7 % in a week.
- **D1 — rewards that support the plan.**
  - Quiet in the training experience: "Biggest active day" and "Longest
    fast" records, fasting-streak badges, weight-goal milestones, and the
    challenges, daily challenges, bingo squares and boss that judge the
    fixed calorie target.
  - New: a `training` gamification feature with five badge ladders, fed by
    a small adapter from TrainingCore: morning check-ins, an honest amber
    or red morning followed by its option, gym twice a week, habit ticks,
    and a week the projection closes within plan.
  - Its badges pay the generic badge bonus as an optional source
    (`rebalance-xp-economy` D4), so levelling keeps its pace. Each badge is
    unlocked once, so nothing is paid twice.

## Capabilities

### New Capabilities

- `training-fuel` — per-day fuel targets from the plan, the carb-first Today
  summary, band-based goal status, and fasting paused by the plan.
- `training-weight-monitor` — the 7-day morning average and the one quiet
  flag, instead of a weight goal.
- `training-rewards` — what goes quiet in the training experience and the
  training badge ladders.

### Modified Capabilities

(none — the food-first behaviour of `challenges`, `streaks` and `levels` is
unchanged)

## Non-goals

- Changing the vault or the contract fixtures. The mirrored fixtures will be
  updated when the vault publishes `fuel`. Tests here use synthetic inline
  projections.
- In-session fuelling (PM-FUEL-2/3/6) and carb-load planning screens.
- A Progress-tab slot for the training rewards. The badges appear in
  Achievements, and the feature's hub summary is ready for a later slot.
- Rewriting the meal cards' macro bars or other calorie surfaces. Only the
  Today summary changes.

## Impact

- TrainingCore: `Contract/Projection.swift`, `Contract/OpenEnum.swift` (`DayFuel`,
  `GramsPerKgRange`, `DayFastingPolicy`), new `Plan/DayFuelTargets.swift`,
  `Plan/TrainingRewardFacts.swift`.
- FoodLogCore: new `FuelDay.swift`, `WeightMonitor.swift`;
  `GoalStatusEvaluator.evaluate(_:fuel:)`; `FastingDayResult.paused` and
  `history(pausedDays:)`.
- Gamification: new `Features/Training/` (signals, availability, store,
  feature), `FeatureContext` gains `isTrainingExperience` and `training`,
  the feature registry and XP budget gain one line each, and records, sport
  & body, boss, bingo and challenge rotation take the training flag.
- App: `AppEnvironment+TrainingNutrition.swift`,
  `Training/TrainingNutritionBridge.swift`, `Today/FuelSummaryCard.swift`,
  and edits to the Today summary, the fasting views, weight, Sport & Body,
  `FeatureHost` and `GamificationEngine`. New EN + CS strings.
