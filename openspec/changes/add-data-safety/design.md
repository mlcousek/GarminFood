## Context

- **Where the data lives.** Every store is a JSON file under Application
  Support, one subdirectory per package:
  - `GarminKit/`: `outbox-app.json`, `weight-outbox-app.json`,
    `hydration-outbox-app.json` and `diagnostics-log.json`;
  - `FoodLogCore/`: about fifteen stores, the month-sharded `FoodLog/` and
    `OfflineIndex/`;
  - `Gamification/`: eight core stores and `features/<id>/*.json`;
  - `GarminFood/`: `donations.json`.

  Preferences are in `UserDefaults.standard`. Garmin tokens are in the
  Keychain (`...ThisDeviceOnly`, TokenProvider.swift), never in a file.
- **How stores load and save.** Every store loads through
  `PersistedJSON.load` (#36). A file that doesn't decode is moved aside as
  `<name>.unreadable-<stamp>.json`, and the store starts empty. A file that
  can't be read yet blocks saves (`ensureSafeToWrite`). Every store writes
  atomically. Every store is loaded once per process and held by
  `AppServices.shared` (one instance per process).
- **Constraints.**
  - Free Apple account: no iCloud container, App Group or Keychain sharing.
  - No Mac: CI is the only compiler.
  - No network in any of this.
  - Local-first: nothing on a confirm path.
- `add-standalone-mode` D9 designed a `BackupBundle` built from decoded
  store values. This change keeps its intent (a versioned single file, a
  preview, a safety backup first, replace rather than merge, no secrets) but
  copies **files** instead of decoded values (D3).

## Goals / Non-goals

Goals: no store format change can reach a release without CI noticing;
yesterday's data can be recovered on the phone; everything can be moved to
a new phone or install through one file. Non-goals are listed in the
proposal.

## Decisions

### D1 — Compatibility contract and store versions

The contract, written down in `docs/data-compatibility.md` and enforced by
D2:

1. **Adding a field.** A new stored field is Optional or has a
   decode-time default (`decodeIfPresent ?? default`). Old files must
   still decode.
2. **Renaming or removing a key.** Never done without a decode shim that
   still reads the old key. The same applies to changing a field's type,
   or an enum's raw values.
3. **Adding an enum case.** Safe for the new app, but a file containing the
   new case can't be read by the previous release. That breaks forward
   compatibility, so the store's version is bumped (point 5).
4. **An unreadable file** is quarantined, never overwritten (#36,
   unchanged).
5. **Store versions.** Every store has a version in `StoreCatalog`
   (FoodLogCore `Backup/`): an id, a location, `schemaVersion` (all 1
   today), a preview area and whether it is backed up.
   - `schemaVersion` is bumped when a change makes the file unreadable by
     the **previous** release. Additive Optional fields don't bump it.
   - Snapshots and exports record each file's store id and version.
   - Restore refuses a backup that contains a store version newer than
     this build knows (D4).

Why a catalog rather than a `version` field inside every file? Adding a
field to every store touches about 35 files owned by other changes and
their encoders, and it would need its own migration. The catalog gives the
same guarantee for backups, and a per-file field can still be added to a
store when it first needs a real migration.

A coverage test fails when a store file name appears in the package
sources but not in the catalog. So a new store, such as supplements', must
register its version.

### D2 — Old-format fixtures in CI

- **Fixtures.** Each package (GarminKit, FoodLogCore, Gamification) commits
  `Tests/<Target>/Fixtures/Stores/<file>.json`, one per persisted store, as
  the current release writes it. The encoder is the same: date strategy,
  CodingKeys, enum raw values, omitted nils.
- **Fixture tests** (`StoreFixtureTests`) copy each fixture into a fresh
  temp directory under its real file name and open the **real store** on
  it. The test then asserts specific decoded values, and asserts that no
  `.unreadable-` file appeared. This matters because a decode failure
  doesn't throw; it quarantines the file and reads as empty.
- **Coverage.** A coverage test in each package scans
  `Sources/<Package>/**/*.swift` for string-literal file names
  (`"name.json"`). It fails when a name has neither a fixture nor an
  exemption with a written reason. It also fails on orphan fixtures.
  Interpolated names (the outboxes, the food-log month shards) are listed
  by hand in the test.
- **Fixtures are append-only.** When a format changes, the developer adds
  `<file>.v2.json` next to the old fixture, and the old one must keep
  decoding. That is exactly the "new app, old file" case an update hits.
- **How tests find them.** Fixtures are read through `#filePath`, and
  `exclude: ["Fixtures"]` in each test target keeps SPM from treating them
  as sources. They are not bundled, so no `Bundle.module` is needed.

### D3 — Automatic rolling snapshots

- **When.** On the scene becoming active, at most once per calendar day,
  in a detached background-priority task. The job
  (`DataSafetyController.snapshotIfDue`) is never awaited by anything the
  user sees.
- **What.** `BackupVault.writeSnapshot` walks Application Support
  recursively and copies every regular `*.json` file that
  `BackupExclusions.includesFile` accepts. This is generic by design: a new
  store (supplements, a future goals store) is included with no
  registration.
- **Excluded:**
  - `Backups/` itself;
  - every path with a component containing `outbox` (D8);
  - `GarminKit/diagnostics-log.json`, which is copied from Diagnostics
    instead;
  - `FoodLogCore/garmin-health-cache.json`, a Garmin read cache;
  - `FoodLogCore/OfflineIndex/`, which is large and re-downloadable;
  - `GarminFood/donations.json`, device-local Siri state;
  - any path component that looks like a credential (`token`, `oauth`,
    `cookie`, `credential`, `password`). "secret" is left off because the
    `Gamification/features/secrets/` directory is legitimate;
  - any file whose **content** contains an OAuth or token JSON key
    (`BackupSecretPolicy`), which is skipped and logged.

  Tokens are in the Keychain anyway. The two checks above are defense in
  depth.
- **Preferences.** The app's `UserDefaults` persistent domain is saved as
  typed JSON (`[String: PreferenceValue]`, with `type`/`value` pairs, so
  bool, int, double, date and data survive a round trip). Some keys are
  excluded:
  - `dataSafety.*`, the backup bookkeeping itself;
  - `developer.*`, testing switches;
  - system prefixes (`Apple`, `NS`, `com.apple.`, `WebKit`);
  - any key containing a credential-like word.
- **Layout and write order.** Everything is written to `Backups/.tmp-<uuid>/`
  first, then renamed to `Backups/<yyyy-MM-dd>/`, so a crash never leaves
  a half-written snapshot that looks complete:

  ```
  Backups/<id>/manifest.json      BackupManifest (schema, formatVersion,
                                  kind, createdAt, appVersion, files with
                                  byteCount/storeId/storeVersion)
  Backups/<id>/preferences.json   [String: PreferenceValue]
  Backups/<id>/data/<relative path of each file>
  ```
- **Retention.** The newest 14 automatic (and manual "Back up now")
  snapshots are kept, plus the newest 5 safety snapshots. Leftover `.tmp-*`
  directories are removed.
- **An empty data set is not snapshotted.** A wiped or brand-new container
  must not rotate good snapshots out.
- **Status.** Every attempt records its outcome in `Backups/status.json`
  (`BackupStatus`: last attempt, last success, last error, last restore).
  A failure is logged to `DiagnosticsLog` (category `DataSafety`) and shown
  on the Data screen.

### D4 — Staged restore, applied at the next launch

Restoring while the stores are loaded would be undone by the next save of
any in-memory store. The in-memory copy and the file would disagree, which
is the bug class `AppServices` exists to prevent. So a restore happens in
two steps.

1. **Stage** (in the running app).
   - `stageRestore(snapshotId:)` or `stageRestore(container:)` validates
     the backup: its schema, `BackupCompatibility.check` and safe relative
     paths (no `..`, nothing absolute, nothing under `Backups/`).
   - It writes the backup as `Backups/.pending-restore/`, in the same
     layout as a snapshot, by writing to a temp directory and then
     renaming it.
   - The Data screen then shows "Close GarminFood and open it again to
     finish restoring", with "Cancel restore".
2. **Apply** (`GarminFoodApp.init`, before `ContentView` and so before
   `AppServices.shared` or any store exists). This is synchronous, with
   file operations only and no network.
   1. Re-check compatibility.
   2. Write a **safety snapshot** of the current data and preferences. If
      that fails, the restore is abandoned and nothing is touched.
   3. Delete the current files that `includesFile` accepts. Excluded files
      stay exactly as they are: outboxes, diagnostics, the offline index,
      the health cache and the donation ledger.
   4. Copy in the staged files.
   5. Replace the includable preference keys. Excluded keys stay, and
      backupable keys that are absent from the backup are removed, so this
      is a replace, not a merge.
   6. Remove the staged directory and record the outcome in
      `status.json`.

   If step 4 fails partway, the safety snapshot's files are copied back.
   Every failure is logged and reported on the Data screen.

**Version check (`BackupCompatibility`).** A backup is refused, and
nothing changes, when:
- its schema isn't `garminfood.backup`: "This isn't a GarminFood backup";
- its `formatVersion` is newer than this build supports: "Update the app";
- any file's `storeVersion` is newer than this build's catalog: "Update
  the app".

A file whose store is unknown to the catalog (a newer app's new store) is
still restored. This build ignores it, and a later update reads it.

### D5 — Single-file export and import

**Why one JSON file and not a zip?**
- iOS Foundation has no public zip or unzip API. `NSFileCoordinator`'s
  `.forUploading` can zip a directory, but nothing unzips.
- A third-party archive library would be the first external dependency
  in the project.
- A single JSON container (`BackupContainer`) is plain Codable, is
  testable in `swift test`, and still opens in any text editor.

```
{ "manifest": BackupManifest (kind "export"),
  "files": [ { "path": "FoodLogCore/custom-foods.json", "contents": "<base64>" } ],
  "preferences": { "preferences.haptics": { "type": "bool", "value": true } } }
```

- **File contents are base64** (JSONEncoder's default for `Data`), so a
  restore writes back the exact original bytes. Each store's own decoder,
  shims and quarantine then apply unchanged. Base64 makes the file about a
  third larger, which is acceptable for a few MB of JSON.
- **Export.** "Export backup…" builds the container off the main thread
  and presents `fileExporter` with a `.json` document named
  `GarminFood-backup-<yyyy-MM-dd>.json`, which can be saved to Files or
  iCloud Drive without any entitlement. On success it records
  `dataSafety.lastExportAt`.
- **Import.** "Import backup…" uses `fileImporter([.json])` and reads the
  file inside a security-scoped access. It decodes the container, checks
  it with `BackupCompatibility`, then shows a preview:
  - the backup's date and app version;
  - counts per area (food-log entries, custom foods, meal presets,
    favourites, weigh-ins, drinks, day notes), from `BackupPreview`, which
    counts top-level JSON arrays generically;
  - the number of progress and history files;
  - "Your current data is saved as a safety backup first".

  On confirm it stages the container (D4).
- **No secrets.** `BackupSecretExclusionTests` builds a data directory that
  contains a token-like file, a file with an `oauth_token_secret` key and
  token-like preference keys. It then exports, snapshots and stages, and
  scans every byte of the outputs (base64 decoded) for the token key names
  and the planted secret values.

### D6 — Settings → Data

A new row "Data" in Settings (additive) opens `DataSettingsView`.

- **Pending restore**, shown on top when a restore is staged: the
  instruction to reopen the app, and "Cancel restore".
- **Last restore result**, shown once after a restore: "Restored the
  backup from …" or "Restore failed: …".
- **Automatic backups**:
  - the last backup ("Today", "N days ago", "None yet");
  - a warning when the last attempt failed, with the reason;
  - "Back up now";
  - the list of snapshots (date, kind, file count), where tapping one
    asks to confirm and then stages the restore.
- **Export**:
  - "Export backup…";
  - "Last export: N days ago" or "Never";
  - a note when entries are still waiting for Garmin, since they are not
    part of backups (D8).
- **Import**: "Import backup…", which leads to the preview sheet.

**Reminder.** When the last export is older than 14 days, or there has
never been one, and it wasn't dismissed in the last 14 days, a quiet
`BackupReminderBanner` appears in the Today banner slot (`TodaySlotHost`,
one added line). It offers "Export" (which opens the Data screen) and
"Not now" (dismissed for 14 days). This is standalone's 6.3, in both modes.

All text is English and Czech. Counts use plural variations (Czech one,
few, many, other). Colors come only from `Theme` tokens.

Logic lives in FoodLogCore's `Backup/`. `DataSafetyController` (app, an
`@Observable` that is not stored in `AppEnvironment`) only glues it to
UserDefaults, Bundle and the file pickers.

### D7 — CI

The fixture tests and Backup tests are ordinary XCTest in the existing
packages. The existing `swift test` steps in `.github/workflows/build.yml`
run them, so the workflow doesn't change. `node
tools/check-localizations.mjs` covers the new strings.

### D8 — Outboxes are not backed up and restore never touches them

Undelivered entries are user data, so this was decided deliberately.

- **What an outbox is.** It is per-device delivery state for Garmin, the
  system of record. It is not history: a delivered entry leaves it within
  seconds while the phone is online.
- **Why not back it up.** Restoring a snapshot taken while an entry was
  queued, after that entry was delivered, would send it again. Garmin has
  no idempotency key (Outbox.swift's header), and Reconciliation only
  removes the duplicate after the fact, and only for food.
- **What restore does.** It leaves the current outboxes in place, so
  anything this phone still has queued is delivered after a restore
  exactly as before.
- **What is lost.** Only entries still queued on a phone that is lost
  before it next reaches Garmin, which no backup taken on that phone could
  cover reliably anyway.
- **The local copies are backed up.** Weight and water entries have their
  own local stores (`weight-entries.json`, `hydration-entries.json`), which
  are backed up. In standalone mode the local food log is the system of
  record, and it is backed up.
- **What the user sees.** The Data screen shows how many entries are still
  waiting for Garmin, so "deliver first" is visible before an export.

## Risks / Trade-offs

- **Fixtures written by hand.** No Mac means no generated fixtures, and a
  wrong fixture fails CI loudly, which is safe. They are checked against
  each type's CodingKeys and encoder settings, and the first CI run
  confirms them.
- **Consistency across files.** A snapshot copies files one by one while
  the app may be writing. Each file is internally consistent (atomic
  writes), but two files may be a few seconds apart. That is acceptable
  for disaster recovery.
- **Relaunch friction.** The user has to reopen the app after staging a
  restore. This is intentional (D4), and it's the only way to guarantee no
  in-memory store survives the restore.
- **Space.** At most 19 snapshots of a few MB each. A large food log could
  make this tens of MB. Snapshots could be compressed later if needed.
- **Export privacy.** The file holds health data in plain text wherever
  the user saves it. Stated in the footer.

## Migration Plan

The first launch of this version takes the first snapshot. Nothing
existing changes shape, and no store file is rewritten.

## Open Questions

None blocking. After the release, consider CSV export (standalone 6.1's
second half) and a per-store `version` field when a store first needs a
real migration.
