## Purpose

Turn a chosen food and serving into a confirmed, durable log entry — with a meal type and date — and hand it to the sync layer, completing the flow every fast-entry surface in this project ultimately triggers.

## ADDED Requirements

### Requirement: Confirming an entry commits it without waiting on the network

The system SHALL commit a food entry (food, serving, quantity, meal type, date) to durable local storage as soon as the user confirms it, and MUST NOT require network connectivity to complete the confirmation.

#### Scenario: Confirming an entry with no connectivity

- **WHEN** the user confirms a food entry while offline
- **THEN** the entry is committed locally and the confirm screen completes immediately

#### Scenario: Confirming an entry with connectivity

- **WHEN** the user confirms a food entry while online
- **THEN** the confirm screen completes without waiting for the Garmin delivery to finish

### Requirement: A confirmed entry is handed to sync in the same action that commits it

The system SHALL enqueue a confirmed entry for delivery, via the sync capability's per-process outbox, as part of the same action that commits the entry locally, so that no confirmed entry can exist without a corresponding delivery obligation.

#### Scenario: An entry is confirmed

- **WHEN** a food entry is confirmed
- **THEN** it exists simultaneously in local storage and in the delivery queue

### Requirement: A confirmed entry updates local usage ranking

Confirming an entry SHALL update the food catalog's local usage record for that food and serving, so that future quick-pick ranking reflects the newly logged entry.

#### Scenario: Logging a food updates its ranking

- **WHEN** a food and serving are logged
- **THEN** the local usage record for that food and serving is updated with the current timestamp

### Requirement: Meal type and date default sensibly but remain editable

The system SHALL default the meal type based on time of day and the date to today, and SHALL allow the user to change either before confirming, so that a late log for an earlier meal or an earlier day is possible without contorting the flow.

#### Scenario: Logging at a typical mealtime

- **WHEN** the user logs a food during a typical breakfast, lunch or dinner window
- **THEN** the corresponding meal type is pre-selected

#### Scenario: Logging a meal after the fact

- **WHEN** the user changes the date or meal type before confirming
- **THEN** the entry is recorded against the selected date and meal type, not the current moment
