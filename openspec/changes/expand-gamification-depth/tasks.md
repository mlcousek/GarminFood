## 1. Levels

- [ ] 1.1 Retune `LevelCurve.growthFactor` from `1.3` to `1.045` (base unchanged); update the file's doc comments with the new reachability numbers (see design.md D1).
- [ ] 1.2 Add `LevelTier.swift`: ~20 named tiers spanning levels 1-200, each with a title + one-line flavor string, plus a lookup function from level to tier.
- [ ] 1.3 Wire tier display into the level screen and the level-up moment.
- [ ] 1.4 Update `LevelCurveTests` for the new curve; add `LevelTierTests` (boundary levels, monotonic tier ordering, every level 1-200 maps to exactly one tier).

## 2. Challenge catalog expansion

- [ ] 2.1 Add the five new `ChallengeKind` cases to `ChallengeTemplates.swift` (`mealSlotAbsent`, `allGoalsHitDays`, `allFourMealSlotsDays`, `sameFoodConsecutiveDays`, `consecutiveWeekendsBothDays`).
- [ ] 2.2 Implement evaluation for each new kind in `ChallengeEngine.progress` and `targetCount`.
- [ ] 2.3 Build blueprint-generator helpers producing a difficulty ladder (Easy/Medium/Hard/Extreme) per kind family, parameterized across `GoalMacro`/`MealTimeBucket` where relevant, with hand-written per-tier title/subtitle copy.
- [ ] 2.4 Assemble `ChallengeCatalog.all` from the existing 13 (ids unchanged) plus the generated set; verify count >= 220 and every id is unique.
- [ ] 2.5 Unit test each new `ChallengeKind`'s evaluation against constructed log histories (happy path + at least one non-trivial edge case each), matching the existing `ChallengeTemplateCoverageTests` pattern.

## 3. Daily challenges

- [ ] 3.1 Add `DailyChallenges.swift`: `DailyChallengeKind` (11 cases), `DailyChallengeTemplate`, `DailyChallengeCatalog.all` (120+ templates via the same generator-plus-flavor-text approach).
- [ ] 3.2 Add `DailyChallengeEngine`: evaluates a kind against one day's `[UsageEvent]` + optional `DailyGoalStatus`.
- [ ] 3.3 Add `DailyChallengeStore` (actor): deterministic day-seeded selection of 2 templates/day, 30-day no-repeat with least-recently-shown fallback, persisted `{day: [templateId]}` history (~60 days), per-day completion/XP-awarded flags.
- [ ] 3.4 Add `XPAward.dailyChallengeBonus` and a `GamificationMoment.dailyChallengeCompleted(title:xpAwarded:)` case.
- [ ] 3.5 Wire `GamificationEngine`: assign/read today's daily challenges on `refresh()`, evaluate + award on `handleLogConfirmed()`.
- [ ] 3.6 Unit tests: deterministic same-day reselection, 30-day no-repeat (including the fewer-than-2-eligible fallback), each `DailyChallengeKind`'s evaluation, idempotent same-day XP award.

## 4. Lifetime stats ledger

- [ ] 4.1 Add `LifetimeStatsStore.swift` (actor): `totalLogsEver`, `totalCaloriesEver`, `maxSingleDayCalories`, `firstLogDate`, `goalHitDaysEver: [GoalMacro: Int]` with per-macro last-counted-day dedupe.
- [ ] 4.2 Add `handleLogConfirmed(now:calories:)` parameter to `GamificationEngine`; thread `LogEntryConfirmView`'s existing `caloriesForQuantity` through at its one call site.
- [ ] 4.3 Call `LifetimeStatsStore.recordGoalStatus(_:)` from `refreshGoalStatus(for:)` alongside the existing `goalStatusStore.record(_:)` call.
- [ ] 4.4 First-launch best-effort backfill: if the ledger is empty but `usageHistory`/`goalStatusStore` already have data, seed `totalLogsEver`/`firstLogDate`/`goalHitDaysEver` from whatever's still retained (documented, bounded gap — see design.md's Risks).
- [ ] 4.5 Unit tests: idempotent per-day goal-hit counting, max-single-day tracking across a backdated log, backfill behavior on a pre-populated history.

## 5. Achievements

- [ ] 5.1 Add `Achievements.swift`: `AchievementDefinition`, `AchievementCategory`, `AchievementCondition`, `AchievementContext` (bundles level/XP/streak/lifetime-stats/challenge-and-daily-challenge-completion-counts/calendar-novelty booleans).
- [ ] 5.2 Author the catalog (120+ definitions) across the eleven categories in design.md D5, including the funny cumulative-comparison and extreme-single-day-calorie sets with the specified tone.
- [ ] 5.3 Add `AchievementEngine.evaluate(context:alreadyUnlocked:)`: two-pass (non-meta, then meta/completionist against the resulting count), returns newly-unlocked definitions.
- [ ] 5.4 Add `AchievementStore` (actor): persists unlocked ids + unlock dates.
- [ ] 5.5 Add `XPAward.achievementBonus` and `GamificationMoment.achievementUnlocked(title:badgeSymbol:)`.
- [ ] 5.6 Wire `GamificationEngine.refresh()`/`handleLogConfirmed()`: build the context, evaluate, persist new unlocks, enqueue moments.
- [ ] 5.7 Unit tests: every category's boundary condition, meta-achievement two-pass correctness, permanence (condition later becoming false does not revoke), catalog count >= 100.

## 6. UI

- [ ] 6.1 Add `AchievementsView.swift`: grouped grid, locked (greyed + lock glyph) vs. unlocked (colored + date) states, unlock-count header.
- [ ] 6.2 Add a card/link to `AchievementsView` from `ProgressHomeView`.
- [ ] 6.3 Add a "Today" section to `ChallengesView` showing the two daily challenges with live progress.
- [ ] 6.4 Extend `MomentOverlay` (or its equivalent) to present `.dailyChallengeCompleted` and `.achievementUnlocked`, respecting Reduce Motion per the existing pattern.
- [ ] 6.5 Verify Dynamic Type and VoiceOver labels on the new Achievements screen and the daily-challenges section.

## 7. Verification

- [ ] 7.1 `swift test` green for all `Gamification` package targets (CI, no local toolchain).
- [ ] 7.2 Full app build green (CI).
- [ ] 7.3 Adversarial self-review pass (matching this project's established pattern) before considering the change done, given its size.
- [ ] 7.4 Device check: open the app, confirm today's two daily challenges appear and persist across a re-open, confirm the Achievements screen renders and an easy achievement (e.g. first log) unlocks.
