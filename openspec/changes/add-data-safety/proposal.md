## Why

The owner, 2026-09-25: "I want to use it and also develop it, so when I
introduce a new version I don't want to lose the data."

Everything the app knows that isn't in Garmin lives in JSON files under
Application Support, plus preferences in `UserDefaults.standard`:

- `GarminKit/` holds the outboxes and the diagnostics log;
- `FoodLogCore/` holds the stores, the local food log and the offline index;
- `Gamification/` holds XP, achievements, challenges and feature stores;
- `GarminFood/` holds the Siri donation ledger.

AltStore updates keep the container, but three things can still lose data:

1. **Deleting or reinstalling the app**, or re-signing under a different
   Apple ID. The container is gone, and on a free account there is no
   iCloud, no App Group and no Keychain sharing to fall back on.
2. **A new version that can't decode an old file.** Since #36
   (`fix-silent-store-wipe`) such a file is quarantined instead of silently
   overwritten. The data is kept on disk, but the app then shows the store
   as empty. Only conventions stop a developer from shipping that mistake.
3. **Losing the phone.**

The owner chose to protect against all three. A database migration
(SQLite/SwiftData) was explicitly rejected, and this has to ship before the
upcoming release.

`add-standalone-mode` wave 6 (tasks 6.1–6.3, `specs/data-backup`) already
planned a manual backup for standalone mode. This change takes ownership of
that plan, generalises it to both modes, and adds the two protections it
lacked: CI checks of old file formats, and automatic on-device snapshots.

## What Changes

- **Compatibility contract and store versions (D1).**
  - A documented contract: new fields are Optional or defaulted, and no key
    is renamed or removed without a decode shim. An unreadable file is
    quarantined, never overwritten (already true since #36).
  - A `StoreCatalog` in FoodLogCore gives every known store file a schema
    version. The version is bumped when a change makes the file unreadable
    by the previous release.
- **Old-format fixtures in CI (D2).**
  - GarminKit, FoodLogCore and Gamification each commit a JSON fixture of
    every persisted store, as the current release writes it.
  - Tests load each fixture through the real store with today's code.
  - A coverage test fails when a store file name in the sources has no
    fixture.
  - `docs/data-compatibility.md` tells developers how to add a fixture.
- **Automatic rolling snapshots (D3).**
  - At most once a day, on foreground and off the main thread, the app
    copies every JSON data file generically to
    `Application Support/Backups/<yyyy-MM-dd>/`, so new stores such as
    supplements are included without registration.
  - The snapshot also holds the app's preferences as typed JSON.
  - The last 14 are kept.
  - It excludes tokens, outboxes, the offline index, the diagnostics log,
    the Garmin health cache and the Siri donation ledger.
  - Failures go to `DiagnosticsLog` and show on the Data screen.
- **Staged restore (D4).**
  - Restoring a snapshot or an imported file never touches loaded stores.
    It is staged, and the app asks the user to reopen it.
  - The staged restore is applied at the next launch, before `AppServices`
    exists.
  - A safety snapshot is always taken first.
  - A backup from a newer format or store version is refused.
- **Export and import of one file (D5).**
  - One `.json` container holds the manifest, every data file and the
    preferences.
  - It is shared with `fileExporter`/ShareLink to Files or iCloud Drive,
    which needs no entitlement.
  - Import uses `fileImporter`, then a version check, then a preview (date,
    app version, counts per area), then the D4 restore.
  - A test scans the output for token keys to prove it holds no secrets.
- **Settings → Data (D6).**
  - Shows the last snapshot, the snapshot list with Restore, "Export
    backup…", "Import backup…" and a pending-restore state.
  - A quiet Today reminder appears when the last export is more than 14
    days old (standalone's 6.3), and can be dismissed for 14 days.
  - All text is in English and Czech.
- **CI (D7).** The fixture tests run in the existing `swift test` steps. The
  workflow does not change.

## Capabilities

### New Capabilities

- `data-safety`: the store compatibility contract and fixtures, automatic
  snapshots, staged restore, and single-file export and import.

### Modified Capabilities

- `add-standalone-mode`'s `data-backup` (not yet archived) is superseded by
  `data-safety`. Its tasks 6.1–6.3 are marked "moved to add-data-safety".
  Its CSV export is a non-goal here (see below).

## Non-goals

- A database migration (SQLite, SwiftData, Core Data). Rejected by the
  owner. The stores stay JSON files.
- Merging two histories. Restore **replaces**, as in standalone's D9.
- Cloud sync, iCloud containers, App Groups or Keychain sharing. None of
  them are available on a free Apple account.
- Backing up **Garmin tokens**, which stay in the Keychain
  (`ThisDeviceOnly`). After a restore on a new phone the user signs in
  again.
- Backing up or restoring the **outboxes**. They are per-device delivery
  state. Replaying a stale outbox would send entries to Garmin a second
  time (design D8).
- The `food-log.csv` spreadsheet export from standalone's 6.1. The owner
  asked for data safety, not a report. It can follow later as a separate
  change.
- Protecting against a **downgrade**, i.e. sideloading an older build over
  newer data. The quarantine still keeps the file.
- Encrypting the exported file. It contains food and weight data but no
  credentials. The user chooses where it goes.

## Impact

- New `ios/FoodLogCore/Sources/FoodLogCore/Backup/`, pure and tested:
  - `StoreCatalog`;
  - `BackupManifest`, `BackupContainer`, `PreferenceValue`;
  - `BackupExclusions`, the secret policy;
  - `SnapshotWriter`, `SnapshotRetention`;
  - `BackupCompatibility`, the version check;
  - `RestoreStager`/`RestoreApplier`;
  - `BackupPreview`.
- New app files:
  - `ios/GarminFood/Settings/DataSettingsView.swift` and its siblings, the
    Data screen and its controller;
  - the Today reminder banner.
- Additive edits:
  - `GarminFoodApp.swift`: the synchronous restore hook in `init`, and the
    daily snapshot on the active scene phase;
  - `SettingsView.swift`: one row;
  - `TodaySlotHost.swift`: one line;
  - `Localizable.xcstrings`: new keys only;
  - the three packages' test targets: `exclude: ["Fixtures"]`.
- New `docs/data-compatibility.md`.
- No new Garmin route and no network. Garmin-mode behaviour is otherwise
  unchanged, and nothing is added to a confirm path.
- **Depends on**:
  - `fix-silent-store-wipe` (#36): the quarantine and unreadable-file
    contract that restore relies on;
  - `add-reminders-and-diagnostics`: `DiagnosticsLog`.
- **Unblocks**:
  - `add-standalone-mode` wave 6, since the fiancée's install needs a
    backup before she relies on it;
  - `add-supplements` task 2.3, since its stores are included
    automatically and it only adds fixtures;
  - every future store-format change, which becomes safe to ship.
