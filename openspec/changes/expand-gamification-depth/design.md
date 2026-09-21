## Context

`add-gamification`'s code is live on `main` (streaks, XP/levels, one rotating challenge) but its OpenSpec change folder was never archived — `openspec/specs/` has no `levels`/`challenges` capability yet, only `openspec/changes/add-gamification/specs/{levels,challenges}`. This change treats that folder as the current baseline anyway (it matches the shipped code exactly, verified by reading every file it describes) and writes normal MODIFIED deltas against it. Archiving `add-gamification` itself is out of scope here.

Every relevant file was re-read in full before writing this design (not assumed from memory): `LevelCurve.swift`, `ChallengeTemplates.swift`, `ChallengeEngine.swift`, `ChallengeStore.swift`, `ChallengeHistory.swift`, `StreakEngine.swift`, `StreakHistory.swift`, `XPStore.swift`, `GoalStatus.swift`, `GamificationMoment.swift`, `NutritionDayBoundary.swift`, `GamificationEngine.swift`, and `UsageHistory.swift` (for the exact `UsageEvent` shape).

## Goals

- Levels, challenges, daily challenges, and achievements should each still be **pure, locally-evaluable functions** wherever `add-gamification` already established that pattern — no new network calls beyond the one that already exists (`GamificationEngine.refreshGoalStatus`).
- Content must be **paced for 2-3+ years**, not exhausted in week one. This is a real constraint on the numbers chosen below, not just a count to hit.
- Stay inside the existing architectural seams: `Gamification` package owns pure engines + JSON-file actor stores; `GamificationEngine` (app target) is the only place that composes them with the outside world (usage history, Garmin client).

## Decisions

### D1 — The level curve is retuned, not just extended

**Problem, worked out with real numbers**: `maxLevel` is already 200, comfortably past "100+ levels." The actual defect is the growth factor. At `growthFactor = 1.3`, the XP band to go from level *L* to *L+1* is `100 * 1.3^(L-1)`. By level 20 that's already ~100x the first band (the code's own comment says so); by level 60 it is roughly `1.3^59 ≈ 5.3 million` times the first band — a single level-up costing hundreds of millions of XP. At a generous ~75 XP/day of realistic engagement (flat per-log + streak + goal bonuses), the cumulative total XP needed to reach level 20 alone is already ~63,000 XP (~2.3 years), and every level after that gets **exponentially** worse. The existing curve does not support "100+ meaningful levels" in any human timeframe — it supports about 15-20 before the wall.

**Decision**: change `growthFactor` from `1.3` to `1.045` (base `baseXPForFirstLevelUp = 100` unchanged, so early pacing — "a single realistic day gets meaningfully close to level 2" — is untouched). With this curve, at ~75 XP/day:

| Milestone | Cumulative XP | Time to reach | Per-level band around there |
|---|---|---|---|
| Level 10 | ~1,300 | ~2-3 weeks | ~2 days/level |
| Level 30 | ~10,900 | ~4-5 months | ~5 days/level |
| Level 50 | ~26,500 | ~1 year | ~12 days/level |
| Level 84 | ~82,000 | ~3 years | ~2-3 months/level |
| Level 100 | ~171,000 | ~6+ years | ~3.5 months/level |
| Level 150 | ~4.9M | multi-decade | true "prestige, may never be reached" ceiling |
| Level 200 (max) | astronomically large | never in practice | same safety-ceiling role the original comment describes |

This gives a curve that feels alive in week one (matching the *existing* early-game intent, which this change does not touch), keeps producing real level-ups throughout years 1-3 (roughly levels 30-85 in that window), and still has 100+ levels of runway beyond that for someone who genuinely uses this for a decade — while levels past ~150 are honestly "may never happen," same spirit as the original `maxLevel`'s own doc comment. This is exactly the kind of implementation-time tuning call `add-gamification`'s own `levels` spec explicitly leaves unpinned ("the exact curve... is an implementation-time tuning detail, not a spec-level requirement"), so this is a retune, not a spec violation.

**Level tiers**: a small new `LevelTier` table (~20 named bands spanning levels 1-200, e.g. levels 1-5 "Rookie", 6-15 "Apprentice", ... 186-200 "Legend"), each with a one-line flavor string. This is deliberately NOT 200 individually hand-named levels — that would be either 200 genuinely distinct funny names (not realistic to write well) or a thin combinatorial reskin that reads as filler either way. A tier name + "Level 47" reads better than "Level 47: Protein Paladin the Third."

### D2 — Challenge catalog expansion: five new kinds + generated tiers, not 220 bespoke entries

Five new `ChallengeKind` cases are added (full list and evaluation rules below), each evaluable the same way the existing nine are — from `events: [UsageEvent]` and `goalStatuses: [DailyGoalStatus]` alone, no new data dependency:

- `mealSlotAbsent(bucket:, minDays:)` — a "self-control" theme: at least `minDays` days within the window logged **nothing** in `bucket` (still requires the day to have at least one entry overall, otherwise doing nothing all day would trivially count). Powers "Snack-Free Days" style challenges.
- `allGoalsHitDays(minCount:)` — calorie AND protein AND carb AND fat goals all met the same day, on `minCount` days.
- `allFourMealSlotsDays(minDays:)` — all four `MealTimeBucket` values covered in a single day (stronger than the existing `multiMealDays`, which only requires *some* N buckets), on `minDays` days.
- `sameFoodConsecutiveDays(minDays:)` — the identical `foodId` logged on `minDays` **consecutive** nutrition-days ("Comfort Food Streak").
- `consecutiveWeekendsBothDays(weekends:)` — generalizes the existing single-weekend `weekendBothDays` to `weekends` **consecutive** weekends, each with both Saturday and Sunday logged.

**Content generation**: rather than hand-writing 220 near-duplicate struct literals, `ChallengeCatalog.all` is assembled from (a) the 13 existing hand-written templates, kept byte-for-byte with their existing ids (id stability matters: `ChallengeStore`/`ChallengeHistoryStore` persist template ids on disk), plus (b) a small set of internal **blueprint generator functions** — one per kind family — that each produce a difficulty ladder (Easy/Medium/Hard/Extreme, escalating `minCount`/`windowDays`/`xpReward`) across the relevant parameter space (all four `GoalMacro` values, all four `MealTimeBucket` values, etc.), with hand-written per-tier title/subtitle text so the result still reads as authored copy, not "Challenge #47." This mirrors the file's own existing framing ("add a row + an evaluation function") at the scale the owner asked for, and keeps every template's evaluation logic exercised by the same `ChallengeEngine.progress` switch the existing 13 already go through. Target: 220+ total templates, comfortably past the 200 asked for, leaving headroom.

### D3 — Daily challenges are a new, parallel, day-scoped system

`ChallengeStore` is architecturally single-slot (one long-running challenge, replaced on completion or window-elapse) and stays exactly that — it is not extended to hold daily challenges too. Daily challenges get their own type family and store instead, because the semantics are genuinely different: exactly one nutrition-day window (never multi-day), exactly two active per day (not one), and a hard no-repeat-within-30-days constraint the long-running catalog doesn't have.

- **`DailyChallengeKind`** (11 cases, all evaluable purely from a single day's `[UsageEvent]` + that day's `DailyGoalStatus?`): `logAtLeast(count:)`, `logDistinctFoods(count:)`, `logInMealSlot(bucket:)`, `avoidMealSlot(bucket:)`, `hitCalorieGoal`, `hitMacroGoal(macro:)`, `hitAllGoals`, `tryNewFood` (a food never seen before in the retained history), `logAllFourSlots`, `earlyLog(beforeHour:)`, `lateLog(afterHour:)` — the last two use the event's **real timestamp hour**, not the coarse `MealTimeBucket`, since daily challenges only need to reason about a single day and can afford the extra precision.
- **120+ templates** via the same "hand-authored table" pattern as the long-running catalog, but leaning harder on flavor-text variation per kind (a player sees each daily challenge for one day only, so mechanical novelty matters less than the writing — 4-6 differently-worded templates per kind/parameter combination is the actual source of the 120+, not 120 distinct mechanics).
- **Selection**: for a given nutrition-day, pick 2 templates such that neither was shown in the last 30 days. Deterministic per day (a `SplitMix64`-style seeded generator keyed by the day string, so reopening the app later the same day shows the same two, but the pick is otherwise unpredictable day to day) rather than `Array.randomElement()`, for the same testability reason `ChallengeRotation.pickNext` is already deterministic. If fewer than 2 templates are eligible under the 30-day rule (only possible if the catalog were much smaller than it is), the rule is relaxed to "least-recently-shown" rather than leaving a day with fewer than 2 — the mechanic must never break.
- **`DailyChallengeStore`** (new actor, same JSON-file pattern): persists `{day: String -> [templateId]}` for the last ~60 days (bounds the no-repeat lookup and file size) and a per-day completion/XP-awarded flag so a completed daily challenge is never re-awarded on a later `refresh()` the same day.
- **XP**: a new, smaller, separate award (`XPAward.dailyChallengeBonus`) — daily challenges are meant to be frequent and easy, so their reward is deliberately less than the long-running `challengeCompletionBonus`.

### D4 — Achievements: a persisted lifetime-stats ledger, because the existing stores are capped

Several achievement ideas the owner asked for directly need a **true lifetime total** — total calories ever logged (for the "eaten an elephant" style facts), the single highest-calorie day ever, total logs ever, per-macro goal-hit-day counts ever, first-ever-log date (for anniversaries). None of these can be safely recomputed from `UsageHistoryStore` (caps at 500 events, silently trims oldest) or `GoalStatusStore` (caps at 120 days) — exactly the problem `XPStore`'s own header already documents and solves for total XP by keeping a small persisted running ledger instead of a derived value. This change applies the same fix to the same class of problem: a new **`LifetimeStatsStore`** actor (same JSON-file pattern) holding `totalLogsEver`, `totalCaloriesEver`, `maxSingleDayCalories`, `firstLogDate`, and `goalHitDaysEver: [GoalMacro: Int]` (with a last-counted-day guard per macro, mirroring `XPStore`'s own `lastStreakBonusDay`/`lastGoalBonusDay` idempotency pattern, so re-fetching the same day's goal status twice never double-counts).

This needs two small, deliberate plumbing additions:
- `GamificationEngine.handleLogConfirmed(now:)` gains an optional `calories: Double?` parameter. `LogEntryConfirmView.confirm()` already computes `caloriesForQuantity` for the on-screen preview — it is passed straight through, no new calculation invented. When `nil` (custom foods without a calorie value, or any future call site that doesn't have one), the calorie-dependent ledger fields simply don't advance that log; nothing breaks.
- `GamificationEngine.refreshGoalStatus(for:)` passes the `DailyGoalStatus` it just computed into `LifetimeStatsStore.recordGoalStatus(_:)` alongside the existing `goalStatusStore.record(_:)` call.

Achievements that don't need a lifetime counter (streak length, level, challenge/daily-challenge completion counts, distinct-foods-in-retained-history, calendar novelties like leap day/New Year's Day/perfect-calendar-month) are evaluated live from data the engine already holds every `refresh()` — no new persistence needed for those.

**"Distinct foods tried" is explicitly scoped to the retained 500-event history**, the same documented limitation `ChallengeKind.newFoodsTried` already carries — a true lifetime distinct-food count would need its own persisted `Set<String>` of every foodId ever seen, which is a reasonable future add-on but is left out of this change to keep the ledger small; the achievement thresholds for this category are chosen low enough (5-500) that the 500-event cap is not the binding constraint in practice for a normal logging cadence.

### D5 — Achievement categories, counts, and the "funny facts" content

Target: 120+ definitions (comfortably past the 100 asked for), across these categories (exact counts, chosen so the total clears 120 with margin and so the long-tail ones are genuinely long-tail):

| Category | Tiers | Example thresholds |
|---|---|---|
| Streak length | 16 | 1, 3, 7, 14, 21, 30, 45, 60, 90, 120, 180, 270, 365, 500, 730, 1000 days |
| Level reached | 11 | 5, 10, 20, 30, 50, 75, 100, 125, 150, 175, 200 |
| Lifetime logs | 10 | 1, 10, 50, 100, 250, 500, 1000, 2500, 5000, 10000 |
| Distinct foods tried (retained history) | 7 | 5, 10, 25, 50, 100, 200, 500 |
| Long-running challenges completed | 7 | 1, 5, 10, 25, 50, 100, "every template in the catalog" |
| Daily challenges completed | 7 | 1, 10, 50, 100, 250, 500, 1000 |
| Per-macro cumulative goal-hit days (x4 macros) | 16 | 10 / 50 / 100 / 365 days per macro |
| Extreme single-day calories ("Feast Mode") | 7 | 3000, 4000, 5000, 6000, 7000, 8000, 10000 kcal in one day |
| Funny cumulative comparisons | ~20 | see below |
| Calendar novelties | 7 | perfect calendar month, leap day, New Year's Day, midnight log, 1/2/3-year app anniversary |
| Meta/completionist | 4 | 25% / 50% / 75% / 100% of all *other* achievements unlocked |

**Funny cumulative comparisons** (the owner's own "eaten an elephant" example), each with 3-4 escalating tiers, using clearly-labeled rough/playful figures (never presented as medical or nutritional fact — every subtitle says "roughly" or "give or take"): total lifetime calories converted against a banana (~105 kcal), a Big Mac (~550 kcal), a pizza (~2,000 kcal/pie), a marathon's energy expenditure (~2,600 kcal), an elephant's daily intake (~150,000 kcal, the owner's own example), and — as the deliberately absurd top tier — a blue whale's daily intake (~1,500,000 kcal). These are framed purely as a fun cumulative-total nerd-fact, never as something to strive for, and never combined with any "do this again" mechanic.

**Extreme single-day calorie badges** (the owner's own "5000kcal, 7000kcal" example) are framed as a one-off, celebratory joke about a single occasion ("Feast Mode", "Thanksgiving Tier") — one-time unlocks like everything else here, not a repeatable challenge and not paired with any XP loop that would reward repeating it, so nothing in the system nudges toward doing this regularly.

**Meta/completionist achievements** exclude themselves from their own denominator and are evaluated in a second pass after every other achievement for that `refresh()` has already been checked, so there's no self-referential ordering bug.

### D6 — UI

A new `AchievementsView` (grid, grouped by category, locked entries shown as a greyed silhouette + lock glyph, unlocked entries in color with their unlock date), reached via a new card on `ProgressHomeView` alongside the existing Level/Streak/Challenges cards. `ChallengesView` gains a "Today" section above the existing active/all/completed sections, showing the two daily challenges and their live progress. A new `GamificationMoment` case (`.achievementUnlocked` and `.dailyChallengeCompleted`) feeds the existing `MomentOverlay` mechanism — no new celebration UI framework, reusing what `add-gamification` already built for level-ups and challenge completions.

## Risks / Trade-offs

- **Retuning the level curve changes existing `LevelCurveTests` expectations.** Accepted and necessary — those tests currently assert the too-steep curve; they get updated alongside the fix, not carried forward as-is.
- **`LifetimeStatsStore` is new persisted state with no migration path from "nothing" — every existing/real device starts all counters at zero on first launch after this ships**, even though the account already has real history. This under-counts lifetime totals for existing data (a device that already had 200 logged entries starts its `totalLogsEver` counter at 0, not 200). Accepted: this project has exactly one real user/device, that device's usage history is still within the 500-event cap `UsageHistoryStore` already carries, and a one-time backfill of `totalLogsEver`/`totalCaloriesEver` from whatever's still in the capped history is a cheap, safe first-launch step this change's implementation includes (best-effort; it cannot recover calorie data or foodIds already rolled off the cap, which is an accepted, bounded gap, not a correctness bug for anything going forward).
- **120+ daily-challenge templates leaning on flavor-text variation for volume, not mechanical novelty**, is a deliberate content trade-off: a genuinely novel single-day condition space is much smaller than the long-running challenge space (there just isn't that much you can meaningfully ask of one day), so authored variety is carried by writing, not by the `DailyChallengeKind` enum's size.
