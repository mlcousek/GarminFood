## ADDED Requirements

### Requirement: Every persisted store format is proven readable in CI

The system SHALL keep, for each package that persists JSON stores, a
committed fixture of every store file as written by the current release,
and a test that loads each fixture through the real store and asserts its
decoded values. A store file name in the package sources that has no fixture
and no written exemption SHALL fail CI. Existing fixtures SHALL NOT be
edited or deleted when a format changes; a new fixture is added beside them.

#### Scenario: A field is renamed without a shim

- **WHEN** a developer renames `name` to `title` in `CustomFoodDraft` without a decode shim and pushes
- **THEN** the FoodLogCore fixture test for `custom-foods.json` fails because the store reads zero custom foods and a `.unreadable-` file appears

#### Scenario: A new store without a fixture

- **WHEN** a developer adds a store writing `"supplement-plan.json"` and no fixture
- **THEN** `testEveryPersistedFileHasAFixture` fails and names `supplement-plan.json`

### Requirement: Every store has a schema version and newer backups are refused

The system SHALL record a schema version for every known store in a store
catalog, SHALL record each backed-up file's store id and version in the
backup manifest, and SHALL refuse to restore a backup whose format version or
any store version is newer than the running build supports, changing
nothing.

#### Scenario: Backup from a newer build

- **WHEN** the user imports a backup whose manifest lists `custom-foods` at version 2 while this build's catalog has version 1
- **THEN** the app says the backup needs a newer app version and no file or preference is changed

#### Scenario: Not a backup

- **WHEN** the user picks an arbitrary JSON file that has no backup manifest
- **THEN** the app says it is not a GarminFood backup and nothing is staged

### Requirement: The app takes an automatic snapshot at most once a day

The system SHALL, when the app becomes active and no automatic snapshot
exists for the current calendar day, copy every included data file and the
included preferences into a new snapshot under
`Application Support/Backups/`, off the main thread and never on a confirm
path, keeping the newest 14 automatic snapshots and the newest 5 safety
snapshots. It SHALL NOT write a snapshot of an empty data set. A failure
SHALL be logged to diagnostics and shown in Settings → Data.

#### Scenario: Second foreground on the same day

- **WHEN** the app becomes active at 08:00 and again at 13:00 on the same day
- **THEN** exactly one automatic snapshot exists for that day

#### Scenario: Retention

- **WHEN** a 15th daily automatic snapshot is written
- **THEN** the oldest automatic snapshot is deleted and safety snapshots are untouched

#### Scenario: A new store is included without registration

- **WHEN** a store file `FoodLogCore/Supplements/plan.json` exists that no backup code names
- **THEN** the next snapshot contains it at the same relative path

#### Scenario: Snapshot failure is visible

- **WHEN** writing the snapshot fails because the disk is full
- **THEN** an error is logged in Diagnostics under `DataSafety` and Settings → Data shows that the last automatic backup failed

### Requirement: Backups never contain secrets or device delivery state

The system SHALL exclude from every snapshot and export the Garmin tokens,
any file or preference key whose name looks like a credential, any file whose
content contains an OAuth or token key, the outboxes, the diagnostics log,
the Garmin health cache, the offline food index and the Siri donation ledger.

#### Scenario: Token scan

- **WHEN** the data directory contains `GarminKit/oauth-token.json`, a store-like file containing `"oauth_token_secret"`, and a preference key `garmin.oauthToken`
- **THEN** neither the snapshot nor the exported file contains the strings `oauth_token`, `oauth_token_secret` or the planted secret value

#### Scenario: Outbox excluded

- **WHEN** `GarminKit/outbox-app.json` holds one pending entry and a snapshot is taken
- **THEN** the snapshot has no outbox file

### Requirement: Restore is staged and applied before any store loads

The system SHALL restore only by staging the chosen backup and applying it at
the next app launch before any store is created. Before applying, it SHALL
write a safety snapshot of the current data; if that fails, nothing SHALL be
changed. Applying SHALL replace every included file and included preference
with the backup's, remove included files and keys that the backup does not
contain, and leave excluded files and keys (outboxes, diagnostics, offline
index, health cache, backup bookkeeping) exactly as they were.

#### Scenario: Restoring yesterday's snapshot

- **WHEN** the user restores yesterday's snapshot from Settings → Data and reopens the app
- **THEN** custom foods, meal presets, weight entries and progress are exactly as in yesterday's snapshot, a safety snapshot of the pre-restore data exists, and Settings → Data says the restore succeeded

#### Scenario: Queued entries survive a restore

- **WHEN** one food entry is queued for Garmin and the user restores a snapshot
- **THEN** after relaunch the entry is still queued and is delivered once

#### Scenario: Files not in the backup are removed

- **WHEN** the current data has `FoodLogCore/day-notes.json` and the restored backup has no day notes
- **THEN** after relaunch there are no day notes

#### Scenario: Cancel before relaunch

- **WHEN** the user stages a restore and taps "Cancel restore" before relaunching
- **THEN** the next launch changes nothing

### Requirement: All data can be exported to and imported from one file

The system SHALL export every included data file and preference as a single
`.json` backup file through the system file exporter (Files, iCloud Drive)
without any entitlement, SHALL record the export time, and SHALL import such a
file through the system file importer by checking its version, showing a
preview (backup date, app version, counts of food-log entries, custom foods,
meal presets, favourites, weigh-ins, drinks and day notes) and, on
confirmation, staging it as a restore.

#### Scenario: Move to a reinstalled app

- **WHEN** the user exports a backup to Files, deletes the app, reinstalls it, imports the file, confirms the preview and reopens the app
- **THEN** the food log, custom foods, meal presets, favourites, weight, water, day notes, preferences and progress are as they were at export, and Garmin asks for sign-in again

#### Scenario: Preview before anything changes

- **WHEN** the user picks a backup file with 12 custom foods and 40 weigh-ins
- **THEN** the preview shows 12 custom foods and 40 weigh-ins and no data has changed until she confirms

### Requirement: The user is reminded to export

The system SHALL show in Settings → Data when the last export was made and,
when it is more than 14 days old or there has never been one, a quiet
reminder in the Today banner area that can be dismissed for 14 days, in
both data modes.

#### Scenario: Reminder after two weeks

- **WHEN** the last export was 15 days ago and the reminder was not dismissed
- **THEN** the Today screen shows the backup reminder until the user exports or taps "Not now"

#### Scenario: Dismissed

- **WHEN** the user taps "Not now" on the reminder
- **THEN** it does not appear again for 14 days
