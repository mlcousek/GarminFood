## Why

The owner wants gamification *"like things from real word"*. Two of his
chosen ideas turn the numbers he already logs into something tangible:

- **Real-world journeys**: cumulative totals mapped onto real places. The
  protein you eat climbs mountains (Petřín → Sněžka → Mont Blanc → Everest),
  the water you drink fills a bathtub, a hot tub and — some day — the Podolí
  pool, and the active calories your Forerunner records walk you from Praha
  to Brno, Vídeň and on to Lisabon.
- **Personal records**, Garmin-PR style: most protein in a day, most fruit
  and veg in a day, longest water-goal streak, longest fast, most distinct
  foods, lowest-sugar on-target day, biggest active-calorie day — each with
  a "New PR!" moment, just like his watch does for running.

## What Changes

- Four **journeys** with documented conversions and milestones: protein
  climb (1 g = 1 vertical metre), water "Vodník" (litres), active-kcal road
  trip (km = active kcal ÷ body weight in kg), and a passport of distinct
  foods (1 stamp per food). Each shows the current position and the next
  milestone; each milestone = 40 XP; final milestones unlock badges.
- **Eight personal records** with value, date and previous best; a
  "New PR!" moment and 20 XP at most once per record per day; a silent
  baseline on first run and a 7-day warm-up so week one is not a PR storm.
- True lifetime totals via per-day sealing (the usage history is capped at
  500 events, so journeys keep their own ledgers).
- Journeys and Records screens on the Progress tab.

## Capabilities

### New Capabilities

- `journeys` - cumulative real-world journeys with milestones.
- `personal-records` - best-ever daily values with PR moments.

### Modified Capabilities

(none)

## Non-goals

- Maps or GPS routes (a milestone list with a progress line, no MapKit).
- Records based on data without a confirmed route (steps, sleep).
- Retroactive history beyond what the signals snapshot holds on first run
  (42 days) — older days were never cached with macros/water/active kcal.
- Changing the existing lifetime-calories "funny facts" achievements.

## Impact

Owned files only: `Gamification/Sources/Gamification/Features/Journeys/*`,
`Gamification/Sources/Gamification/Features/Records/*`,
`GarminFood/Progress/Slots/{JourneysSlotView,RecordsSlotView}.swift`,
`GarminFood/Progress/Journeys/*`, `GarminFood/Progress/Records/*`, tests.

**Depends on**: `add-gamification-signals` (signals with protein, water,
active kcal, weigh-ins; feature seam; `RewardLedger`; day-sealing pattern).

**Unblocks**: nothing.
