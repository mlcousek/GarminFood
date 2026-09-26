## 1. Route registry (docs only, READ-ONLY route)

- [x] 1.1 Add `activitiesSearch` to `docs/garmin-routes.json` `read[]`: GET `/activitylist-service/activities/search/activities?startDate={yyyy-MM-dd}&endDate={yyyy-MM-dd}&limit={n}`, `lastVerified` "2026-09-24", `observedStatus` 200, notes: JSON array, 78 keys per item, fields used (`activityId`, `startTimeLocal` "2026-09-23 19:22:08", `startTimeGMT`, `activityType.typeKey`, `duration` s, `calories`, `distance` m), probe body truncated at 20 KB so keep `limit` ≤ 20, READ-ONLY, used by gamification signals.
- [x] 1.2 Add a note to the existing `dailyWellnessSummary` and `dailyFoodLog` entries that gamification now caches their values (no new request).

## 2. GarminKit (read only)

- [x] 2.1 `GarminActivities.swift`: `GarminActivity` DTO (only the used keys, all Optional, unknown keys ignored) + header comment naming the route and date.
- [x] 2.2 `GarminClient.activities(startDate:endDate:limit:)` using the existing signed GET choke point (so it inherits DiagnosticsLog and auth handling). Doc comment: READ-ONLY, confirmed 2026-09-24.
- [x] 2.3 Test: decode a trimmed real fixture (3 items incl. a "walking" and a "running"), including a missing `distance`.

## 3. FoodLogCore — tagging

- [x] 3.1 `FoodTag` (open struct) + core constants (D1).
- [x] 3.2 `FoodTagRule`, `FoodTagRuleSet`, token-boundary phrase matcher over `SearchText` + `CzechLightStemmer` (D2).
- [x] 3.3 `FoodTagRules+Core.swift`: core dictionary (food groups, colours, cuisines, drinks) with exclusions.
- [x] 3.4 `CzechBrands.swift`: brand list + EAN-859 helper.
- [x] 3.5 `FoodTagRuleRegistry.all` = core + three empty stub sets (`+Seasonal`, `+Collections`, `+Sport`) in their own files.
- [x] 3.6 `FoodTaggerTests` golden suite: ≥ 120 fixtures incl. the traps listed in design D13.

## 4. FoodLogCore — caches and signals

- [x] 4.1 `DayLogDigest` + `DayLogDigestStore` (120-day cap, quarantine semantics) + adapter from `DailyFoodLog`. Tests: adapter maps fibre/sugar/goals; cap; corrupt-file quarantine.
- [x] 4.2 `ActivityCacheStore` (active kcal + activities per day, 120-day cap; GMT start parsing, local-date day assignment). Tests.
- [x] 4.3 `FoodProvenanceStore` (foodId → barcode/brand, 2,000 cap). Tests.
- [x] 4.4 `DaySignals`, `SignalEntry`, `MacroTotals`, `MacroGoals`, `SignalAvailability`, `FastingOutcome`, `ProfileSignals` (incl. `firstName(fromFullName:)`: "Jiří Mlčoušek" → "Jiří"). Plain types only — no GarminKit type in any public signature.
- [x] 4.5 `DaySignalsBuilder.build` (pure). Tests: digest precedence, newer-local append, ±120 s de-dup, meal fallback order, water max rule, fasting mapping, note tags, availability flags, 42-day window, tag memoisation per food id.
- [x] 4.6 Performance test: 42 days × 1,000 entries builds in < 50 ms (release).

## 5. Gamification — shared vocabulary and seam

- [x] 5.1 `WeekKey` (ISO-8601 week "2026-W39", Monday start, `minimumDaysInFirstWeek = 4`) + tests across year boundaries (2026-12-31, 2027-01-01, 2020-12-31 = W53).
- [x] 5.2 `DeterministicRandom` (djb2 + LCG, same algorithm as `DailyChallengeSelection`, which is left untouched) + weighted pick. Tests.
- [x] 5.3 `DayPredicate`, `WeekPredicate`, `DataRequirement`, `SignalEvaluator`. One test per case + missing-data paths.
- [x] 5.4 `GamificationFeature` protocol, `FeatureContext`, `FeatureUpdate`, `RewardGrant`, `FeatureMoment`, `FeatureSummary`.
- [x] 5.5 `RewardLedger` (JSON actor). Tests: idempotent XP, freeze grants listed with day, reload from disk.
- [x] 5.6 Eight stub features in their own folders + `GamificationFeatureRegistry.makeAll(directory:)`. Test: ids unique, order fixed.
- [x] 5.7 `Achievements.swift`: Optional `visibility`, `edition`, `rarityOverride`, `featureId`; `.featureEvaluated` condition; `AchievementEngine` meta denominator excludes `.featureEvaluated`; `AchievementRarity` honours override. Tests incl. the unchanged-denominator scenario.
- [x] 5.8 `BadgeRegistry.all` + test: no duplicate ids.
- [x] 5.9 `XPAward+Features.swift` constants (D10).
- [x] 5.10 `GamificationMoment.feature(FeatureMoment)` case.

## 6. Gamification — challenge trim and creative challenges

- [x] 6.1 `ChallengeKind.signalDays(DayPredicate, minDays:)` and `.signalWeek(WeekPredicate)`; `ChallengeEngine.progress` gains an optional `signals: SignalsSnapshot?` parameter (default nil → signal kinds report 0 progress).
- [x] 6.2 `ChallengeTemplates+Signals.swift`: the 24 templates in design D11, appended to `ChallengeCatalog.all`.
- [x] 6.3 `ChallengeRotationPolicy` (weights + ladder allowlist) and weighted `ChallengeRotation.pickNext`; `ChallengeStore.recentTemplateIds` cap 3 → 8 (Optional-safe decode).
- [x] 6.4 `allChallengesCompleted` denominator = templates with static weight > 0.
- [x] 6.6 Level curve (D10): `LevelCurve.growthFactor` 1.045 → 1.0505; `XPStore.peakLevel` (Optional) so a reached level is never lowered (displayed = max(curve, peak)); level-up moments / level achievements only above the peak. Tests: level 84 XP ≈ 116 k; an XP total that was level N on the old curve still displays ≥ N; a level-up fires only above the peak; old `XPStore` JSON decodes.
- [x] 6.5 Tests: `ChallengeRotationPolicyTests`, signal-kind progress tests (Something Fishy, Fibre Fanatic missing-macro day), back-compat decode of an old `ChallengeStore` JSON fixture, existing `ChallengeTemplateCoverageTests` still pass.

## 7. App wiring (thin)

- [x] 7.1 `AppServices`: instantiate `DayLogDigestStore`, `ActivityCacheStore`, `FoodProvenanceStore`, `RewardLedger`; expose via `AppEnvironment`.
- [x] 7.2 Write the day-log digest where `DayLogLoader` and `GamificationEngine.refreshGoalStatus` already fetch a day log; write active kcal where `DayLogLoader` already reads it.
- [x] 7.3 `GamificationSignalsSync`: on foreground/background refresh (never on confirm), at most every 30 min, read activities for the last 14 days (limit 20) and `socialProfile` first name (once per day); cache; failures → `DiagnosticsLog(.error, category: "signals")`; auth errors → existing banner.
- [x] 7.4 Record OFF provenance in the existing OFF match / custom-food-create flow (local write, after the user's action, no network await added).
- [x] 7.5 `FeatureHost`: builds `SignalsInput` from stores, runs registry features, applies ledger/badges/moments, catches and logs per-feature errors. Called at the end of `GamificationEngine.refresh` and `handleLogConfirmed` (≤ 3 lines each).
- [x] 7.6 `MomentOverlay`: render `.feature` moments generically (symbol, title, message, XP; style colour; haptic; Reduce Motion respected).
- [x] 7.7 `ProgressSlotHost` + 8 stub slot views; `TodaySlotHost` + 2 stub banners; one line each in `ProgressHomeView` and `TodayView`.
- [x] 7.8 `AchievementsView` + summary card read `BadgeRegistry`; "Secret" group of `???` tiles; "Limited edition" group.

## 8. Verify

- [x] 8.1 `openspec validate add-gamification-signals --strict` passes.
- [x] 8.2 CI green: `swift test` for GarminKit, FoodLogCore, Gamification; app + widget `xcodebuild`. *Ticked 2026-09-26: merged to `main`, whose `Build iOS app` CI (package tests + app/widget build) is green (run on 0de2d46).*
- [ ] 8.3 On-device check (AltStore build): existing streak/level/achievements unchanged after upgrade; Progress tab renders with empty slots; after a refresh, Settings → Diagnostics shows no `signals` errors and a run logged on the watch appears in the cached activities (verify via a debug line in Diagnostics).
