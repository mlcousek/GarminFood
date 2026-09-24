## ADDED Requirements

### Requirement: All local data can be exported

The system SHALL export, in both modes, a versioned JSON backup of every
local store (local food log, goals, custom foods, presets, favourites, usage
history, serving defaults, food cache, weight, water, day notes, every
gamification store and non-device preferences) plus a CSV of the food log,
and SHALL share them through the system share sheet. The backup SHALL NOT
contain Garmin tokens, the Garmin health cache, outboxes, the offline index
or the diagnostics log.

#### Scenario: Backing up

- **WHEN** a standalone user taps "Back up now"
- **THEN** the share sheet offers a .json backup and a food-log.csv that opens in a spreadsheet with one row per logged food

#### Scenario: No secrets in the backup

- **WHEN** a Garmin-connected user exports a backup
- **THEN** the file contains no OAuth token or secret

### Requirement: A backup can be restored safely

The system SHALL import a backup only after checking its schema and version
(refusing newer versions with an "update the app" message), SHALL show a
preview of what it contains, SHALL write an automatic safety backup of the
current data first, and SHALL then replace every store in the backup and
reload it. Restore SHALL replace, not merge.

#### Scenario: Restoring onto a new phone

- **WHEN** a user restores a backup on a fresh standalone install and confirms the preview
- **THEN** her food log, goals, custom foods, weight, water and progress appear as they were in the backup

#### Scenario: Backup from a newer app version

- **WHEN** a user picks a backup whose version is newer than the app supports
- **THEN** nothing is changed and the app asks her to update first

### Requirement: Standalone users are reminded to back up

In standalone mode the system SHALL show when the last backup was made in
Settings and, after 14 days without a backup, a quiet reminder card on the
Today screen, because there is no cloud copy of standalone data.

#### Scenario: Reminder after two weeks

- **WHEN** a standalone user's last backup is 15 days old
- **THEN** a reminder card appears on the Today screen until she backs up or dismisses it for another 14 days
