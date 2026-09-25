## Context

Built entirely on `add-gamification-signals`: `SignalsSnapshot` (42 days of
`DaySignals`), core `FoodTag`s, `DayPredicate`/`WeekPredicate` with
`DataRequirement`, `WeekKey` (ISO-8601, Monday start), `DeterministicRandom`,
the `GamificationFeature` protocol (replacing the stub in
`Features/WeeklyBingo/WeeklyBingoFeature.swift`), and `RewardLedger`.
No network, no Garmin reads of its own.

## Decisions

### D1 — The week and the seed

- Week = ISO-8601 week of the **logged date** (the engine's day boundary,
  `loggedDateBoundaryHour = 0`), key like `2026-W39`.
- Seed = `"bingo-" + weekKey`. The card is generated the **first time** the
  feature runs in that week and **persisted**; later catalog edits or data
  changes never alter an existing card. Starting mid-week still gives a full
  Monday–Sunday card (days before install simply may not have data).

### D2 — Task catalog (`BingoTaskCatalog.swift`)

Each task: `id`, `title`, `detail`, `difficulty` (easy/medium/hard),
`family` (no two per card), `scope` (`.day(DayPredicate)` — holds on any
single day of the week, or `.week(WeekPredicate)`), and the predicate's
`DataRequirement`.

| id | Title | Rule | Diff | Family | Needs |
|---|---|---|---|---|---|
| `e-early-log` | Rise & Log | first log before 09:00 | E | time | – |
| `e-fruit` | An Apple a Day | any fruit | E | fruit | – |
| `e-veg-lunch` | Green Lunch | vegetable at lunch | E | vegmeal | – |
| `e-three-meals` | Square Meals | breakfast, lunch and dinner the same day | E | meals | – |
| `e-new-food` | Something New | a food never logged before | E | novelty | – |
| `e-soup` | Polévka Day | a soup | E | soup | – |
| `e-tea` | Tea Break | tea | E | drinks | – |
| `e-fermented` | Friendly Bacteria | a fermented food | E | fermented | – |
| `e-nuts` | Go Nuts | nuts | E | nuts | – |
| `e-egg` | Egg Day | eggs | E | egg | – |
| `m-fish` | Something Fishy | fish or seafood | M | fish | – |
| `m-three-fruits` | Fruit Salad | ≥ 3 fruit entries in one day | M | fruit | – |
| `m-water-goal` | Hydrated | water goal met | M | water | water |
| `m-czech-brand` | Local Hero | a Czech brand not logged before this day | M | brands | – |
| `m-no-soda` | Soda-Free Day | ≥ 3 entries, no sugary drink | M | drinks | – |
| `m-protein-2` | Protein Double | protein goal on 2 days (week) | M | goal | – |
| `m-veg-breakfast` | Veggie Sunrise | vegetable at breakfast | M | vegmeal | – |
| `m-legume` | Pulse Day | legumes | M | legume | – |
| `m-colours-4` | Painted Plate | ≥ 4 colours in one day | M | colours | – |
| `m-cuisine` | Passport Stamp | any non-Czech cuisine | M | cuisine | – |
| `m-early-dinner` | Early Dinner | dinner logged and last log before 19:30 | M | time | – |
| `m-whole-grain` | Whole Grain | whole grain | M | grain | – |
| `m-refuel` | Refuel | ≥ 20 g protein within 60 min after an activity | M | sport | activities |
| `m-calories-2` | On Target Twice | calorie goal on 2 days (week) | M | goal | – |
| `h-fish-2` | Fish Twice | fish on 2 days (week) | H | fish | – |
| `h-protein-3` | Protein Hat-Trick | protein goal on 3 days (week) | H | goal | – |
| `h-water-4` | Water Works | water goal on 4 days (week) | H | water | water |
| `h-ten-foods` | Variety Show | ≥ 10 distinct foods in one day | H | novelty | – |
| `h-meatless` | Meat-Free Day | ≥ 3 entries, none meat/poultry/fish | H | meat | – |
| `h-fibre-30` | Fibre Day | ≥ 30 g fibre | H | macros | macros |
| `h-sugar-low` | Sugar Low | ≤ 25 g sugar with ≥ 3 entries | H | macros | macros |
| `h-five-a-day` | Five a Day | ≥ 5 fruit+veg entries in one day | H | fruit | – |
| `h-rainbow` | Full Rainbow | all 6 colours across the week | H | colours | – |
| `h-earned-it` | Earned the Meal | activity ≥ 30 min and calorie goal the same day | H | sport | activities |
| `h-clean-sweep` | Clean Sweep | all four goals in one day | H | goal | – |

35 tasks: 10 easy, 14 medium, 11 hard. Adding a task later is a row in this
table; ids are persisted and never reused.

### D3 — Card composition (pure `BingoCardGenerator.generate`)

1. Eligible = tasks whose `DataRequirement` is met by at least one of the
   last 14 days (`SignalAvailability`), and not on the previous week's card
   (so two consecutive weeks never repeat a task; if that leaves too few,
   the previous-week exclusion is dropped first).
2. Seeded shuffle of eligible tasks per difficulty.
3. Pick 3 easy, 3 medium, 2 hard, skipping any whose family is already on
   the card. If a difficulty runs short, fill from the next easier one;
   if families block completion, relax the family rule last.
4. Layout: index 4 (centre) = FREE. The 8 picks are placed by a seeded
   permutation of positions {0,1,2,3,5,6,7,8}, except hard tasks never sit
   on the same line together (re-permute deterministically up to 16 times,
   then accept).

A card is stored as 9 task ids with `"free"` at index 4.

### D4 — Completion

- A day-scoped square completes when its predicate holds on any logged date
  in the card's week up to today; a week-scoped square when its
  `WeekPredicate` holds over the week so far.
- **Sticky**: once a square is recorded complete (with the day it
  completed), it stays complete even if a later edit/delete would make the
  predicate false. Rewards are never taken back.
- Squares complete during the card's week only; on Monday the previous card
  is frozen as-is and archived.
- If a stored task id is no longer in the catalog, the square is treated as
  FREE (defensive; ids are never removed on purpose).

### D5 — Lines and rewards

- 8 lines: rows (0-1-2, 3-4-5, 6-7-8), columns (0-3-6, 1-4-7, 2-5-8),
  diagonals (0-4-8, 2-4-6). The free centre counts as complete.
- Each newly complete line: `RewardGrant(key: "bingo.line.<week>.<lineId>",
  .xp(XPAward.bingoLine = 25))` + moment "BINGO! Row 2" (style
  `.celebration`).
- Full card: `bingo.full.<week>` → `.xp(XPAward.bingoFullCard = 150)`, and
  `bingo.freeze.<week>` → `.streakFreeze`, moment "Blackout! Full card".
  Maximum from one week: 8 × 25 + 150 = 350 XP.

### D6 — Badges (`featureId: "bingo"`, `.featureEvaluated`)

| id | Title | Condition | Rarity |
|---|---|---|---|
| `bingo.first-line` | Bingo! | first line ever | common |
| `bingo.four-corners` | Four Corners | squares 0, 2, 6, 8 all done in one week | uncommon |
| `bingo.x-marks` | X Marks the Spot | both diagonals in one week | uncommon |
| `bingo.lines-50` | Line Dancer | 50 lines in total | rare |
| `bingo.blackout-1` | Blackout | first full card | rare |
| `bingo.blackout-4` | Card Shark | 4 full cards | epic |
| `bingo.blackout-12` | Bingo Hall Legend | 12 full cards | legendary |

Lifetime counters (`totalLines`, `fullCards`) live in the bingo store and
are incremented only when the corresponding ledger key is new, so they stay
correct across reinstalls of the same data.

### D7 — Persistence (`BingoStore`, JSON actor)

`features/bingo/bingo.json`:
`{ cards: { "2026-W39": { taskIds: [9], completed: { "3": "2026-09-23" },
linesDone: ["row0"], full: false } }, totalLines: Int?, fullCards: Int? }`.
Keeps the last 12 weeks. All non-essential fields Optional so older files
decode. Uses `GamificationStorage` load/quarantine helpers.

### D8 — UI

- `BingoSlotView` (Progress hub): 3×3 mini grid (filled/empty dots, free
  star), "2 lines · 5/9" and days left; taps into `BingoCardView`.
- `BingoCardView`: large grid; each square shows an SF Symbol per family,
  title, and a check with the day it completed; tapping opens a sheet with
  the rule and whether the owner's data supports it. Completed lines are
  drawn as a stroke across the grid with a spring animation (Reduce Motion:
  fade). Past cards: a horizontally paged list of the last 12 weeks.
- VoiceOver: each square reads "Row 1, column 2, Fruit Salad, done on
  Tuesday" / "not done".

### D9 — Testing (`GamificationTests/WeeklyBingo*Tests.swift`)

- Generator: same week → same card; different weeks → different cards;
  composition counts; no duplicate family; free centre; requirement
  filtering (no water data → no water tasks); previous-week exclusion and
  its relaxation; hard tasks not sharing a line.
- Completion: each day-scoped and week-scoped task via literal
  `DaySignals`; stickiness after a deleted entry; no completion outside the
  card week; unknown task id treated as free.
- Rewards: line keys, full-card XP + freeze grant keys, applied once across
  two runs (with a real `RewardLedger` in a temp dir).
- Badges: four corners, X, counters.
- Store: round-trip, 12-week cap, old-file decode.

## Risks / Trade-offs

- A hard square may be unreachable in a given week (e.g. no activity
  happened). Accepted: bingo is about "any line", not a full card every
  week.
- Tagging errors can tick or miss a square. The square sheet shows *which
  entry* ticked it, so the owner can report bad tags.

## Open Questions

1. Free centre square: kept (owner said "optional"). Alternative: centre
   is always a "wildcard" easy task. Default: free.
2. Should a blackout also grant a small bonus for doing it before Friday?
   Not planned.
