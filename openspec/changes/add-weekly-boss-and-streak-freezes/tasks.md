## 1. Streak freezes (Gamification, pure + store)

- [x] 1.1 `StreakEngine.simulate/status` gain `frozenDays: Set<Date> = []` and the `.frozen` outcome (design D5). Existing tests unchanged and green.
- [x] 1.2 `StreakHistory.summary` gains `frozenDays`; `Mark.frozen`.
- [x] 1.3 `StreakFreeze/StreakFreezeStore.swift` (frozen days + consumptions; Optional fields; quarantine helpers).
- [x] 1.4 `StreakFreeze/FreezeBalance.swift`: replay of `RewardLedger` freeze grants and consumptions, cap 2, overflow count.
- [x] 1.5 `StreakFreeze/StreakFreezePlanner.swift` (design D6).
- [x] 1.6 Freeze badges (`freeze.first`, `freeze.saved-100`) registered through the boss feature's `badges` (same change, no registry edit).
- [x] 1.7 Tests: frozen semantics (no length change, not in grace window, never resets, backfill = logged); planner cases (streak-breaking miss, grace day, streak < 3, > 7 days old, grant after miss, two misses/two freezes, idempotent); balance with overflow; spec scenario "streak 21 frozen Thursday".

## 2. Weekly boss (Gamification)

- [x] 2.1 `Features/Boss/BossCatalog.swift`: 10 archetypes (design D1) + badges.
- [x] 2.2 `Features/Boss/BossPicker.swift`: adherence, eligibility, exclusion, new-user ghost, tie-break, target formula.
- [x] 2.3 `Features/Boss/BossFight.swift`: hits, completed-day-only archetypes, defeat/escape.
- [x] 2.4 `BossStore` (26 weeks, Optional fields).
- [x] 2.5 Replace the stub `WeeklyBossFeature`: pick-if-missing, hits, grants `boss.defeat.<week>` + `boss.freeze.<week>`, intro and defeat moments, badges, summary; expose `currentBoss()`, `history()`, `bestiary()`.
- [x] 2.6 Tests: design D8 picker and fight lists; rewards once across two runs with a real `RewardLedger`.

## 3. App wiring (shared files allowed by the ownership table)

- [x] 3.1 `GamificationEngine`: run `StreakFreezePlanner` (local, no network) at the start of `refresh` and `handleLogConfirmed`, persist, queue `.freeze` moments, then pass `frozenDays` into the existing `StreakEngine.status` and `StreakHistory.summary` calls.
- [x] 3.2 `ProgressViews.swift`: `StreakDot` frozen style + label; "❄️ n/2" on `StreakSummaryCard` and `StreakDetailView`; freeze paragraph in "How streaks work".
- [x] 3.3 `Today/Slots/BossBannerSlot.swift`, `Progress/Slots/BossSlotView.swift`, `Progress/Boss/BossDetailView.swift` (why-this-boss line, HP bar, history, bestiary). VoiceOver, Dynamic Type, dark mode, Reduce Motion.

## 4. Verify

- [x] 4.1 `openspec validate add-weekly-boss-and-streak-freezes --strict` passes.
- [x] 4.2 CI green (`swift test` Gamification incl. all pre-existing streak tests; app + widget build). *Ticked 2026-09-26: merged to `main`, whose `Build iOS app` CI (package tests + app/widget build) is green (run on 0de2d46).*
- [ ] 4.3 On-device check: Monday shows a boss with a sensible "why" line; the streak card shows the freeze count; after deliberately missing a second day in a week with a freeze available, the next launch shows the day as frozen and the streak intact, and the streak reminder behaves as before.
