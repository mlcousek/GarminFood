Every task ends with CI green: `swift test` for GarminKit, FoodLogCore and
Gamification, the app and widget `xcodebuild`, and the `localization` job.
Commit after each task. All new user-facing text is in English and Czech,
with Czech plural forms (one, few, many, other) for counts.

## 1. Plan

- [x] 1.1 Proposal, design (D1–D8), `data-safety` spec and tasks. `openspec validate add-data-safety --strict`.
- [x] 1.2 `add-standalone-mode/tasks.md`: mark 6.1–6.3 as moved to this change.

## 2. Compatibility contract and fixtures (D1, D2, D7)

- [ ] 2.1 `docs/data-compatibility.md`: the contract, when to bump a store version, and how to add a fixture.
- [ ] 2.2 GarminKit: `Fixtures/Stores/*` for the three outboxes and the diagnostics log. `StoreFixtureTests`: load each through the real store, and a coverage test for file names.
- [ ] 2.3 FoodLogCore: fixtures for every store, including the food-log month shard and the offline-index status. `StoreFixtureTests` and a coverage test.
- [ ] 2.4 Gamification: fixtures for every core and feature store. `StoreFixtureTests` and a coverage test.
- [ ] 2.5 `exclude: ["Fixtures"]` on the three test targets.

## 3. Backup core in FoodLogCore `Backup/` (D1, D3, D4, D5)

- [ ] 3.1 `StoreCatalog` (id, location, schemaVersion, area, inBackup), `BackupExclusions` (files, preference keys, credential-like names), `BackupSecretPolicy` (content scan). Tests:
  - the catalog agrees with the exclusions;
  - every store file name in the three packages' sources is in the catalog;
  - the path-safety rules.
- [ ] 3.2 `PreferenceValue` (typed JSON, property-list round trip) and `PreferencesBackup` (capture with exclusions; `restoredDomain` replaces included keys and keeps excluded ones). Tests.
- [ ] 3.3 `BackupManifest`, `BackupContainer`, `BackupCompatibility` (schema, format version, store versions), `BackupPreview` (counts per area). Tests: round trip, newer format refused, newer store version refused, not-a-backup, preview counts.
- [ ] 3.4 `BackupVault` snapshots:
  - `writeSnapshot` (temp directory, then rename; generic walk; exclusions; secret skip);
  - `isAutomaticSnapshotDue`, retention (14 automatic or manual, 5 safety, temp cleanup), no snapshot of an empty data set, and `BackupStatus`.

  Tests on temp directories with real files, including a new store included without registration.
- [ ] 3.5 `BackupVault` export and staged restore:
  - `makeExportContainer`, `stageRestore(snapshotId:)`, `stageRestore(container:)`, `cancelPendingRestore`;
  - `applyPendingRestore`: re-check, safety snapshot, replace included files, keep excluded ones, roll back on failure, record status.

  Tests:
  - the secret scan over the snapshot, the export and the staged output;
  - outboxes and diagnostics survive a restore untouched;
  - files missing from the backup are removed;
  - cancel means no change;
  - a newer version is refused at stage and at apply.

## 4. App (D3, D4, D5, D6)

- [ ] 4.1 `GarminFoodApp.init`: `DataSafetyLaunch.applyPendingRestoreIfNeeded()` (synchronous, before any store), which applies the preferences through `PreferencesBackup.restoredDomain`. Also a daily snapshot on the active scene phase, detached at background priority.
- [ ] 4.2 `DataSafetyController` and `DataSettingsView` (Settings → Data):
  - status, snapshot list with restore, "Back up now", export through `fileExporter`, import through `fileImporter` with a preview sheet;
  - the pending-restore state and cancel, the last restore result, and the note about undelivered entries.
- [ ] 4.3 `BackupReminderBanner` in `TodaySlotHost` (more than 14 days since the last export, or never; "Not now" dismisses it for 14 days) and the "Data" row in Settings.
- [ ] 4.4 English and Czech strings in `Localizable.xcstrings` with plurals. `node tools/check-localizations.mjs` and `bash tools/lint-design-tokens.sh` pass.

## 5. Hand-off and verification

- [ ] 5.1 Tell the supplements agent to add fixtures and catalog entries for its stores, following `docs/data-compatibility.md`.
- [ ] 5.2 CI green on the PR.
- [ ] 5.3 On device, owner:
  - (a) update the app over AltStore: all data is still there;
  - (b) the next day, Settings → Data lists an automatic snapshot;
  - (c) export to Files, delete the app, reinstall, import, reopen: the food log, custom foods, presets, weight, water, notes and progress are back, and Garmin asks for sign-in;
  - (d) restore yesterday's snapshot: a safety snapshot appears and queued entries still deliver once.
