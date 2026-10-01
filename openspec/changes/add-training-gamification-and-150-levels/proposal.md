## Why

The owner asked on 1 Oct 2026: gamification for habits, training, races and
plans, and **150 levels that take about 3–5 years** instead of the present
target of level 84 in three years.

Today the training experience has almost no rewards of its own.
`add-winter-arc-nutrition-and-rewards` added five badge ladders and nothing
else: no XP for a check-in, a habit tick, a session, a kept week, a finished
race. It also deferred the Progress-tab slot. The level curve is solved for
the food economy alone (≈ 128 XP a day), with level 84 as the target and a
ceiling of 200 that nobody reaches.

One principle rules everything here. The plan's method exists to prevent
overload: it holds volume, gates intensity on a morning traffic light, and
puts a deload every fourth week. A reward system that pays for "more" works
against it. So this change rewards **following the plan and honest
self-monitoring, never doing more than the plan**:

- no XP for extra kilometres, extra sessions, hard days in a row, running
  through a red morning, or losing weight;
- a rest day, a deload week, the amber or red option, stopping at the stop
  rule and skipping a race are rewarded, or at least never punished.

## What Changes

- **150 levels.** One curve for both experiences:
  `XP(n → n+1) = round(100 × 1.03087^(n−1))`, levels 1–150.
  - A typical consistent day in the training experience (≈ 193 XP) reaches
    level 150 in **1,540 days (4.2 years)**. Perfect play every day needs
    2.9 years. Three typical weeks and one poor week need 5.0 years.
  - Level 10 arrives in about 5 days. No level takes longer than 47 typical
    days (6.7 weeks).
  - The food-first experience keeps working on the same curve. Alone, its
    typical day (≈ 128 XP) reaches level 150 in about 6.4 years.
- **Migration.** XP is kept as it is. Every threshold of the new curve is at
  or below the same level's threshold on every curve that shipped before, so
  nobody's level goes down, and most go up (a 3,000 XP ledger: level 20 →
  22). The level tiers below 91 keep their names and ranges. A one-time
  "150 levels" moment explains the change. The level badges for 175 and 200
  are retired (nobody could have earned them).
- **Training XP** (training experience only), all read from the plan the
  vault publishes, through the existing adapter pattern, each paid once:
  - *Self-monitoring:* morning check-in, pain score while it is asked,
    RPE and note after a session, the weekly gate test, a recorded test.
  - *Habits:* each tick, a full habit day, streak milestones 7 / 30 / 100 /
    365, a new ladder step. A tick filled in more than two days later pays
    no XP (it still counts for streaks and badges).
  - *Training:* a session done within the plan and the morning light, an
    amber or red morning followed by its option, a kept plan day (a rest day
    counts; so does resting on a red morning), gym twice a week.
  - *Plans:* a week approved, a week kept within plan, an easy week
    respected, a phase closed with its recap, a season completed. Plan edits
    pay no XP.
  - *Races:* prep complete, carb-load days hit, the race finished, the
    report written. A fixed amount, never by distance or pace. Goal and PR
    are rare one-off badges. A race stopped or not started for a good reason
    pays the same as a finish, with a secret badge.
- **Guards, as tested rules.** Unplanned kilometres pay nothing and break
  "week kept within plan". A session done harder than the morning light
  allows pays nothing and breaks its day. Nothing counts consecutive hard
  days.
- **Training variants of the weekly games.** In the training experience the
  boss can be "the Impatience Imp" (beaten by kept plan days), bingo cards draw
  squares for check-ins, habits, the plan and fuelling, and the road-trip
  journey moves by kept plan days instead of active calories.
- **Progress tab.** A training section: the 1–150 bar, current streaks, this
  week, and every training ladder with its next step.
- **XP budget.** `XPBudget` gains training lines (≈ 65 XP a day, half the
  food core). The curve is solved against food core + training. The training
  rewards stop being an "optional source".

## Capabilities

### New Capabilities

- `training-xp` — XP and badges from the plan's facts, and the guards.
- `training-challenges` — the training variants of boss, bingo and journeys.
- `training-progress` — the Progress tab's training section.

### Modified Capabilities

- `levels` — 150 levels, the curve's formula, tiers, the one-time moment.
- `xp-economy` — the pace target (level 150 after 1,540 typical days) and
  the training lines of the budget.

## Non-goals

- New vault fields. Three facts the app would like are not published yet (a
  race's outcome and whether its goal was reached, whether the fuel plan was
  followed). They are decoded tolerantly and stay dormant until then.
- Changing any food-economy reward or the optional-source rule.
- Prestige levels or a level reset.
- Rewards computed from pace, distance, elevation or weight.

## Impact

- Gamification: `LevelCurve`, `LevelTier`, `XPBudget`, `XPStore`, the level
  badges, `Features/Training/*` (signals, rules, budget, catalog, store,
  feature, progress model), boss, bingo, journeys, the feature context.
  New store fields in `training.json` (additive) and a new fixture; a new
  `xp-ledger` fixture for curve version 4.
- TrainingCore: new `Plan/TrainingPlanFacts.swift` and
  `Contract/ProjectionRewardExtras.swift`; one read-only method on
  `ProjectionStore`. No existing model changes.
- App: `Training/TrainingPlanSignalsBridge.swift`,
  `Progress/Slots/TrainingProgressSlotView.swift`, small edits to
  `FeatureHost`, `GamificationEngine`, `AppEnvironment+TrainingNutrition`
  and `ProgressViews`. New EN + CS strings.
- `tools/level-curve-model.mjs`: the numeric model of the curve.
