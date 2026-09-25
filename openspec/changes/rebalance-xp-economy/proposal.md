## Why

Since 2026-09-24 the app gained nine gamification features: seasonal
events, collections, journeys, records, sport & body, secrets, bingo, the
weekly boss and streak freezes. `add-supplements` will add another XP source.
`add-gamification-signals` D10 retuned the level curve once (growth
1.045 → 1.0505) using an **estimate** of about 31 extra XP/day. That estimate
came from the *designs*, and several shipped amounts differ from them. For
example, bingo's full card pays 350 XP where the design said 150, and sport
& body pays no XP.

The owner wants levelling to keep **the same pace as now**: every new source
must not add up to a faster climb. They said *"we will also need to edit
gamification again to not level up that fast"*. Tuning by hand each time a
feature lands doesn't scale, so the pace becomes an explicit, tested budget.

## What Changes

- **A pure XP-budget model (`XPBudget`)** in the Gamification package.
  - Every XP source declares its expected XP for a "typical active day"
    through a small, reviewable table: flat per-log XP, streak XP,
    challenges, daily challenges, and each wave-2 feature, plus supplements
    when that feature is on.
  - The model sums the table into an expected XP/day.
- **The level curve is derived from the budget.** `LevelCurve.growthFactor`
  is solved (closed form or bisection, at build or test time) so that a
  typical day reaches **level 84 in 3 years**, matching the original
  2026-09-18 promise. A unit test pins the solved factor and fails when a
  new source is added without updating the budget.
- **Optional features count only when enabled.** Supplements (off by
  default) add their budget line only when switched on. The curve is
  computed from the always-on budget, and optional sources are scaled with a
  per-source **XP multiplier** so that switching a feature on doesn't change
  the pace.
- **Levels never drop.** Existing `peakLevel` handling carries over: a
  steeper curve never lowers a displayed level. A one-time migration seeds
  `peakLevel` from the current factor before the new one applies.
- **Retune shipped amounts where they're out of line** (listed in design
  D3), e.g. bingo's full card and journeys milestones, so one feature can't
  dominate the budget.

## Capabilities

### New Capabilities

- `xp-economy` - an explicit, tested XP budget that keeps levelling at a
  fixed pace however many XP sources exist.

### Modified Capabilities

(none; `LevelCurve`'s determinism and the never-lower-a-level rule are
unchanged)

## Non-goals

- New XP sources or rewards. Those belong to each feature's own change
  (e.g. `add-supplements`).
- A per-day XP cap. The owner explicitly chose calibration over a cap.
- Changing badge rarities, challenge difficulty or streak rules.

## Impact

- Gamification package: `LevelCurve.swift`, new `XPBudget.swift`, feature
  reward constants, and `XPStore` peak-level migration. The app only changes
  where it shows "XP to next level" (no API change).
- **Depends on**: all wave-2 gamification changes being merged (done
  2026-09-25).
- **Unblocks**: `add-supplements` (its supplement XP is priced through this
  budget).
