## Why

`add-gamification` shipped a real streak/level/challenge system, but it is sized for a demo, not for the 2-3+ years of daily use the owner actually intends: 13 challenge templates, one active challenge at a time, and a level curve whose own growth factor (1.3x per level) makes anything past roughly level 15-20 mathematically unreachable in a human lifetime (a `1.3` geometric factor means a level-100 band alone would cost billions of XP). The owner asked directly for a much deeper, funnier, longer-tail system — more levels that are actually reachable over years, 200+ challenges, a brand-new daily-challenge layer (2 random, non-repeating challenges every day), and 100+ achievements/badges with genuinely creative content (cumulative "you've eaten an elephant's worth of calories" style facts, extreme single-day calorie badges, multi-year streak/anniversary badges) — explicitly so a 2-3 year user never runs out of new things to unlock in the first month.

## What Changes

- **Retune the level curve** so it supports a real multi-year arc: a realistic user reaches roughly level 80-90 by year three, not an unreachable wall by month two. `maxLevel` (200) already exceeds the "100+ levels" ask; the growth factor is what's actually broken and gets fixed. Levels also gain a **tier/title** ("Rookie", "Nutrition Ninja", "Legend", ...) spanning ~20 named bands across the 200 levels, for personality.
- **Expand the long-running challenge catalog from 13 to 220+ templates**, adding five new locally-evaluable `ChallengeKind` cases (snack-free days, all-goals-hit days, all-four-meal-slot days, same-food streaks, consecutive weekend streaks) alongside the nine existing ones, with a difficulty ladder (Easy/Medium/Hard/Extreme) and matching XP rewards, so the catalog stops repeating within any reasonable timeframe.
- **Add a new Daily Challenges system**: 120+ single-day challenge templates, 2 freshly picked every nutrition-day, deterministic per day (reopening the app the same day shows the same two), with no template repeating for at least 30 days. Separate XP track from the long-running challenges; separate persisted history for its own achievements.
- **Add Achievements/Badges**: 120+ one-time, permanently-unlocked achievements across streak length, level, lifetime log count, distinct foods tried, challenge/daily-challenge completions, per-macro goal-hitting totals, calendar novelties (leap day, New Year's Day, app-anniversaries), extreme single-day calorie totals, and playful cumulative "real-world comparison" facts (calories eaten vs. an elephant's daily intake, a Big Mac, a marathon's energy burn, etc.), shown on a new dedicated Achievements screen with locked/unlocked state and unlock dates. Deliberately paced with real long-tail thresholds (365/730/1000-day streaks, 1000+ lifetime logs, 3-year anniversary) so most of the catalog stays unreached for a long time.
- Add a small **lifetime-stats ledger** (cumulative calories, max single-day calories, per-macro goal-hit-day counts, first-ever-log date) — the existing usage-history and goal-status stores are capped and roll off old data (documented, deliberate limitations of those stores), so anything meant to be a true lifetime total needs its own small persisted counter, the same reasoning `XPStore` already uses for total XP.

## Capabilities

### New Capabilities

- `daily-challenges` - a daily-refreshing pair of single-day challenges, randomized without repeating any template for 30 days.
- `achievements` - permanent, one-time-unlockable badges spanning consistency, volume, variety, and playful cumulative/extreme milestones, paced for multi-year use.

### Modified Capabilities

- `levels` - retunes the XP curve for multi-year reachability and adds level tiers/titles.
- `challenges` - expands the template catalog and adds new challenge kinds; the existing single-active-slot rotation model is unchanged.

## Non-goals

- **A procedural/generated-at-runtime challenge or achievement engine.** Every template and achievement definition is still a hand-authored (or hand-authored-via-generator-helper) static table, per `add-gamification`'s own explicit "not an authoring engine" scope line.
- **Social features** (leaderboards, sharing unlocked badges) — unchanged from `add-gamification`'s own non-goal; still a single-user app.
- **Custom badge artwork.** Badges are rendered with SF Symbols + color/rarity styling, not commissioned icons — no art pipeline exists in this project.
- **Per-food macro data flowing into daily-challenge or achievement conditions beyond calories.** `UsageEvent` still only carries `foodId`/`servingId`/`numberOfUnits`/`timestamp`/`nutritionDay` (no macros); only the calorie value already computed on the confirm screen is threaded through for the lifetime-calories ledger. Protein/carb/fat-aware conditions stay expressed in terms of the existing day-level `DailyGoalStatus`, exactly as `challenges` already does.

## Impact

Affected surfaces: the `Gamification` package (new `DailyChallenges.swift`, `Achievements.swift`, `LevelTier.swift`, `LifetimeStatsStore.swift`; expanded `ChallengeTemplates.swift`/`ChallengeEngine.swift`; retuned `LevelCurve.swift`), `GamificationEngine.swift` (wiring + one new parameter on `handleLogConfirmed` to pass the confirm screen's already-computed calorie value through), and the app's Progress tab (a new Achievements screen; the existing Challenges screen gains a "Today" section for the two daily challenges).

**Depends on**: `add-gamification` (this change modifies its `levels`/`challenges` capabilities and reuses its stores/patterns directly; `add-gamification` itself was never formally archived — see design.md for how this change treats that).

**Unblocks**: nothing further planned.
