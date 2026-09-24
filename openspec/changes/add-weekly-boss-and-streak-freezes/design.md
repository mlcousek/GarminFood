## Context

Current streak mechanics (read 2026-09-24, `StreakEngine.swift`):
`simulate(loggedDays:today:calendar:)` walks from the earliest logged day
to today (or yesterday if today is not logged). A logged day adds 1. A
missed day is `grace` (length unchanged) if no other miss lies within the
trailing 7-day window, otherwise `missed` and the length resets to 0.
`StreakHistory` renders the same walk's outcomes as calendar marks, so the
two can never disagree. `status(...).isAtRiskToday` drives the streak
reminder notification. The walk is a pure function of logged days — this
change keeps that property by making frozen days an explicit, persisted
input.

Boss data comes from the foundation's `SignalsSnapshot` (42 days: the
current week + 4 full past weeks fit), `DayPredicate`, `WeekKey` and
`DeterministicRandom`. Freeze grants are already recorded by
`RewardLedger` since wave 1 (`bingo.freeze.<week>`), so freezes earned
before this change ships are honoured.

## Decisions

### D1 — Boss archetypes (`BossCatalog.swift`)

Each: `id`, name (Czech + English), flavour line, `goodDay: DayPredicate`,
`consideredDay` filter, `DataRequirement`.

| id | Name | Good day | Considered days | Needs |
|---|---|---|---|---|
| `breakfast-goblin` | Snídaňový skřet · Breakfast Goblin | breakfast logged | logged days | – |
| `desert-dragon` | Pouštní drak · Desert Dragon | water ≥ goal | days with water data | water |
| `beige-beast` | Béžová bestie · The Beige Beast | ≥ 2 vegetable entries | logged days | – |
| `protein-poltergeist` | Proteinový poltergeist | protein goal met | days with goal status | – |
| `calorie-kraken` | Kalorický kraken | calorie goal met | days with goal status | – |
| `midnight-muncher` | Půlnoční mlsoun · Midnight Muncher | no entry at or after 21:00 | logged days | – |
| `soda-lich` | Limonádový lich · Soda Lich | no sugary drink (day has ≥ 2 entries) | logged days with ≥ 2 entries | – |
| `fibre-phantom` | Vlákninový fantom · Fibre Phantom | fibre ≥ 25 g | days with macros | macros |
| `scurvy-pirate` | Kurdějový pirát · Scurvy Pirate | ≥ 1 fruit | logged days | – |
| `forgetful-ghost` | Zapomnětlivý duch · Forgetful Ghost | any entry | every day | – |

### D2 — Picking the boss (pure `BossPicker.pick`)

- Analysis window: the 28 days of the 4 ISO weeks before the current one.
- For each archetype: `considered` = days passing its filter;
  `adherence = goodDays / considered`. Eligible if its requirement is met
  and `considered ≥ 14` (≥ 50 % coverage). `forgetful-ghost` is always
  eligible (considered = 28).
- New user (< 7 logged days in the window) → `forgetful-ghost`.
- Otherwise the eligible archetype with the lowest adherence, **excluding
  last week's boss**; ties broken by `DeterministicRandom` seeded
  `"boss-" + weekKey`.
- Target days this week: `clamp(ceil(adherence × 7) + 2, 3, 7)` — two days
  better than the recent average, never trivial, never above 7. Example:
  breakfast on 11 of 26 logged days (42 %) → ⌈2.96⌉ + 2 = 5.
- Generated on the first run of the week, persisted, never re-rolled.

### D3 — Fighting the boss

- Each day of the current week whose signals satisfy `goodDay` (and pass
  `consideredDay`) is one **hit**; boss HP = target.
- Today counts as a hit as soon as it qualifies, except
  `midnight-muncher` and `soda-lich`, which judge completed days only (an
  evening entry could still spoil them).
- **Defeated** when hits ≥ target: `RewardGrant("boss.defeat.<week>",
  .xp(150 + 25 × (target − 3)))` (150–250 XP) and `("boss.freeze.<week>",
  .streakFreeze)`; moment style `.boss` ("Snídaňový skřet defeated! +200 XP,
  +1 ❄️").
- Not defeated by Sunday → **escaped**; recorded, no penalty.
- Monday intro moment once per week ("This week: Pouštní drak — reach
  your water goal on 5 days").
- Badges (`featureId: "boss"`): `boss.first` Boss Slayer (common),
  `boss.10` Monster Hunter (rare), `boss.25` (epic), `boss.perfect`
  (defeat with a 7-day target, rare), `boss.bestiary` (every archetype
  defeated at least once, legendary).
- `BossStore`: `{ weeks: {weekKey: {bossId, target, adherence, hits:
  [day], outcome}}, defeatedIds: [String]?, defeatCount: Int? }`, 26 weeks
  kept, Optional fields, quarantine helpers.

### D4 — Freeze balance

- Grants: every `RewardLedger` freeze grant (`bingo.freeze.*`,
  `boss.freeze.*`) with its day.
- Consumptions: `StreakFreezeStore.consumptions: [{frozenDay,
  consumedOn}]`.
- Balance is computed by replaying grants and consumptions in day order,
  clamping at **cap 2** after each grant (a grant into a full bank is
  wasted and shown as "bank full"). Never negative.

### D5 — Frozen-day semantics in `StreakEngine`

`simulate(loggedDays:frozenDays:today:calendar:)` (new parameter, default
`[]`, so every existing call and test is unchanged):

- A day in `frozenDays` that is not logged → outcome **`.frozen`**: the
  running length is unchanged (like grace), the day is **not** added to the
  trailing-miss window (so it does not use up or trigger the grace rule),
  and it never resets the streak.
- A frozen day that later gains a log (a backfill) is simply `.logged`; the
  freeze stays spent (no refund — keeps the ledger simple and monotonic).
- `status(...)` and `StreakHistory.summary(...)` gain the same parameter.
  `StreakHistory.Mark.frozen` is added; `StreakDot` renders it ice-blue with
  a snowflake, label "Missed, streak frozen".
- `longestLength` includes freeze-bridged runs, exactly as it does for
  grace-bridged runs, so streak achievements can unlock through a freeze.
  `isAtRiskToday` keeps its meaning. `extendStreakBy` challenges read the
  same length.

### D6 — When a freeze is consumed (pure `StreakFreezePlanner.plan`)

Input: logged days, existing frozen days, grants, consumptions, today.
Loop:
1. `walk = simulate(loggedDays, frozenDays, today)`.
2. Find the earliest day `d` with outcome `.missed` such that
   `today − 7 ≤ d < today`, the running length immediately before `d` was
   ≥ **3** (only real streaks are protected), and the balance at `d` is ≥ 1
   counting only grants whose day is **before** `d` (a freeze cannot be
   earned after the miss and applied retroactively).
3. If found: add `d` to frozen days, record the consumption, repeat; else
   stop.

Run by `GamificationEngine` at the start of `refresh` and
`handleLogConfirmed`, before the two existing streak computations, then the
new frozen set is passed into them. Local, synchronous-fast, no network.
Each consumption → moment style `.freeze` ("❄️ Freeze used for Tuesday —
your 23-day streak lives on") and badges `freeze.first` (Cool Head,
common), `freeze.saved-100` (a freeze saved a streak ≥ 100 days, epic).

Example: streak 20 on Monday; Tuesday missed (grace, still 20); Wednesday
logged (21); Thursday missed (would reset, being the second miss within 7
days). On Friday's refresh with 1 freeze (earned last Sunday): Thursday →
frozen; the streak stays at 21 and is at risk until Friday is logged, then
22.

### D7 — UI

- Streak card and detail: "❄️ 1/2" chip; detail "How streaks work" adds
  one paragraph on freezes and how to earn them.
- `BossBannerSlot` (Today): boss name, flavour line, HP bar
  (target − hits), days left; tap → `BossDetailView`.
- `BossSlotView` (Progress) + `Progress/Boss/BossDetailView.swift`: this
  week's boss with the 28-day adherence that chose it ("You logged
  breakfast on 42 % of days"), hit days, past 8 weeks' outcomes, bestiary
  grid (defeated archetypes lit).

### D8 — Testing

- Picker: lowest adherence wins; last week's boss excluded; coverage < 14
  ineligible; requirement filter; new-user ghost; tie-break determinism;
  target formula incl. clamps (adherence 0 → 3, 0.9 → 7).
- Fight: hits per archetype; completed-day-only bosses; defeat grants once;
  escape; perfect; bestiary.
- `StreakEngine` with `frozenDays`: frozen = no length change, not in the
  grace window, never resets; backfilled frozen day = logged; all existing
  `StreakEngineTests`/`StreakHistoryTests` pass unchanged (default `[]`).
- Planner: consumes for a streak-breaking miss; not for grace; not for a
  streak < 3; not older than 7 days; not with a grant dated after the miss;
  two misses + two freezes; cap 2 with overflow; idempotent across runs.
- Balance replay with overflow.

## Risks / Trade-offs

- Streak semantics are the most visible number in the app; the default
  parameter keeps every existing path identical and the planner is pure and
  heavily tested.
- A boss chosen from sparse data may feel random; the 50 %-coverage rule and
  the "why this boss" line mitigate it.
- Freezes make long streaks easier — intended, and bounded by the cap and
  the 3-day minimum.

## Open Questions

1. Minimum protected streak length (3 days) and cap (2) — owner's
   preference?
2. Should an escaped boss come back the following week ("rematch") instead
   of the never-twice-in-a-row rule? Default: no rematch, per the owner's
   brief.
