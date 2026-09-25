## Context

`LevelCurve` (Gamification) maps total XP to a level with a geometric
threshold curve: base 100 XP for level 1→2, growth factor `1.0505`, and a
cap of 200. The tuning history is in its header comment:

- 1.3 made levels unreachable;
- 2026-09-18 set 1.045, which reaches level 84 in about 3 years at
  ~75 XP/day;
- 2026-09-24 set 1.0505, because new sources were estimated to add
  ~31 XP/day.

`XPStore` keeps `peakLevel`, so a curve change never lowers the displayed
level. That estimate was made before the features were built. This change
replaces tuning by estimate with a budget table that tests can check.

## Decisions

### D1 — The pace target

**Level 84 after 3 years (1,095 days) of a typical active day.** This is the
promise from the 2026-09-18 retune that the owner has seen. Secondary
checks: level 10 falls within 2–5 weeks and level 50 within 9–15 months.
All three are asserted in tests.

### D2 — `XPBudget` (pure)

```swift
public struct XPBudgetLine { let source: String; let expectedDailyXP: Double; let optional: Bool }
public enum XPBudget {
    static let lines: [XPBudgetLine]           // one per source, reviewed in code review
    static var coreDailyXP: Double             // sum of non-optional lines
    static func solveGrowthFactor(targetLevel: Int, days: Int, dailyXP: Double) -> Double
}
```

- **Expected values.** Each line's value is the *long-run average per day*
  for a typical active user. Examples: a line bonus paid about 1.5 times a
  week counts as `25 × 1.5 / 7`; secrets are one-offs spread over 3 years.
- **Documentation.** The table lives in one file, with a comment per line
  giving the source constant and its assumed frequency.
- **Solving the factor.** `solveGrowthFactor` bisects the factor in
  [1.0, 1.2] until the cumulative XP to reach `targetLevel` equals
  `days × dailyXP`, to within 0.1%.
- **Pinning.** `LevelCurve.growthFactor` stays a literal constant, for
  deterministic and cheap builds. The test
  `testGrowthFactorMatchesBudget` checks that the literal matches the
  solved value to within 1e-4. It fails when someone changes rewards or
  adds a source without re-solving, and its failure message prints the
  value to paste in.
- **Registry check.** A second test enumerates
  `GamificationFeatureRegistry.makeAll` and requires one budget line per
  feature id. A new feature can't skip the budget.

### D3 — Audit of shipped amounts (to verify during implementation)

During implementation, read each shipped reward constant and record it in
the table. Known from PRs #69–#80:

| Source | Shipped reward | Frequency assumption |
|---|---|---|
| Seasonal bonus quest | 25 XP | per event quest |
| Collections | 5 XP / discovery | declining over time |
| Journeys | 40 XP / milestone | a few per month |
| Records | 20 XP / PR, max 1 per record per day | a few per month |
| Sport & body | 0 XP | — |
| Secrets | 50 XP each, 16 total | one-off |
| Bingo | 25 per line; 350 full card + freeze | lines ~1.5/week, full card rare |
| Weekly boss | defeat XP (read constant) | ~0.5/week |

Retune rule: if one wave-2 feature's expected daily XP is more than 25% of
`coreDailyXP`, reduce its constants rather than steepen the curve for
everyone. Bingo's 350-XP full card is the likely candidate. Changes to
feature constants are listed in the PR description.

### D4 — Optional sources (supplements)

The curve is solved for `coreDailyXP` only. An optional source gets a
per-source multiplier `m = 1 − (optionalDailyXP / (coreDailyXP + optionalDailyXP))`.
This is applied when the source grants XP (`RewardLedger` grant amount × m,
rounded, minimum 1). As a result, a user with supplements on levels at the
same pace as one without.

- Supplements are budgeted at a small daily amount (see `add-supplements`
  D9) before the multiplier.
- The multiplier comes from the same table, so a test can check it.

### D5 — Migration

- When the constant changes, `XPStore` seeds `peakLevel` from the level
  under the *previous* factor, exactly as the 2026-09-24 migration did with
  `legacyGrowthFactor`. A one-level-ever-reached guarantee is kept.
- `legacyGrowthFactor` becomes a list of past factors: `[1.045, 1.0505]`.
  The seed takes the max level over all of them.

### D6 — Testing

- Solver: known curve round-trips, and monotonicity.
- Pace checks from D1.
- Registry-to-budget coverage.
- Migration: an XP total that was level N under 1.0505 is never shown below
  N.
- Multiplier: with an optional line enabled, the simulated days to level 84
  are within ±1% of the core-only figure.

## Risks / Trade-offs

- **Estimates are still estimates.** The table makes them explicit and
  reviewable, but real usage may differ. A later tweak is a one-line table
  change plus a re-solved constant.
- **A steeper curve can make the next level feel far away.** `peakLevel`
  stops any drop. The "XP to next level" bar may jump once after the update,
  which is acceptable and mentioned in the release notes.

## Open Questions

- None blocking. The owner chose "calibrate the whole XP economy" on
  2026-09-25.
