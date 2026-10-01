Every task ends with CI green: `swift test` for Gamification, TrainingCore
and FoodLogCore, the design-token lint, the app and widget `xcodebuild`, and
the `localization` job. Every new `.swift` file starts with a header
comment. All new user-facing text is in English and Czech. **Fixtures are
synthetic** (a 2030 season): never a token, the vault repository's name or
real data, and no health detail of a real person in a string or a document.
Branch `mlcousek/training-gamification-150-levels` on `main` `8120fd8`.
Swift does not build on the development machine: write small steps and
commit after each.

## 1. The model and the curve (Gamification)

- [x] 1.1 `tools/level-curve-model.mjs`: the three scenarios, the solved factor, the level table, the pace and migration checks (`--check` exits 1 on a failed rule).
- [x] 1.2 `XPAward+Training.swift`: every training reward constant (design D3, D7).
- [x] 1.3 `TrainingXPBudget.swift`: one sub-line per training source with its reward and its poor / typical / perfect frequency.
- [x] 1.4 `XPBudget`: `trainingOnly` lines, `trainingDailyXP`, `typicalDailyXP`, poor and perfect totals, target level 150 after 1,540 days; the `training` line is no longer optional.
- [x] 1.5 `LevelCurve`: `growthFactor` 1.03087, `maxLevel` 150, `pastGrowthFactors` + 1.05358 (curve version 4).
- [x] 1.6 `LevelTiers` re-banded to 150 (ranges up to 90 unchanged); Czech keys for the moved tiers; level badges 175 and 200 retired, 150 = "Max Level".
- [x] 1.7 `XPStore`: the one-time curve announcement (Optional field, shown once, never on a new install).
- [x] 1.8 Tests: `LevelCurveTests` (threshold table, every threshold at or below each past curve's, no XP total mapped lower), `XPBudgetTests` (pin, pace, slowest level, scenarios, shares), `XPCurveMigrationTests` and `LevelPeakTests` rewritten for a flatter curve, `LevelTierTests`, `XPStoreTests` (announcement), `StoreFixtureTests` (`xp-ledger.json` now migrates; new `xp-ledger.v4.json`).

## 2. Plan facts (TrainingCore)

- [x] 2.1 `Contract/ProjectionRewardExtras.swift`: tolerant sidecar decode of `athlete.gate.date`, week `actual.unplannedRunKm` / `overPlanKm`, applied plan-edit outcomes and `race.result`; `ProjectionStore.cachedRewardExtras()`.
- [x] 2.2 `Plan/TrainingPlanFacts.swift`: days (light from a check-in, pain answered, habits expected and done, sessions with status and option, unplanned runs, carb-load), weeks, active habits, races, phases, season.
- [x] 2.3 `TrainingPlanFactsTests` on synthetic inline projections: every fact, the phone's own check-in / tick / RPE overlay, broken and missing extras.

## 3. Rules and rewards (Gamification)

- [x] 3.1 `TrainingPlanSignals.swift` (plain values) and `FeatureContext.trainingPlan`.
- [x] 3.2 `TrainingXPRules.swift`: session, day and week verdicts; grants with their keys; the grace window; the facts to record (design D7).
- [x] 3.3 `TrainingRewardsStore`: `sets`, `habitExpectedByDay`, `seasonEnds` (additive); the habit streak; progress counts.
- [x] 3.4 `TrainingProgressCatalog.swift`: the 41 new badges and their ladders (design D8), EN + CS.
- [x] 3.5 `TrainingRewardsFeature`: grants, badges, the secret reveal, the summary; honest calls and kept weeks from the new rules.
- [x] 3.6 Tests: `TrainingXPRulesTests` (every row of the verdict tables, the eight guards, idempotency, the grace window), `TrainingProgressTests` (ladders, streak across the window, store round trip), `StoreFixtureTests` (`training.v2.json`), the budget's training line.

## 4. Training variants (Gamification)

- [ ] 4.1 Boss: `BossKind.impatienceImp`, hits and adherence from kept plan days, never chosen or required outside the training experience.
- [ ] 4.2 Bingo: `BingoTaskScope.training`, eight training squares, in the pool only in the training experience.
- [ ] 4.3 Journeys: the road trip advances 8 km per kept plan day in the training experience, with its own conversion line.
- [ ] 4.4 Tests for each variant; food-first unchanged.

## 5. Progress model (Gamification)

- [x] 5.1 `TrainingProgressModel.swift`: this week, streaks, ladder rows with count and next step, localized.
- [x] 5.2 Tests: rows, completed ladders, an empty store.

## 6. App

- [x] 6.1 `Training/TrainingPlanSignalsBridge.swift`: TrainingCore facts → `TrainingPlanSignals`; the extras cache.
- [x] 6.2 `FeatureHost`: the plan-signals provider into `FeatureContext`; training no longer an optional source.
- [x] 6.3 `GamificationEngine`: the one-time "150 levels" moment; a feature pass after a training event.
- [x] 6.4 `AppEnvironment+TrainingNutrition`: wire the provider and the event hook.
- [x] 6.5 `Progress/Slots/TrainingProgressSlotView.swift` and its detail list; the level card's "of 150" line and bar; "How to earn XP" rows for the training experience.
- [x] 6.6 App strings (EN + CS) in `Localizable.xcstrings`; `node tools/check-localizations.mjs --scan`; `sh tools/lint-design-tokens.sh`.

## 7. Catalog and docs

- [ ] 7.1 `StoreCatalog`: no new file name (the new fields live in `training.json` and `xp-ledger.json`); `docs/data-compatibility.md` note if the rules ask for one.
- [ ] 7.2 `CLAUDE.md`: the Gamification paragraph mentions training XP and the model script.

## 8. Verify

- [x] 8.1 `openspec validate add-training-gamification-and-150-levels --strict`.
- [x] 8.2 `node tools/level-curve-model.mjs --check`.
- [ ] 8.3 CI green (package tests, app and widget build, localization).
- [ ] 8.4 On device, existing install: XP unchanged, the level is the same or higher, the "150 levels" moment shows once. Training experience: a check-in pays 10 XP once; a rest day shows as kept the next morning; a red morning rested keeps the day; an unplanned run pays nothing; the Progress tab shows the training section. Food-first: no training section, bingo and boss unchanged.

- [ ] 8.5 Archive after `rebalance-xp-economy` (this change modifies its `xp-economy` capability, which exists only once that change is archived).

## 9. Files CI has not compiled yet (read these first when it is red)

- Gamification: `TrainingXPRules.swift`, `TrainingProgressCatalog.swift`, `TrainingProgressModel.swift`, `TrainingRewardsStore.swift`, `TrainingRewardsFeature.swift`, `XPBudget.swift`, `BossCatalog.swift`, `WeeklyBossFeature.swift`, `BingoEvaluator.swift`, `WeeklyBingoFeature.swift`, `JourneysEvaluator.swift`.
- TrainingCore: `TrainingPlanFacts.swift`, `ProjectionRewardExtras.swift`.
- App: `TrainingPlanSignalsBridge.swift`, `TrainingProgressSlotView.swift`, `FeatureHost.swift`, `GamificationEngine.swift`.
- Numbers pinned from the model: `XPBudgetTests` (factor, three totals), `LevelCurveTests` (thresholds).
