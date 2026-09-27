## ADDED Requirements

### Requirement: The PC bridge is off by default and set up once with a folder picker

The system SHALL provide a Settings → Data → "PC bridge" switch that is off
on a new or upgraded install. Turning it on SHALL ask the user to choose one
folder with the system document picker, SHALL remember the folder across
launches without asking again, and SHALL create `inbox/`, `results/`,
`archive/` and `state.json` inside it. While the bridge is off, the system
SHALL NOT read, write or list that folder.

#### Scenario: Fresh install

- **WHEN** the app is installed or updated and Settings → Data is opened
- **THEN** the PC bridge switch is off and no file exists in any bridge folder

#### Scenario: Folder remembered across relaunch and AltStore re-sign

- **WHEN** the user picks a folder, the app is force-quit, and AltStore re-signs the app in place a week later
- **THEN** on next launch the bridge reads that same folder without showing the picker again

#### Scenario: Folder access lost

- **WHEN** the remembered folder can no longer be opened (bookmark stale, folder deleted or moved)
- **THEN** the Data screen and the Today screen show a "PC bridge needs its folder again" notice with a button that opens the picker, and a `bridge` error is written to the diagnostics log

### Requirement: Commands are applied only through the coordinators and stores the UI uses

The system SHALL apply each command file found in `inbox/` by calling the
same FoodLogCore coordinator or store method that the equivalent UI action
calls, with the same validation. A command SHALL NOT write a store file
directly, and SHALL NOT be able to read or change Garmin credentials, sign
in or out, change the data mode, restore a backup, or delete the app's data.

#### Scenario: Logging food through the bridge earns XP like a tap

- **WHEN** a valid `food.log` command for 150 g of a catalog food at LUNCH today is applied
- **THEN** one entry is committed to the food outbox, usage history records it, and the streak and XP update exactly as if the user had confirmed the same food in the app

#### Scenario: Invalid quantity is refused like in the UI

- **WHEN** a `food.log` command carries a quantity outside the app's valid range
- **THEN** nothing is enqueued and the result file has status `rejected` with reason `quantity_out_of_range`

#### Scenario: Forbidden command kind

- **WHEN** a command file has kind `auth.signOut` or any kind not in the protocol's allow-list
- **THEN** it is not applied, its result has status `rejected` with reason `unknown_kind`, and the command file is moved to `archive/`

### Requirement: Every command is applied at most once

The system SHALL identify each command by a client-generated `commandId`
(UUID) and SHALL keep a local ledger of applied command ids for at least
90 days. A command whose id is already in the ledger SHALL NOT be applied
again; its original result SHALL be written again instead.

#### Scenario: Same file synced twice

- **WHEN** iCloud delivers the same `food.log` command file twice, or the app is killed after applying it but before archiving it
- **THEN** exactly one food entry exists for that command and both result writes carry the same `appliedAt`

### Requirement: Commands apply in order and only while the app runs

The system SHALL apply pending commands when the app launches, when it
returns to the foreground, and when the user taps "Check now" in the bridge
status view, in ascending `createdAt` order, and SHALL NOT block the UI
while doing so. A command whose `notAfter` time has passed SHALL be
rejected with reason `expired` instead of applied.

#### Scenario: Two commands that depend on each other

- **WHEN** `inbox/` holds a `supplement.addProduct` created at 10:00 and a `supplement.tick` for that product created at 10:01
- **THEN** the product is created first and the tick is recorded against it

#### Scenario: Expired command

- **WHEN** a `food.log` command with `notAfter` two hours ago is found
- **THEN** it is not applied, and its result says `rejected` with reason `expired`

### Requirement: Each command gets a result file the PC can read

The system SHALL write, for every command it reads, a result file
`results/<commandId>.json` with status `applied`, `rejected` or `failed`,
a machine-readable reason, a human message in English, the ids of anything
created (for example the new product id or outbox entry id), and the time
it was applied. It SHALL then move the command file to `archive/`.

#### Scenario: Applied command

- **WHEN** a `preset.create` command is applied
- **THEN** `results/<commandId>.json` has status `applied` and names the new preset's id, and the command file is in `archive/`

#### Scenario: Store cannot be written

- **WHEN** a store refuses a write because the device is locked or the file is quarantined
- **THEN** the command stays in `inbox/` for the next run, no result with status `applied` is written, and a `bridge` warning is added to the diagnostics log

### Requirement: The app publishes a read-only snapshot of its local state

The system SHALL write `state.json` into the bridge folder after applying
commands and at most every 5 minutes while the app is in the foreground.
The snapshot SHALL carry a `protocolVersion`, `generatedAt`, the app
version, the data mode, and the local data the PC cannot read from Garmin
(custom foods, meal presets, favourites, day notes, fasting state and
history, local goals, supplement products, schedules, limits, stock and the
last 90 days of intake, reminder settings, streak, freezes, level and XP,
active challenges, bingo, boss, journeys, records, collections,
achievements, appearance and layout, the bridge ledger's last 200 results,
and outbox entries not yet delivered). It SHALL NOT contain Garmin tokens,
OAuth values, or the diagnostics log.

#### Scenario: Snapshot holds no secrets

- **WHEN** the snapshot is generated from a test fixture that has Garmin tokens stored
- **THEN** a scan of `state.json` finds none of the token key names or values used by the backup secret-scan test

#### Scenario: Snapshot written atomically

- **WHEN** the app is suspended while writing the snapshot
- **THEN** the previous complete `state.json` is still in place and no partial file is named `state.json`

### Requirement: Bridge problems are visible to the user

The system SHALL show, in a bridge status view reachable from Settings →
Data, the time of the last run, the last snapshot time, and the last 50
results with their status. Any `rejected` or `failed` result, and any
folder-access error, SHALL also be written to the diagnostics log under
category `bridge`, and a failed or rejected command SHALL raise a
dismissible notice on the Today screen until it is viewed.

#### Scenario: A rejected command is not silent

- **WHEN** a `supplement.tick` names a product id that doesn't exist
- **THEN** the result is `rejected` with reason `not_found`, the diagnostics log has a `bridge` entry naming the command id, and Today shows the notice until the status view is opened

### Requirement: Commands carry a protocol version the app checks

The system SHALL refuse, with reason `unsupported_protocol`, any command
whose `protocolVersion` is newer than the version the running app supports,
and SHALL leave it in `inbox/` so a later app version can apply it.

#### Scenario: Newer PC server, older app

- **WHEN** a command with `protocolVersion` 3 arrives at an app that supports version 2
- **THEN** it is not applied, a result `rejected`/`unsupported_protocol` is written, and the command file stays in `inbox/`
