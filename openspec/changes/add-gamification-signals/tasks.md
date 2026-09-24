## 1. Route registry (docs only, READ-ONLY route)

- [ ] 1.1 Add `activitiesSearch` to `docs/garmin-routes.json` `read[]`: GET `/activitylist-service/activities/search/activities?startDate={yyyy-MM-dd}&endDate={yyyy-MM-dd}&limit={n}`, `lastVerified` "2026-09-24", `observedStatus` 200, notes: JSON array, 78 keys per item, fields used (`activityId`, `startTimeLocal` "2026-09-23 19:22:08", `startTimeGMT`, `activityType.typeKey`, `duration` s, `calories`, `distance` m), probe body truncated at 20 KB so keep `limit` ≤ 20, READ-ONLY, used by gamification signals.
- [ ] 1.2 Add a note to the existing `dailyWellnessSummary` and `dailyFoodLog` entries that gamification now caches their values (no new request).

## 2. GarminKit (read only)

- [ ] 2.1 `GarminActivities.swift`: `GarminActivity` DTO (only the used keys, all Optional, unknown keys ignored) + header comment naming the route and date.
- [ ] 2.2 `GarminClient.activities(startDate:endDate:limit:)` using the existing signed GET choke point (so it inherits DiagnosticsLog and auth handling). Doc comment: READ-ONLY, confirmed 2026-09-24.
- [ ] 2.3 Test: decode a trimmed real fixture (3 items incl. a "walking" and a "running"), including a missing `distance`.

## 3. FoodLogCore — tagging

- [ ] 3.1 `FoodTag` (open struct) + core constants (D1).
- [ ] 3.2 `FoodTagRule`, `FoodTagRuleSet`, token-boundary phrase matcher over `SearchText` + `CzechLightStemmer` (D2).
- [ ] 3.3 `FoodTagRules+Core.swift`: core dictionary (food groups, colours, cuisines, drinks) with exclusions.
- [ ] 3.4 `CzechBrands.swift`: brand list + EAN-859 helper.
- [ ] 3.5 `FoodTagRuleRegistry.all` = core + three empty stub sets (`+Seasonal`, `+Collections`, `+Sport`) in their own files.
- [ ] 3.6 `FoodTaggerTests` golden suite: ≥ 120 fixtures incl. the traps listed in design D13.

## 4. FoodLogCore — caches and signals

- [ ] 4.1 `DayLogDigest` + `DayLogDigestStore` (120-day cap, quarantine semantics) + adapter from `DailyFoodLog`. Tests: adapter maps fibre/sugar/goals; cap; corrupt-file quarantine.
- [ ] 4.2 `ActivityCacheStore` (active kcal + activities per day, 120-day cap; GMT start parsing, local-date day assignment). Tests.
- [ ] 4.3 `FoodProvenanceStore` (foodId → barcode/brand, 2,000 cap). Tests.
- [ ] 4.4 `DaySignals`, `SignalEntry`, `MacroTotals`, `MacroGoals`, `SignalAvailability`, `FastingOutcome`, `ProfileSignals` (incl. `firstName(fromFullName:)`: "Jiří Mlčoušek" → "Jiří"). Plain types only — no GarminKit type in any public signature.
- [ ] 4.5 `DaySignalsBuilder.build` (pure). Tests: digest precedence, newer-local append, ±120 s de-dup, meal fallback order, water max rule, fasting mapping, note tags, availability flags, 42-day window, tag memoisation per food id.
- [ ] 4.6 Performance test: 42 days × 1,000 entries builds in < 50 ms (release).

## 5. Gamification — shared vocabulary and seam

- [ ] 5.1 `WeekKey` (ISO-8601 week "2026-W39", Monday start, `minimumDaysInFirstWeek = 4`) + tests across year boundaries (2026-12-31, 2027-01-01, 2020-12-31 = W53).
- [ ] 5.2 `DeterministicRandom` (djb2 + LCG, same algorithm as `DailyChallengeSelection`, which is left untouched) + weighted pick. Tests.
- [ ] 5.3 `DayPredicate`, `WeekPredicate`, `DataRequirement`, `SignalEvaluator`. One test per case + missing-data paths.
- [ ] 5.4 `GamificationFeature` protocol, `FeatureContext`, `FeatureUpdate`, `RewardGrant`, `FeatureMoment`, `FeatureSummary`.
- [ ] 5.5 `RewardLedger` (JSON actor). Tests: idempotent XP, freeze grants listed with day, reload from disk.
- [ ] 5.6 Eight stub features in their own folders + `GamificationFeatureRegistry.makeAll(directory:)`. Test: ids unique, order fixed.
- [ ] 5.7 `Achievements.swift`: Optional `visibility`, `edition`, `rarityOverride`, `featureId`; `.featureEvaluated` condition; `AchievementEngine` meta denominator excludes `.featureEvaluated`; `AchievementRarity` honours override. Tests incl. the unchanged-denominator scenario.
- [ ] 5.8 `BadgeRegistry.all` + test: no duplicate ids.
- [ ] 5.9 `XPAward+Features.swift` constants (D10).
- [ ] 5.10 `GamificationMoment.feature(FeatureMoment)` case.

## 6. Gamification — challenge trim and creative challenges

- [ ] 6.1 `ChallengeKind.signalDays(DayPredicate, minDays:)` and `.signalWeek(WeekPredicate)`; `ChallengeEngine.progress` gains an optional `signals: SignalsSnapshot?` parameter (default nil → signal kinds report 0 progress).
- [ ] 6.2 `ChallengeTemplates+Signals.swift`: the 24 templates in design D11, appended to `ChallengeCatalog.all`.
- [ ] 6.3 `ChallengeRotationPolicy` (weights + ladder allowlist) and weighted `ChallengeRotation.pickNext`; `ChallengeStore.recentTemplateIds` cap 3 → 8 (Optional-safe decode).
- [ ] 6.4 `allChallengesCompleted` denominator = templates with static weight > 0.
- [ ] 6.6 Level curve (D10): `LevelCurve.growthFactor` 1.045 → 1.0505; `XPStore.peakLevel` (Optional) so a reached level is never lowered (displayed = max(curve, peak)); level-up moments / level achievements only above the peak. Tests: level 84 XP ≈ 116 k; an XP total that was level N on the old curve still displays ≥ N; a level-up fires only above the peak; old `XPStore` JSON decodes.
- [ ] 6.5 Tests: `ChallengeRotationPolicyTests`, signal-kind progress tests (Something Fishy, Fibre Fanatic missing-macro day), back-compat decode of an old `ChallengeStore` JSON fixture, existing `ChallengeTemplateCoverageTests` still pass.

## 7. App wiring (thin)

- [ ] 7.1 `AppServices`: instantiate `DayLogDigestStore`, `ActivityCacheStore`, `FoodProvenanceStore`, `RewardLedger`; expose via `AppEnvironment`.
- [ ] 7.2 Write the day-log digest where `DayLogLoader` and `GamificationEngine.refreshGoalStatus` already fetch a day log; write active kcal where `DayLogLoader` already reads it.
- [ ] 7.3 `GamificationSignalsSync`: on foreground/background refresh (never on confirm), at most every 30 min, read activities for the last 14 days (limit 20) and `socialProfile` first name (once per day); cache; failures → `DiagnosticsLog(.error, category: "signals")`; auth errors → existing banner.
- [ ] 7.4 Record OFF provenance in the existing OFF match / custom-food-create flow (local write, after the user's action, no network await added).
- [ ] 7.5 `FeatureHost`: builds `SignalsInput` from stores, runs registry features, applies ledger/badges/moments, catches and logs per-feature errors. Called at the end of `GamificationEngine.refresh` and `handleLogConfirmed` (≤ 3 lines each).
- [ ] 7.6 `MomentOverlay`: render `.feature` moments generically (symbol, title, message, XP; style colour; haptic; Reduce Motion respected).
- [ ] 7.7 `ProgressSlotHost` + 8 stub slot views; `TodaySlotHost` + 2 stub banners; one line each in `ProgressHomeView` and `TodayView`.
- [ ] 7.8 `AchievementsView` + summary card read `BadgeRegistry`; "Secret" group of `???` tiles; "Limited edition" group.

## 8. Verify

- [ ] 8.1 `openspec validate add-gamification-signals --strict` passes.
- [ ] 8.2 CI green: `swift test` for GarminKit, FoodLogCore, Gamification; app + widget `xcodebuild`.
- [ ] 8.3 On-device check (AltStore build): existing streak/level/achievements unchanged after upgrade; Progress tab renders with empty slots; after a refresh, Settings → Diagnostics shows no `signals` errors and a run logged on the watch appears in the cached activities (verify via a debug line in Diagnostics).
