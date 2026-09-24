## Why

The owner is a runner with a Garmin Forerunner 970 who races trails; his
food log lives next to his training in Garmin Connect. Yet the app's
gamification ignores that completely. He asked for achievements *"like
things from real word"* and picked **sport & body via Garmin**: reward
fuelling before a run, refuelling protein after it, eating to match a big
training day, fuelling on race day and during long efforts, weight
milestones against his own Garmin weight goal, and keeping a fasting
schedule. These are the moments where food logging genuinely matters to him.

## What Changes

- **Activity-linked badges** from cached Garmin activities (READ-ONLY route
  confirmed 2026-09-24): Fuel the Run (carbs 30–180 min before start),
  Recovery Window (≥ 20 g protein within 60 min after the end), Earned It
  (intake matched to active calories on an active day), Double Day, Gel
  Guru / Long Haul (fuelling during long activities) — each with tiers.
- **Race-day badges** from the `race` day-note tag: race-day fuel, serial
  racer, and a carb-loading badge for the two days before a race.
- **Weight milestones** against the effective weight goal (Garmin's
  `startingWeight`/`targetWeight` or the local override): first kilo,
  halfway, target reached, 30 days steady within ±1 kg.
- **Fasting streak badges** (3/7/14/30 days kept) from the existing fasting
  schedule evaluation.
- A Sport & Body card on the Progress tab with this month's fuelled and
  recovered activities, weight milestone progress and the fasting streak.

## Capabilities

### New Capabilities

- `sport-body-achievements` - achievements linking food to Garmin
  activities, race days, weight-goal milestones and fasting.

### Modified Capabilities

(none)

## Non-goals

- Any Garmin write (no activity notes, no workout edits).
- Training advice or prescribed fuelling targets beyond the badge rules.
- Steps, sleep, HRV, training load (no confirmed routes).
- Rewarding weight loss speed or extreme deficits — "Earned It" has a floor
  of 80 % of the calorie goal.

## Impact

Owned files only: `Gamification/Sources/Gamification/Features/SportBody/*`,
`FoodLogCore/Sources/FoodLogCore/Signals/FoodTagRules+Sport.swift` (stub
filled), `FoodLogCore/Sources/FoodLogCore/Signals/FoodTag+Sport.swift`
(new), `GarminFood/Progress/Slots/SportBodySlotView.swift`,
`GarminFood/Progress/SportBody/*`, tests. Two shared touches: `GarminFood/App/FeatureHost.swift`
now passes the EFFECTIVE weight goal (override, else Garmin's cached plan)
into `ProfileSignals` -- it previously passed only the local override, so
weight milestones would never see Garmin's own goal -- and the feature id is
added to `GamificationFeatureRegistryTests`' implemented set.

**Depends on**: `add-gamification-signals` (cached activities and active
kcal, weigh-ins, weight goal in `ProfileSignals`, fasting outcome, note
tags, feature seam).

**Unblocks**: nothing.
