## 1. Tags (FoodLogCore)

- [x] 1.1 `Signals/FoodTag+Sport.swift` (`sport.carbRich`) and fill `Signals/FoodTagRules+Sport.swift`.
- [x] 1.2 Tagger golden cases: banán, ovesná kaše, energetický gel, "Rohlík tukový" → carbRich; "Rýžový nápoj" (a milk substitute) and "Banánový jogurt" → not carbRich (pinned by exclusions).

## 2. Rules (Gamification, pure)

- [x] 2.1 `Features/SportBody/SportActivityClass.swift` (design D1) + tests.
- [x] 2.2 `Features/SportBody/SportRules.swift`: fuel, recovery, earned-it, double day, gel guru, long haul, race day, carb loader (design D2).
- [x] 2.3 `Features/SportBody/BodyRules.swift`: goal direction, progress, first kilo, halfway, target, steady-30, fasting tiers.
- [x] 2.4 `SportBodyCatalog.swift`: badge definitions (`featureId: SportAndBodyFeature.id` = "sportBody", rarity overrides).
- [x] 2.5 Tests: every edge in design D7.

## 3. Feature

- [x] 3.1 `SportBodyStore` (activity ids / days, caps, Optional fields, quarantine helpers).
- [x] 3.2 Replace the stub `SportAndBodyFeature`: counts, unlocks, per-activity moment once, summary; expose `recentActivities()` and `bodyProgress()`.
- [x] 3.3 Tests: counts accumulate beyond 42 days via the store; one moment per activity; activities-unavailable path.

## 4. UI (thin)

- [x] 4.1 `Progress/Slots/SportBodySlotView.swift`.
- [x] 4.2 `Progress/SportBody/SportBodyView.swift`: activities with fuel/recovery ticks and the counted entries; weight milestones; fasting streak. VoiceOver, Dynamic Type, dark mode.

## 5. Verify

- [x] 5.1 `openspec validate add-sport-and-body-achievements --strict` passes.
- [x] 5.2 CI green (`swift test` FoodLogCore + Gamification; app + widget build). *Ticked 2026-09-26: merged to `main`, whose `Build iOS app` CI (package tests + app/widget build) is green (run on 0de2d46).*
- [ ] 5.3 On-device check: after a real run synced to Garmin, a pre-run carb log shows the run as fuelled in Sport & Body and unlocks "Fuelled Up" once; a post-run protein log marks it recovered.
