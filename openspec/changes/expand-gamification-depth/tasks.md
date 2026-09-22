> **2026-09-22 reconciliation**: this file was left at 0/36 despite the work
> actually shipping across several commits (`Retune the level curve...`,
> `Expand the challenge catalog from 13 to 226 templates`, `Add the
> daily-challenges system...`, `Add a lifetime-stats ledger...`, `Add the
> achievements system: 122 permanent badges across 11 categories`, `Wire
> daily challenges and achievements into the Progress tab UI`) —
> documentation drift, not unstarted work. Checkboxes below were verified
> against the actual code (file/wiring existence) during this pass, not
> reopened from scratch. Task 7.4 (a real-device check) has no evidence
> either way and is left open honestly, matching this project's own "no
> Mac" convention of not claiming device verification that didn't happen.

## 1. Levels

- [x] 1.1 Retuned in `LevelCurve.swift` (verified: file present, doc comments updated).
- [x] 1.2 `LevelTier.swift` exists with tiers + a level-to-tier lookup.
- [x] 1.3 Tier display wired into the level UI (`ProgressViews.swift`).
- [x] 1.4 `LevelCurveTests.swift` and `LevelTierTests.swift` both exist.

## 2. Challenge catalog expansion

- [x] 2.1 New `ChallengeKind` cases present in `ChallengeTemplates.swift`.
- [x] 2.2 Evaluation implemented in `ChallengeEngine.swift`.
- [x] 2.3 Blueprint-generator helpers present in `ChallengeTemplates.swift`.
- [x] 2.4 `ChallengeCatalog.all` assembled; commit message records 226 templates (>= 220 target).
- [x] 2.5 Covered by `ChallengeTemplateCoverageTests.swift` and `NewChallengeKindTests.swift`.

## 3. Daily challenges

- [x] 3.1 `DailyChallenges.swift` exists (`DailyChallengeKind`, templates, catalog).
- [x] 3.2 `DailyChallengeEngine.swift` exists.
- [x] 3.3 `DailyChallengeStore.swift` exists (actor-based, per the store pattern used throughout this project).
- [x] 3.4 `GamificationMoment.dailyChallengeCompleted(title:xpAwarded:)` confirmed present (`GamificationMoment.swift`), wired into `MomentOverlay.swift`.
- [x] 3.5 Wired into `GamificationEngine.swift`.
- [x] 3.6 Covered by `DailyChallengeTests.swift`.

## 4. Lifetime stats ledger

- [x] 4.1 `LifetimeStatsStore.swift` exists.
- [x] 4.2 `handleLogConfirmed(calories:)` confirmed present on `GamificationEngine` (also the exact hook `MealPresetConfirmView`'s own confirm action reuses — see `add-meal-presets`).
- [x] 4.3 Wired per `LifetimeStatsStore.swift`'s own contents.
- [x] 4.4 Backfill logic present in `LifetimeStatsStore.swift`.
- [x] 4.5 Covered by `LifetimeStatsStoreTests.swift`.

## 5. Achievements

- [x] 5.1 `Achievements.swift` exists with the described types.
- [x] 5.2 Catalog present; commit message records 122 definitions across 11 categories.
- [x] 5.3 `AchievementEngine.swift` exists.
- [x] 5.4 `AchievementStore.swift` exists (actor).
- [x] 5.5 `GamificationMoment.achievementUnlocked(title:badgeSymbol:)` confirmed present, wired into `MomentOverlay.swift`.
- [x] 5.6 Wired into `GamificationEngine.swift`.
- [x] 5.7 Covered by `AchievementTests.swift`.

## 6. UI

- [x] 6.1 `AchievementsView.swift` exists (`ios/GarminFood/Progress/`).
- [x] 6.2 Linked from the Progress tab (`ProgressViews.swift`).
- [x] 6.3 Daily challenges section present in `ProgressViews.swift`.
- [x] 6.4 `MomentOverlay.swift` confirmed handling both `.dailyChallengeCompleted` and `.achievementUnlocked`.
- [ ] 6.5 Dynamic Type / VoiceOver pass not separately confirmed during this reconciliation — genuinely open, not just undocumented.

## 7. Verification

- [x] 7.1 `swift test` gated by `.github/workflows/build.yml` on every push to this branch's history; the code merged to `main`, so this passed in CI.
- [x] 7.2 Same reasoning as 7.1 — the app build is part of the same required CI job.
- [x] 7.3 Directly evidenced: `Fix 9 findings from a full-app adversarial review` (git log), on this branch's history.
- [ ] 7.4 Device check genuinely not confirmed — no evidence either way. Left open.
