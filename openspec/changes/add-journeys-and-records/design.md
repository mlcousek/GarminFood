## Context

Two features in one change (two stub slots from
`add-gamification-signals`: `JourneysFeature`, `PersonalRecordsFeature`)
because they share the same machinery: per-day values from `DaySignals`,
processed once per day with the foundation's sealing pattern (D8 there).
Data used: `totals.protein` (Garmin digest or local servings),
`waterML`/`waterGoalML`, `activeKcal` (cached from
`GET /usersummary-service/usersummary/daily`, confirmed 2026-09-23, READ
only), `weighInKg`, entries' timestamps/tags/foodIds, `goals.calories`,
`totals.sugar`. No new requests.

## Decisions

### D1 — Day sealing (shared helper in this change)

`DailyLedger<Value>`: `sealedThrough: String?`, `openDays: [day: Value]`
for the last 3 days (today, yesterday, the day before), and the feature's
running aggregate over sealed days. Each run: recompute open days from the
snapshot; seal any day older than 3 days by folding its last value into
the aggregate. Days are folded exactly once. Deleting an entry on a sealed
day does not change the aggregate (accepted; logged edits of 4+ day-old
entries are rare).

First run: every day in the 42-day snapshot is processed (days older than
3 are sealed immediately) — silently for records (D6), with a single
summary moment for journeys.

### D2 — Protein climb ("Výstup")

Conversion: **1 g protein = 0.5 vertical metre** (owner decision
2026-09-24: a slower, more epic climb; documented; a playful
unit, not physiology). Only days with known protein contribute.

| Stage | Milestone | Metres (cumulative within stage) |
|---|---|---|
| 1 Summits | Petřín | 327 |
| | Lysá hora | 1,323 |
| | Sněžka | 1,603 |
| | Gerlachovský štít | 2,655 |
| | Grossglockner | 3,798 |
| | Mont Blanc | 4,808 |
| | Kilimanjaro | 5,895 |
| | Aconcagua | 6,961 |
| | Everest | 8,849 |
| 2 Seven Summits | Everest → Aconcagua → Denali → Kilimanjaro → Elbrus → Vinson → Puncak Jaya (running sum) | 8,849 / 15,810 / 22,000 / 27,895 / 33,537 / 38,429 / 43,313 |
| 3 To space | Kármán line | 100,000 |

Stages run one after another (stage 2 starts at 0 m when Everest is
reached). At ~130 g/day (65 m/day): Everest ≈ 20 weeks, Seven Summits
≈ +22 months, Kármán line ≈ +4 years — a genuine long tail.

### D3 — Water ("Vodník", the Czech water goblin)

Cumulative litres (max(local, Garmin) per day, as in signals):

| Milestone | Litres |
|---|---|
| Kbelík (bucket) | 10 |
| Sud piva (beer keg) | 50 |
| Vana (bathtub) | 150 |
| Sud na dešťovku (rain barrel) | 300 |
| Vířivka (hot tub, estimate) | 1,000 |
| Hasičská cisterna (fire-engine tank, estimate) | 2,500 |
| Bazén Podolí (50 m pool: 50 × 21 × 2 m ≈ 2,100,000 L, estimate) | endless: shown as a percentage |

After the fire-engine tank, the UI shows "You've filled 0.14 % of Podolí's
50 m pool" — honest about scale, still moving.

### D4 — Active-kcal road trip ("Na cestě")

km = active kcal ÷ (latest known weight in kg, else 70) — the ~1 kcal per
kg per km rule of thumb for walking/running, documented as an
approximation. Only days with cached `activeKcal` contribute. Approximate
road distances, cumulative from Praha:

Brno 205 → Vídeň 350 → Bratislava 430 → Budapešť 630 → Záhřeb 975 →
Lublaň 1,115 → Benátky 1,350 → Florencie 1,610 → Řím 1,890 → Nice 2,590 →
Barcelona 3,250 → Madrid 3,870 → Lisabon 4,495; stage 2 "Cesta domů"
Lisabon → Paříž → Praha (+2,800, total 7,295).

### D5 — Food passport

One stamp per distinct `foodId` ever logged (persisted set; ids only).
Milestones 10, 25, 50, 100, 250, 500 stamps. First run seeds from the
42-day snapshot.

### D6 — Personal records

| id | Record | Value per day | Better | Needs |
|---|---|---|---|---|
| `protein-day` | Most protein in a day | g | higher | macros |
| `fruit-veg-day` | Most fruit & veg portions | entries tagged fruit or vegetable | higher | – |
| `distinct-foods-day` | Most different foods in a day | distinct foodIds | higher | – |
| `water-day` | Most water in a day | ml | higher | water |
| `active-kcal-day` | Biggest active day | kcal | higher | active kcal |
| `water-streak` | Longest water-goal streak | consecutive days water ≥ goal | higher | water |
| `longest-fast` | Longest fast | hours between consecutive entries, only gaps ≤ 48 h | higher | – |
| `low-sugar-on-target` | Lowest-sugar on-target day | g sugar on a closed day with calories within ±10 % of goal and ≥ 3 entries | lower | macros |

Rules:
- "Higher" records compare today live: the first time today's value
  exceeds the record (strictly; protein by ≥ 1 g, water by ≥ 50 ml,
  kcal by ≥ 1), a PR is set and a moment fires; later increases the same
  day update the value silently. Grant key `records.<id>.<day>` (the feature id is the key namespace the FeatureHost enforces) = 20 XP.
- "Lower" and `longest-fast` are judged on **closed** days only (a fast
  or a low-sugar day is only known once the day is over); the moment fires
  on the next run after the day closes.
- **Warm-up**: a record announces PRs only after it has ≥ 7 days of
  qualifying data. Before that, values update silently.
- **Baseline**: the first run computes all records from the snapshot
  silently (no moments, no XP).
- Stored per record: current `(value, day)`, `previous (value, day)?`,
  `qualifyingDays`, last 10 PRs for the history list.

Record badges: `record.first-pr` (first PR ever, common), `record.pr-10`
(uncommon), `record.pr-50` (epic), `record.full-house` (a PR in every
record whose data exists, rare).

### D7 — Rewards and moments

- Journey milestone: `journeys.<journeyId>.<milestoneId>` (feature-id namespace) = 40 XP, moment
  "You summited Sněžka (1,603 m of protein)!" (style `.celebration`).
- Journey badges: `journey.everest`, `journey.seven-summits` (epic),
  `journey.karman` (legendary), `journey.bathtub`, `journey.hot-tub`
  (rare), `journey.fire-engine` (epic), `journey.vienna`, `journey.rome`
  (rare), `journey.lisbon` (epic), `journey.home-again` (legendary),
  `journey.passport-100`, `journey.passport-500` (epic/legendary).
- PR moment style `.record`: "New PR! 186 g protein (previous 171 g)".
- At most one journey moment and one PR moment per run (combined text if
  several), so a back-fill never floods the overlay.

### D8 — Persistence

`features/journeys/journeys.json`:
`{ protein: {ledger, stage, reachedMilestones}, water: {…}, road: {…},
passport: {foodIds: [String]} }` and `features/records/records.json`, all
fields Optional, quarantine helpers.

### D9 — UI

- `JourneysSlotView`: four compact rows — icon, "Sněžka → Gerlach 64 %".
- `Progress/Journeys/JourneysView.swift`: per journey a vertical milestone
  path (reached = filled, next = pulsing unless Reduce Motion), totals and
  the conversion explained in one line.
- `RecordsSlotView` + `Progress/Records/RecordsView.swift`: Garmin-style
  list (record, value, date, previous best, trophy on recent PRs).

### D10 — Testing

- Ledger: sealing exactly once; open-day recompute; first-run processing.
- Conversions: protein metres, water litres, km with weight / fallback.
- Milestone crossing emits one grant per milestone even when a single day
  crosses two; stage rollover.
- Records: each metric computed from literal `DaySignals`; strict
  improvement thresholds; live vs closed-day timing; warm-up; silent
  baseline; `longest-fast` ignores > 48 h gaps; `low-sugar-on-target`
  ignores off-target days; one grant per record per day.
- Store decode with missing fields.

## Risks / Trade-offs

- Protein-as-metres is whimsical; the conversion is stated on screen so it
  never pretends to be science.
- Weight-based km changes as weight changes; each sealed day uses the
  weight known on that day, so past distance never shifts.
- Days never opened in the app have no cached active kcal and contribute
  nothing — the road trip under-counts rather than invents.

## Open Questions

1. ~~Protein climb pace~~ — decided 2026-09-24: 1 g = 0.5 m (~20 weeks to
   Everest at 130 g/day).
2. Should journeys also include a "calories eaten → Big Macs" style route?
   The existing funny-facts achievements already cover that; not planned.
