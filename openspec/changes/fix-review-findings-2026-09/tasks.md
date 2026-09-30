## 1. Verify every finding

- [x] 1.1 Check findings 1-16 against e2d871a; record verdict and evidence in design.md

## 2. Real findings

- [x] 2.1 (1) `ConfirmedLogRelay` + `QuickPickCommit` in FoodLogCore; quick-pick Controls, "Log usual food" and "Log <food>" report through it; `AppEnvironment` attaches `handleLogConfirmed`. Test: `ConfirmedLogRelayTests`
- [x] 2.2 (2) `CustomFoodCreation` (2xx = create, injected send) in GarminKit; `CustomFoodCreateGate` in FoodLogCore; create screen uses both; new EN + CS string. Tests: `CustomFoodCreationTests`, `CustomFoodCreateGateTests`
- [x] 2.3 (3, 8) `BackgroundOutboxDelivery` + `OutboxBacklog`; `BackgroundRefresh` and `didEnterBackground` use them; `weightLogged`/`hydrationLogged` refresh the queue count. Test: `BackgroundOutboxDeliveryTests`
- [x] 2.4 (4) Local save first, then enqueue under a pre-chosen id; store rollback on a failed save. Test: `LocalFirstHealthLoggingTests`
- [x] 2.5 (9) Account stamp + scope in all three outboxes and Reconciliation; `GarminAccountKey` recorded by `ProfileLoader`; sign-out ties unstamped entries. Test: `DeliverySafetyTests`
- [x] 2.6 (10) Re-sync after the permission prompt grants. Test: `NotificationWindowTests`
- [x] 2.7 (11) `NotificationPlanning.planWindow` (7 days) and `TrainingReminderPlanner.plan(days:)`. Tests: `NotificationWindowTests`, `CheckInBuilderTests.testAWiderWindowPlansTheFollowingDaysToo`
- [x] 2.8 (16) Send marker in all three outboxes; no blind re-send on reload. Test: `DeliverySafetyTests`

## 3. Checks

- [x] 3.1 `node tools/check-localizations.mjs --scan`, `sh tools/lint-design-tokens.sh`
- [x] 3.2 `openspec validate fix-review-findings-2026-09 --strict`
- [ ] 3.3 CI green (`swift test` for GarminKit, FoodLogCore, TrainingCore; app + widget build)
- [ ] 3.4 Device check after sideload: quick-pick Control awards XP once; create-in-Garmin with an odd response keeps the button off; reminders present the next morning without opening the app
