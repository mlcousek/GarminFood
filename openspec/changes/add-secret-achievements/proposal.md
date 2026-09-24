## Why

The owner wants *"more creative gamification … add creative ideas"*.
Every current achievement is listed with its exact condition, so the
catalog reads like a checklist. **Secret achievements** add surprise: the
owner sees "??? × 15" and only finds out what they were when he stumbles
into one — a 2 a.m. fridge raid, a fifth coffee, a palindrome calorie total,
pizza four Fridays in a row, logging on Friday the 13th. They reward the
quirky, human side of eating rather than discipline, which fits the app's
"playful and encouraging" tone.

## What Changes

- **15 secret achievements** with exact, testable rules (design D2),
  evaluated from day signals.
- Hidden until unlocked: the Achievements screen shows only "???" tiles
  and a count ("3 of 15 secrets found"); no hints.
- Unlocking reveals the title and description with a dedicated moment
  style; 50 XP on top of the usual achievement bonus.
- A visible "Secret Keeper" badge for finding all of them.

## Capabilities

### New Capabilities

- `secret-achievements` - hidden, surprise achievements with exact rules,
  revealed only when unlocked.

### Modified Capabilities

(none)

## Non-goals

- Hints or a "reveal one secret" purchase mechanic.
- Encouraging unhealthy behaviour: no secret rewards extreme intake,
  skipping meals or long fasts (the existing "extreme" calorie badges are
  untouched and out of scope).
- New shared signal fields (all rules use existing signals).

## Impact

Owned files only: `Gamification/Sources/Gamification/Features/Secret/*`,
`GarminFood/Progress/Slots/SecretsSlotView.swift`, tests. The "???" tile
rendering itself is part of `add-gamification-signals` (AchievementsView).

**Depends on**: `add-gamification-signals` (signals, core tags incl.
`coffee`, `pizza`, `fish`, `knedlik`, `pie`, `cuisine.*`; secret badge
visibility; feature seam; `RewardLedger`).

**Unblocks**: nothing.
