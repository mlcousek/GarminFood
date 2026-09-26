## 1. Shared loader

- [x] 1.1 `PersistedJSON.load(_:from:decoder:category:)` (GarminKit/PersistedJSON.swift): missing file → `nil` silently; unreadable → `nil` + `.error` log, file left in place; undecodable → `nil` + `.error` log + file moved aside to `<name>.unreadable-<yyyyMMdd-HHmmss>.json` (short random suffix if that name is taken; a failed move is logged too); success → decoded value.
- [x] 1.2 `FoodLogCoreStorage` made `public`, gains `loadPersistedJSON(...)` passthrough (FoodLogCore/PersistedStoreLoading.swift).
- [x] 1.3 `GamificationStorage.loadPersistedJSON(...)` forwards to the FoodLogCore passthrough -- Gamification still does not depend on GarminKit.

## 2. Convert every store

- [x] 2.1 GarminKit: `OutboxStore`, `WeightOutboxStore`, `HydrationOutboxStore`.
- [x] 2.2 FoodLogCore: `CustomFoodStore`, `MealPresetStore`, `FavoriteFoodStore`, `ServingDefaultStore`, `UsageHistoryStore`, `FoodCacheStore`, `WeightStore`, `HydrationStore`, `FastingSessionStore`.
- [x] 2.3 Gamification: `XPStore`, `AchievementStore`, `GoalStatusStore`, `ChallengeStore`, `ChallengeHistoryStore`, `DailyChallengeStore`, `LifetimeStatsStore`.
- [x] 2.4 Each store keeps its exact existing decoder configuration (`.iso8601` dates where it had them, plain `JSONDecoder()` where it didn't).
- [x] 2.5 `Dictionary(uniqueKeysWithValues:)` over persisted data → `Dictionary(_:uniquingKeysWith: { _, last in last })` (`CustomFoodStore`, `FavoriteFoodStore`, `FoodCacheStore`, `HydrationStore`, `MealPresetStore`, `ServingDefaultStore`, `WeightStore`).
- [x] 2.6 Deliberately NOT converted: `DiagnosticsLog` (would log into itself mid-load), `DonationLedger` (app target, Siri identifiers only) -- see proposal.md's Non-goals.

## 3. Tests

- [x] 3.1 `GarminKitTests/PersistedJSONTests.swift`: missing file → `nil` and nothing created; valid file → decoded value, left in place; corrupt bytes and wrong-shape JSON → `nil`, original path gone, exactly one `*.unreadable-*.json` sibling holding the original bytes; quarantine name doesn't collide with an existing one.
- [x] 3.2 Store-level regression per package -- garbage in the store's file, load (starts empty), write, assert the garbage bytes still exist in the quarantined sibling: `Outbox`/`OutboxStore` (`PersistedJSONTests`), `CustomFoodStore` (`CustomFoodTests`, plus a duplicate-id-doesn't-trap test), `XPStore` (`XPStoreTests`).

## 4. Verification

- [x] 4.1 **CARRIED, needs CI.** No local Swift/Xcode toolchain -- push this branch and let `.github/workflows/build.yml` confirm all three packages and the app target still build and the new/existing tests pass. *Ticked 2026-09-26: merged to `main`, whose `Build iOS app` CI (package tests + app/widget build) is green (run on 0de2d46).*
- [ ] 4.2 **CARRIED, needs a real device.** Nothing user-visible should change on a healthy install: sideload, confirm existing custom foods / presets / favorites / XP / achievements / pending sync queue all still load exactly as before (i.e. every store's existing on-disk data still decodes with its preserved decoder), and that Settings → Diagnostics shows no new `could not decode` lines.
