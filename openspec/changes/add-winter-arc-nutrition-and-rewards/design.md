## Context

The training experience (`AppExperience.training`, on when the vault
connection is on in a Garmin-connected install) reads the vault's
projection v1 through TrainingCore. Food logging, goal status and
gamification were designed for the food-first experience. They judge a day
by a fixed calorie target and reward fasting streaks and weight loss.

The winter plan's fuelling rules (PM-FUEL-1..6) and the athlete context say:
eat for the training, no energy deficit in a build, weight is an outcome.
The owner also decided (30 Sep) that fasting is off during build weeks. The
vault is adding per-day `fuel` to projection days (additive, still v1).

Package boundaries stay as they are:

- FoodLogCore and Gamification never import TrainingCore.
- TrainingCore never imports either of them.
- The app is the only place that sees all three.

## Decisions

### D1 — Decode `fuel` tolerantly, beside the carb-load shape

`DayFuel.carbsGPerKg` was already a number on carb-load days. The new
shape puts `{ min, max }` under the same key, so it decodes as a number into
`carbsGPerKg` or as an object into `carbsBand` (`GramsPerKgRange`), never
both:

- a band with one bound takes it for both;
- a reversed pair is put in order;
- a band without a positive bound reads as `nil`.

Two more fields decode: `proteinGPerKg` (positive only) and `fasting`, an
`OpenEnum<DayFastingPolicy>` (`allowed`, `off`). An unknown fasting word
never pauses fasting. Nothing else in the contract changes. The mirrored
fixtures are not touched: tests use synthetic inline projections.

### D2 — Grams, not g/kg, cross the package line

`DayFuelTargets.resolve(day:athleteWeightKg:fallbackWeightKg:)` in
TrainingCore works out the day's grams:

- **Band day:** band × weight. Protein is `proteinGPerKg` (default 1.6 g/kg,
  PM-FUEL-1) × weight, but only when there is a carb band.
- **Carb-load day:** `carbsG` when given, else g/kg × weight, as a
  one-point band.
- **Also reported:** whether the day has sessions, and whether fasting is
  paused.

The weight is `athlete.weightKg`, else the latest weigh-in (the app passes
it), else there are no grams and the day falls back to the calorie view.

The app copies the result into FoodLogCore's `FuelDayTarget`. No food-side
code knows what a plan is.

### D3 — The judgement lives in FoodLogCore (`FuelDayEvaluator`)

- **Summary** (`nil` without a band): carbs below, in or above the band
  (both edges inclusive), a bar against the upper edge, protein against
  its target, and the under-fuelling note.
- **The under-fuelling note:** today only, from 18:00 local, when carbs
  are under 75 % of the band's lower edge. It is secondary text, never a
  warning colour, and never on a past day, when nothing can be done about
  it.
- **`displayBand`:** on a day with sessions or a band, `slightlyOver` and
  `over` become `nil`, the neutral ring colour. Every other step, and
  every day without a target, is unchanged.
- **`judge` (goal status):**
  - with a band, calories and carbs are met from the band's lower edge
    up, and above the band is not a miss;
  - on a training day without a band, calories are met from 95 % of the
    target, with no ceiling;
  - protein is met from 90 % of the plan's target ("about");
  - fat is judged as before.
- **`GoalStatusEvaluator.evaluate(_:fuel:)`** is that judgement. A day with
  content but no Garmin goals is still judged when it has a band. Without a
  target, it is exactly `evaluate(_:)`.

So everything that reads `metCalorieGoal` in the training experience —
challenges, bingo, the boss, lifetime stats — stops punishing eating inside
the band.

### D4 — Fasting paused by the plan is neutral

`FastingDayResult` gains `.paused`, and `history(…, pausedDays:)` marks those
days (start-of-day of the day the fast ends on). `keptStreak` skips a
paused day like a running fast, so it never breaks the streak.
`DaySignalsBuilder` gives it no outcome.

In the app, only in the training experience:

- **Home card:** "Fasting paused — build week" instead of the phase.
- **Confirm screen:** no fasting note on a paused log date.
- **History:** "Paused by the plan".
- **Reminders:** planned with no schedule on a paused day. They repeat
  daily, so they come back on the next re-plan (every foreground) of an
  "allowed" day.

The settings (enabled, window, tracked-since) are never written.

### D5 — Weight as a monitor (`WeightMonitor`)

- **Average:** the mean of the last 7 days' weigh-ins logged before 07:00
  local. If there are none, every weigh-in in the window counts, and the
  label says "7-day average".
- **Weekly change:** the same average for the 7 days before, in % a week.
- **The flag:** `isFallingTooFast` when that change is below −0.7 % (PM-FUEL-4).
  Nothing else is judged: a gain or a slow fall says nothing.

In the training experience the Today card and the Weight screen pass
`progress: nil` and show the monitor line instead. The goal bar, ETA and
chart goal line are gone. Sport & Body drops its weight-goal and fasting
sections, and the slot drops the milestone chips and fasting streak. Settings
still lets the owner keep a goal; it is just not shown here.

### D6 — What goes quiet (`TrainingExperienceAvailability`)

One list, a no-op in food-first:

- **Records:** "Biggest active day" (`activeKcalDay`) and "Longest fast"
  (`longestFast`) keep their values silently but announce no PR. That means
  no moment, no XP, and no badge count. `RecordsEvaluator.evaluate(…, quiet:)`;
  the full house ignores them too.
- **Badges:** the fasting-streak tiers and weight-goal milestones are not
  unlocked (`SportAndBodyFeature`). They are hidden unless earned
  (`visibleBadges`); an earned badge always stays.
- **Challenges:**
  - a rotation template judged by the fixed calorie target gets weight 0
    for this pick only, so "complete every challenge" keeps its
    denominator;
  - the daily-challenge catalog loses its calorie and all-goals templates;
  - a new bingo card has no calorie square;
  - the boss picker skips the Calorie Kraken.

A challenge or card already running finishes normally.

**Why skip rather than re-judge by the band:** their titles literally say
"calorie goal". Goal status is already band-based in this experience (D3),
so anything still running can't punish eating inside the band.

### D7 — Training rewards: badges from plan facts

TrainingCore's `TrainingRewardFacts.build(snapshot:today:)` reads, per day
up to today (with the phone's own check-ins and ticks applied):

- **checked in:** the light came from a check-in;
- **honest light followed:** an amber or red check-in, and a traffic-light
  session that day done with exactly that option (`done.option`);
- **strength sessions done:** sport or type `strength`, status `done` or a
  `done` block;
- **habit ticks:** `TrainingSnapshot.habitDone`.

Per written week:

- the strength sessions;
- **kept within plan:** only when the projection says the week is `closed`,
  `actual` shows at least one session done and none missed, and run km is at
  most 10 % over the target when both are known. The phone does not compute
  adherence: it reads what the vault wrote.

The app's adapter (`TrainingNutritionBridge.rewardSignals`) copies the facts
into Gamification's plain `TrainingSignals`.

`TrainingRewardsFeature` (id `training`, appended to the registry) records
the facts in its own store, because the projection carries only a few weeks.
It then requests the ladder badges:

- check-ins: 7 / 30 / 100;
- honest calls: 1 / 10;
- gym weeks (≥ 2 strength sessions): 1 / 4 / 12;
- habit ticks: 25 / 100 / 300;
- kept weeks: 1 / 4 / 12.

It emits no grants. The host unlocks each badge once and pays the generic
badge bonus with the standard moment. It runs only with
`context.isTrainingExperience` and `context.training`.

### D8 — XP stays on pace

The `training` line is **optional** (design D4 of `rebalance-xp-economy`):
14 badges over three winters, ≈ 0.38 XP/day. That is under the 0.5 %
allowance of the ≈ 128 XP/day core, so alone its multiplier is 1.

`FeatureHost` counts it as enabled while the training experience is on. Its
badge bonus is then scaled with supplements' when both are on, so turning
the experience on can't speed levelling up. The core budget and
`LevelCurve.growthFactor` are unchanged.

What the experience silences is either replaced from the same pool (daily
challenges, rotation, boss, bingo) or small (records, sport & body badges).

One source can move either way: goal status judged by the band (D3). The
budget's "goal hit on 60 % of days" line is 15 XP/day, so even +10 % more
goal days adds ≈ 2.5 XP/day, about 2 % of the core. That is inside the
tolerance the curve was solved with, and it reflects days the plan actually
calls good.

### D9 — Where the app decides "training experience"

`AppEnvironment+TrainingNutrition.swift` is the one place. It holds the
gated accessors (`trainingFuelTarget`, `isFastingPausedByPlan`,
`fastingPausedDaysByPlan`, `fastingScheduleForReminders`) and the providers
it sets on `GamificationEngine` (`fuelTargetProvider`) and `FeatureHost`
(`isTrainingExperienceProvider`, `trainingSignalsProvider`,
`fastingPausedDaysProvider`). Their defaults are food-first, so previews
and food-first installs change nothing.

## Defaults chosen (owner can revisit)

| Rule | Default | Source |
|---|---|---|
| Protein without `proteinGPerKg` | 1.6 g/kg | PM-FUEL-1 |
| Protein "met" | ≥ 90 % of target | "about" |
| Under-fuelling note | today, ≥ 18:00, carbs < 75 % of the band's min | — |
| Training day, no band: calories met | ≥ 95 % of target, no ceiling | old green band's floor |
| Morning weigh-in | before 07:00 local | athlete context (~83 kg morning) |
| Quiet weight flag | 7-day average −0.7 %/week or faster | PM-FUEL-4 |
| Kept week | closed, 0 missed, ≥ 1 done, run km ≤ target + 10 % | — |
| Gym week | ≥ 2 strength sessions done | Winter Arc gym twice a week |

## Risks / Trade-offs

- **The vault's `fuel` isn't published yet.** Until it is, every training
  day without `fuel` falls back to today's calorie view, with "over" softened
  on session days. That is safe.
- **Nutrition day vs plan day.** A plan day is matched by its `yyyy-MM-dd`
  string against the phone's local day. For an owner living in the plan's
  time zone they are the same.
- **Reminders on a paused day** are removed for the day and restored on the
  next foreground of an allowed day. A repeating reminder can't check the
  plan at fire time (NotificationScheduler's header).
- **Not compiled locally** (no Mac): CI is the signal.
