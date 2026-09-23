## Why

Found independently by two code reviewers and confirmed by reading the code: nearly every JSON-file-backed store in all three SPM packages loaded with `(try? decoder.decode(...)) ?? []` and then latched `loaded = true`. If the file existed but failed to decode — a future model change that isn't backward compatible, a truncated/corrupted write, a hand edit — the store silently started EMPTY, and the very next write (`upsert`/`record`/`enqueue`/...) atomically persisted only the new data, permanently destroying everything that had been on disk: unsent food/weight/hydration outbox entries, custom foods, meal presets, favorites, the XP ledger, achievements, lifetime stats. Nothing was logged anywhere.

Several of those stores (XP, custom foods, meal presets, favorites, usage history) have no copy anywhere else — not in Garmin, and there is no iCloud (openspec/config.yaml) — so a wipe was unrecoverable, and it broke CLAUDE.md's "failures must surface" rule.

Separately, stores that built their in-memory index with `Dictionary(uniqueKeysWithValues:)` would TRAP on a duplicate id in the file, crashing the app on every launch.

## What Changes

- New `GarminKit.PersistedJSON.load(_:from:decoder:category:)` — the one shared load routine:
  - no file → `nil`, nothing logged (normal first launch);
  - file exists but can't be read → `nil`, `.error` logged to `DiagnosticsLog`, file left in place (it may just be locked by data protection before first unlock);
  - file read but doesn't decode → `nil`, `.error` logged (category, file name, truncated decoding error), and the file is MOVED ASIDE to `<name>.unreadable-<yyyyMMdd-HHmmss>.json` in the same directory, so the store's next save writes a fresh file instead of overwriting the original bytes (which stay recoverable by hand). A failed move is logged too;
  - success → the decoded value.
- `FoodLogCoreStorage` becomes `public` and gains `loadPersistedJSON(...)`, a straight passthrough to `PersistedJSON.load`, so Gamification — which deliberately does not depend on GarminKit — reaches the same single implementation via `GamificationStorage.loadPersistedJSON`.
- Every store's `loadIfNeeded()` now goes through it, each keeping its exact existing decoder configuration (`.iso8601` dates or not) so data already on the owner's phone still decodes:
  - GarminKit: `OutboxStore`, `WeightOutboxStore`, `HydrationOutboxStore`.
  - FoodLogCore: `CustomFoodStore`, `MealPresetStore`, `FavoriteFoodStore`, `ServingDefaultStore`, `UsageHistoryStore`, `FoodCacheStore`, `WeightStore`, `HydrationStore`, `FastingSessionStore`.
  - Gamification: `XPStore`, `AchievementStore`, `GoalStatusStore`, `ChallengeStore`, `ChallengeHistoryStore`, `DailyChallengeStore`, `LifetimeStatsStore`.
- Every `Dictionary(uniqueKeysWithValues:)` built from persisted data becomes `Dictionary(_:uniquingKeysWith: { _, last in last })`.

## Non-goals

- **`DiagnosticsLog`'s own store.** Deliberately left on its old loader: routing it through `PersistedJSON` would log into the very log that's mid-load. It is a capped rolling diagnostic window, not user data.
- **`DonationLedger` (app target, `GarminFood/App/LogDonations.swift`).** Same loader shape, but it lives in the app target (outside the three SPM packages this change covers) and holds only Siri donation identifiers — losing them means a deleted food may still be suggested by Siri, not user data loss.
- **Any automatic recovery or in-app surfacing of a quarantined file.** The file is preserved and the error is visible in Settings → Diagnostics; restoring it is a by-hand job. No store's public API, file name/location, or on-disk format changes.

## Impact

Affected surfaces: new `PersistedJSON.swift` (GarminKit), new `PersistedStoreLoading.swift` (FoodLogCore), `GamificationStorage.swift`, and the `loadIfNeeded()` of every store listed above. No new Garmin route, no new store, no network change, no UI change.

**Depends on**: `DiagnosticsLog` (add-reminders-and-diagnostics).

**Unblocks**: making a non-backward-compatible model change to any store without risking the owner's existing data.
