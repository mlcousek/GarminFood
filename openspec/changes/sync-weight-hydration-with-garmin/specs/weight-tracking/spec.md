## ADDED Requirements

### Requirement: Weigh-ins recorded in Garmin appear in the app

The system SHALL show Garmin's weigh-ins alongside local entries that have not
yet synced. Garmin's weigh-ins come from
`GET /weight-service/weight/dayview/{date}` (live-verified 2026-09-23), with
weight converted from grams to kg. An entry the app delivered SHALL NOT appear
twice.

#### Scenario: Scale weigh-in appears
- **WHEN** a weigh-in of 82.8 kg was recorded in Garmin Connect this morning and the user opens the app
- **THEN** the weight card and history show 82.8 kg for this morning

#### Scenario: App entry is not duplicated after sync
- **WHEN** the user logged 83.9 kg in the app and it was delivered to Garmin
- **THEN** history shows exactly one 83.9 kg entry at that time

#### Scenario: Offline
- **WHEN** Garmin cannot be reached
- **THEN** the last fetched weigh-ins and any pending local entries are still shown, with a quiet "couldn't refresh" note

### Requirement: Deleting a weigh-in deletes it in Garmin

The system SHALL delete a Garmin-sourced weigh-in in Garmin when the user
deletes it in the app. It uses `DELETE /weight-service/weight/{date}/byversion/{samplePk}`
(live-verified 2026-09-23) and delivers through the durable outbox, never
blocking the UI.

#### Scenario: Delete a synced weigh-in
- **WHEN** the user deletes a weigh-in that exists in Garmin
- **THEN** it disappears from the app at once and the delete is delivered to Garmin
- **AND** if delivery fails, the failure is visible in the sync queue

### Requirement: Weight goal with progress

The system SHALL show weight-goal progress on the weight card: start, current,
target, kg to go, and an ETA when the trend is moving toward the target. The
goal defaults to Garmin's `targetWeightGoal`/`startingWeight` from
`GET /nutrition-service/settings/{date}` (live-verified 2026-09-23). A local
override set in Settings SHALL replace it.

#### Scenario: Garmin goal shown
- **WHEN** Garmin's goal is 80.4 → 76.0 kg and the current weight is 83.9 kg
- **THEN** the card shows the target 76.0 kg and 7.9 kg to go

#### Scenario: Local override
- **WHEN** the user sets a weight-goal override of 78 kg in Settings
- **THEN** the card uses 78 kg as the target until the user resets to Garmin's goal
