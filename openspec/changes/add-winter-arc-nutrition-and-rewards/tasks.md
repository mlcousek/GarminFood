Every task ends with CI green: `swift test` for TrainingCore, FoodLogCore
and Gamification, the design-token lint, the app and widget `xcodebuild`,
and the `localization` job. Every new `.swift` file starts with a header
comment. All new user-facing text is in English and Czech. **Fixtures are
synthetic** (inline projections of a 2030 season): never a token, the vault
repository's name or real data. Branch `mlcousek/winter-arc-food-and-rewards`
on `main` `4cea263`. Only the training experience changes.

## 1. TrainingCore — fuel and reward facts

- [x] 1.1 `DayFuel`: `carbsGPerKg` as a number (carb load) or a `{ min, max }` band (`GramsPerKgRange`), `proteinGPerKg`, `fasting` (`DayFastingPolicy`); tolerant decoding (design D1).
- [x] 1.2 `DayFuelTargets.resolve` + `TrainingSnapshot.fuelTargets(on:fallbackWeightKg:)`: grams for the weight, 1.6 g/kg protein default, carb-load as a one-point band, sessions, fasting paused (D2).
- [x] 1.3 `TrainingRewardFacts.build`: check-in, honest light followed, strength done, habit ticks per day; strength and "kept within plan" per closed week (D7).
- [x] 1.4 `WinterArcFuelTests` on synthetic inline projections: both shapes, broken fields, grams, fallback weight, carb load, snapshot lookup, day facts with the phone's own check-in and tick, closed-week rule.

## 2. FoodLogCore — judgement, fasting pause, weight monitor

- [x] 2.1 `FuelDayTarget` / `FuelDayEvaluator`: summary, late-day under-fuelling note, softened calorie band, band-based goal judgement (D3).
- [x] 2.2 `GoalStatusEvaluator.evaluate(_:fuel:)`; food-first unchanged without a target.
- [x] 2.3 `FastingDayResult.paused`, `history(pausedDays:)`, `keptStreak` skips it; `DaySignalsBuilder` gives no outcome (D4).
- [x] 2.4 `WeightMonitor`: 7-day morning average, fallback to all, weekly change, flag past −0.7 %/week (D5).
- [x] 2.5 `WinterArcNutritionTests`: every rule above, Prague calendar.

## 3. Gamification — quiet list and training rewards

- [x] 3.1 `FeatureContext.isTrainingExperience` / `training` (defaulted).
- [x] 3.2 `TrainingExperienceAvailability`: quiet records, hidden badges, fixed-calorie-target filters for challenges, daily challenges, bingo, boss (D6); wired into records, sport & body, boss, bingo, `ChallengeRotationPolicy`.
- [x] 3.3 `TrainingSignals`, `TrainingRewardsStore`, `TrainingRewardsFeature` (id `training`, appended to the registry), 14 badges with EN + CS strings (D7).
- [x] 3.4 `XPBudget`: one optional `training` line (D8); registry and supplements tests updated for the appended id.
- [x] 3.5 `TrainingRewardsTests`: inert outside the experience, ladders and thresholds, no grants, no re-request, counts across instances, habit day replace, summary, the quiet list, the budget line.

## 4. App

- [x] 4.1 `TrainingNutritionBridge` (TrainingModel → `FuelDayTarget`, paused days, `TrainingSignals`) and `AppEnvironment+TrainingNutrition` (the gated accessors and providers, D9).
- [x] 4.2 Today: `FuelSummaryCard` on a band day; `DaySummaryCard` softens "over" on a training day.
- [x] 4.3 Fasting: paused card, no confirm note, "Paused by the plan" in history, no reminders on a paused day.
- [x] 4.4 Weight: monitor line instead of the goal bar/ETA/goal line (Today card, Weight screen); Sport & Body drops weight-goal and fasting sections in the training experience.
- [x] 4.5 `GamificationEngine`: band-based goal status, filtered daily catalog, rotation flag; `FeatureHost`: context, paused fasting days, visible badges, optional source.
- [x] 4.6 App strings (EN + CS) in `Localizable.xcstrings`; `node tools/check-localizations.mjs --scan`; `sh tools/lint-design-tokens.sh`.

## 5. Verify

- [x] 5.1 `openspec validate add-winter-arc-nutrition-and-rewards --strict`.
- [ ] 5.2 CI green (package tests, app and widget build, localization).
- [ ] 5.3 Mirror the vault's contract fixtures once `fuel` is published; add a golden check on the example's fuel days.
- [ ] 5.4 On device, in the training experience: a band day shows carbs first; eating past the calorie target stays neutral; a build-week day shows "Fasting paused"; the weight card shows the morning average; a training badge unlocks once. In food-first: nothing changed.
