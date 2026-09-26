## 1. Rules (Gamification, pure)

- [x] 1.1 `Features/Secret/SecretCatalog.swift`: 15 secret definitions + `secret.keeper` (`visibility`, `featureId: "secrets"`, rarity overrides).
- [x] 1.2 `Features/Secret/SecretRules.swift`: one pure function per rule over `SignalsSnapshot` (design D2).
- [x] 1.3 Tests: one positive + ≥ 1 negative per rule (design D5 list), ids unique, all secret except keeper.

## 2. Feature

- [x] 2.1 Replace the stub `SecretAchievementsFeature`: evaluate locked secrets, unlock ids, grants `secrets.<badge id>`, one combined `.secret` moment, summary ("3/15").
- [x] 2.2 Tests: combined moment; XP once across two runs (real `RewardLedger`); keeper after all 15; no evaluation of the current day for completed-day rules.

## 3. UI (thin)

- [x] 3.1 `Progress/Slots/SecretsSlotView.swift`: count + keyhole; navigates to the Secret group of `AchievementsView`.
- [ ] 3.2 Confirm locked secrets are never rendered or read by VoiceOver with their real title (manual check on device; UI is not unit-tested). Code-reviewed: the slot shows counts only; tiles, detail sheet and VoiceOver labels use "???" / "Secret achievement, locked"; secret moments flip in (cross-fade with Reduce Motion).

## 4. Verify

- [x] 4.1 `openspec validate add-secret-achievements --strict` passes.
- [x] 4.2 CI green (`swift test` Gamification; app + widget build). *Ticked 2026-09-26: merged to `main`, whose `Build iOS app` CI (package tests + app/widget build) is green (run on 0de2d46).*
- [ ] 4.3 On-device check: Achievements shows "??? × 15"; logging 5 coffees in a day reveals Barista Mode with the reveal moment once.
