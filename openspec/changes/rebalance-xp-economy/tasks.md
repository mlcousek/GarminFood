## 1. Audit and budget (Gamification, pure)

- [x] 1.1 Read every shipped XP constant: `XPAward`, challenges, daily challenges, seasonal, collections, journeys, records, sport & body, secrets, bingo, boss. Record each in design D3's table with its frequency assumption.
- [x] 1.2 `XPBudget.swift`: `XPBudgetLine` table (one line per source, commented with its constant and frequency), `coreDailyXP`, `solveGrowthFactor(targetLevel:days:dailyXP:)` (bisection, 0.1% tolerance).
- [x] 1.3 Apply D3's retune rule (no wave-2 feature over 25% of core daily XP); adjust the offending constants and list them in the PR. (Audit result: none over the line, largest is boss at ~11%; no constants changed. Enforced by `testNoWaveTwoFeatureExceedsAQuarterOfCore`.)

## 2. Curve and migration

- [x] 2.1 Set `LevelCurve.growthFactor` to the solved literal; turn `legacyGrowthFactor` into `pastGrowthFactors: [1.045, 1.0505]`.
- [x] 2.2 `XPStore`: seed `peakLevel` from the max level across past factors when the stored factor version is older (versioned key; Optional field so old files decode).
- [ ] 2.3 Optional-source multiplier (design D4), exposed for `RewardLedger` grants from optional features.

## 3. Tests

- [ ] 3.1 `XPBudgetTests`: solver round-trip and monotonic; literal matches solved to 1e-4 (failure message prints the value); pace checks for level 10/50/84 (design D1).
- [ ] 3.2 Registry coverage: one budget line per `GamificationFeatureRegistry` feature id.
- [ ] 3.3 Migration: an XP total at level N under 1.0505 is never shown below N; the seeding is idempotent.
- [ ] 3.4 Optional multiplier: the simulation with an optional line enabled stays within ±1% of core days to level 84.

## 4. Verify

- [ ] 4.1 `openspec validate rebalance-xp-economy --strict`.
- [ ] 4.2 CI green (`swift test` Gamification; app build).
- [ ] 4.3 On device: after updating, the displayed level is unchanged and the "XP to next level" bar is plausible; no level-down moment.
