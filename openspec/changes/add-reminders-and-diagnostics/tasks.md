## 36. Notification planning (pure)

- [x] 36.1 Added `NotificationPreferences`/`ReminderSetting`/`NotificationPlanning.plan(...)` (`ios/FoodLogCore/Sources/FoodLogCore/NotificationPlanning.swift`) -- takes plain booleans, not `Gamification` types, per design.md D3.
- [x] 36.2 Unit tested (`NotificationPlanningTests.swift`): disabled-by-default plans nothing, a meal reminder is skipped once that meal is logged, the streak reminder only appears when at risk, the daily-challenge reminder is unconditional, every reminder enabled together, and the configured time is carried through.

## 37. Notification scheduling (side-effecting)

- [x] 37.1 Added `NotificationScheduler` (`ios/GarminFood/App/NotificationScheduler.swift`): requests authorization on demand, and `sync(...)` replans and diffs pending requests against `UNUserNotificationCenter`, per design.md D1/D2 (date-scoped identifiers, one-time triggers).
- [x] 37.2 Added `NotificationPreferencesStore` (`ios/GarminFood/App/NotificationPreferencesStore.swift`), `UserDefaults`-backed, mirroring `AppPreferences.swift`'s existing pattern.
- [x] 37.3 Wired `AppEnvironment.syncNotifications()` into `refreshOnForeground()` and `logConfirmed()`, guarded to skip while a past day is being viewed.
- [x] 37.4 Built `NotificationSettingsView` (`ios/GarminFood/Profile/NotificationSettingsView.swift`): per-reminder toggle + time picker, a denied-permission notice with a Settings link, linked from `SettingsView`.

## 38. Diagnostics log

- [x] 38.1 Added `DiagnosticsLog` (`ios/GarminKit/Sources/GarminKit/DiagnosticsLog.swift`): actor, JSON-file-backed (same directory convention as `Outbox`), capped at 500 entries, mirrored to `os.Logger`.
- [x] 38.2 Wired into `GarminClient.perform`/`throwIfNotSuccessful` (every route, one choke point each) and `Outbox.drain` (one summary per cycle).
- [x] 38.3 Wired into `LogEntryConfirmView.confirm()` and `MealPresetConfirmView.confirm()`'s existing `catch` blocks -- the real error, alongside the unchanged generic user-facing message.
- [x] 38.4 Built `DiagnosticsLogView` (`ios/GarminFood/Profile/DiagnosticsLogView.swift`): list, level badges, copy-all (pasteboard), clear (confirmed), linked from `SettingsView`.

## 39. Documentation

- [x] 39.1 Fixed `openspec/config.yaml`'s wrong "Apple Watch" owner-context claim (owner has a Garmin Forerunner 970, not an Apple Watch).
- [x] 39.2 Reconciled `expand-gamification-depth/tasks.md`'s 0/36 tracking drift against actually-shipped code.
- [x] 39.3 This change's own proposal/design/specs/tasks docs.
