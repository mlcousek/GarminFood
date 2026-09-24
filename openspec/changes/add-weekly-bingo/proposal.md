## Why

The owner asked for *"better and more creative gamification … not only
track breakfast in 5 days, next 6 days, next 7 days etc."* and picked a
**weekly bingo card** as one of the features to build. Bingo turns a week of
ordinary eating into a varied set of small, real-world tasks ("eat fish
once", "three fruits in a day", "a Czech brand you've never logged", "drink
your water goal") where any combination of them pays off — the opposite of
a single number ladder. It also gives the owner a reason to eat a little
more variety without prescribing a diet.

## What Changes

- Every ISO week (Monday–Sunday) a **3×3 bingo card** is generated from a
  catalog of ~35 real-world tasks, deterministically seeded by the week
  (reopening the app never reshuffles it). The centre square is free.
- Card composition is balanced (3 easy, 3 medium, 2 hard around the free
  centre), never has two tasks from the same family, and only uses tasks the
  owner's data can actually satisfy (no water squares without water data,
  no activity squares without Garmin activities, no fibre/sugar squares
  without macro data).
- Squares tick themselves off from the day signals — no manual marking.
  Once ticked, a square stays ticked.
- **Rewards**: each completed row, column or diagonal = 25 XP; the full card
  ("blackout") = 150 XP, a streak-freeze grant (used by
  `add-weekly-boss-and-streak-freezes`) and bingo badges (first line, first
  blackout, 4 and 12 blackouts, both diagonals, four corners, 50 lines).
- UI: a bingo card on the Progress tab (mini grid + lines count) and a full
  card screen with square details and the last 12 weeks' cards.

## Capabilities

### New Capabilities

- `weekly-bingo` - a weekly, deterministic, self-completing 3×3 card of
  real-world food tasks with line and full-card rewards.

### Modified Capabilities

(none)

## Non-goals

- Manually ticking squares or re-rolling a card (keeps it honest and
  deterministic).
- Steps-based squares — no confirmed steps route (see
  `add-gamification-signals` non-goals).
- The streak-freeze balance and consumption — owned by
  `add-weekly-boss-and-streak-freezes`; this change only emits the grant.
- New shared signal fields or tags — uses `add-gamification-signals`' core
  tags and `DayPredicate` only.

## Impact

Affected code (all owned by this change, per the foundation's file
ownership table): `Gamification/Sources/Gamification/Features/WeeklyBingo/*`,
`GarminFood/Progress/Slots/BingoSlotView.swift`, `GarminFood/Progress/Bingo/*`,
tests `GamificationTests/WeeklyBingo*Tests.swift`. No shared files.

**Depends on**: `add-gamification-signals` (tags, `DayPredicate`,
`WeekKey`, `DeterministicRandom`, feature seam, `RewardLedger`).

**Unblocks**: `add-weekly-boss-and-streak-freezes` (consumes the full-card
freeze grant).
