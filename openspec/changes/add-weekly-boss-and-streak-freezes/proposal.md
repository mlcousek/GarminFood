## Why

The owner asked for *"better challenges"* that are not just "breakfast in
5 days, next 6 days, next 7 days". The one thing a static catalog can never
do is react to *him*. An **adaptive weekly boss** does: every Monday it looks
at the last four weeks, finds his weakest habit (skipped breakfasts, low
water, few vegetables, late-night snacking, missed protein goal…) and turns
it into a named boss with a personalised, reachable target — never the same
boss two weeks running.

He also chose **streak freezes**. A long streak is the most valuable thing
in the app, and today a sick day plus a busy day in the same week wipes it
out. Freezes — earned by beating a boss or completing a full bingo card,
capped at two — make the streak resilient in a way you have to *earn*, and
they give bingo and the boss a reward that matters beyond XP.

## What Changes

- **Weekly boss** (10 archetypes, Czech-flavoured names such as
  "Snídaňový skřet" and "Pouštní drak"): chosen each ISO week from the
  habit with the lowest adherence over the previous 28 days, excluding last
  week's boss; target days scaled from that adherence
  (clamp(⌈adherence × 7⌉ + 2, 3, 7)); each qualifying day this week is a
  hit; defeat = 150–250 XP, a streak-freeze grant and boss badges.
- **Streak freezes**: balance computed from freeze grants (bingo full card,
  boss defeat) and consumptions, capped at 2. A freeze is consumed
  automatically for a recent missed day that would otherwise break a streak
  of at least 3 days. A frozen day keeps the streak alive without adding to
  its length — exactly like the existing grace day.
- `StreakEngine`/`StreakHistory` learn a `frozen` day outcome/mark; the
  streak card shows the freeze count; the calendar shows frozen days.
- A boss banner on Today and a boss card on the Progress tab.

## Capabilities

### New Capabilities

- `weekly-boss` - an adaptive, personalised weekly challenge built from the
  owner's weakest recent habit.

### Modified Capabilities

- `streaks` - adds earned, capped, automatically consumed streak freezes.

## Non-goals

- Buying or manually spending freezes; freezes are automatic.
- Penalties for an escaped boss (no XP loss, no streak effect).
- Changing the existing one-miss-per-week grace rule.
- Freezes in the widget (it shows no live data; see add-streak-widget).

## Impact

Owned: `Gamification/Sources/Gamification/Features/Boss/*`,
`Gamification/Sources/Gamification/StreakFreeze/*`,
`GarminFood/Progress/Slots/BossSlotView.swift`,
`GarminFood/Today/Slots/BossBannerSlot.swift`, `GarminFood/Progress/Boss/*`,
tests. Shared (allowed by the foundation's ownership table):
`StreakEngine.swift`, `StreakHistory.swift`, `GamificationEngine.swift`,
`Progress/ProgressViews.swift`.

**Depends on**: `add-gamification-signals` (signals, `DayPredicate`,
`WeekKey`, `RewardLedger` freeze grants, seam), `add-weekly-bingo` (emits
`bingo.freeze.<week>` grants; freezes work without it but earn slower).
Should merge after all wave-2 changes, because it edits streak semantics
other features read.

**Unblocks**: nothing.
