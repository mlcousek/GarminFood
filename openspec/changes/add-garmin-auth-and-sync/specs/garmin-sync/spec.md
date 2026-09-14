## Purpose

Get a locally-recorded food entry into Garmin Connect reliably and exactly once, without ever making the user wait on the network, and without requiring shared storage between the app and its extensions.

## ADDED Requirements

### Requirement: A logged entry is durable before any network call is attempted

The system SHALL persist a food entry and its corresponding delivery record, in the process where the entry originated, in a single local transaction before returning control to the user interface. The user interface MUST NOT block on a network request to Garmin.

#### Scenario: User logs food while offline

- **WHEN** the user logs a food entry with no network connectivity
- **THEN** the entry is saved locally and shown in the UI immediately
- **AND** no error is shown for the absence of network connectivity at the moment of logging

#### Scenario: User logs food while online

- **WHEN** the user logs a food entry with network connectivity available
- **THEN** the entry is saved locally and shown in the UI before any Garmin request completes

### Requirement: Each process drains its own pending entries independently

Because the app has no shared storage between processes (free-tier decision, 2026-09-14 — see the `garmin-auth` capability), each process that can log an entry — the app, the widget extension, the Control — SHALL maintain and drain its own local queue of undelivered entries, without depending on any other process's queue.

#### Scenario: Entry logged from a Control while the app is not running

- **WHEN** the user logs food from a Control Center button and the app process is not running
- **THEN** the extension's own queue records the entry
- **AND** delivery is attempted by that extension's own background delivery mechanism, not by the app

#### Scenario: Entry logged from the app

- **WHEN** the user logs food from within the app
- **THEN** the app's own queue records the entry and drains it independently of any extension's queue

### Requirement: Delivery retries are bounded and rate-limit aware

The system SHALL back off exponentially with jitter between delivery attempts, SHALL honour a `Retry-After` response header when present, and SHALL stop attempting delivery entirely for the remainder of the current drain cycle when a 429 response is received. After a bounded number of failed attempts, an entry MUST be marked failed and surfaced for manual retry rather than retried indefinitely.

#### Scenario: Garmin rate-limits the client

- **WHEN** a delivery attempt receives HTTP 429
- **THEN** no further delivery attempts are made in that drain cycle
- **AND** the queued entry remains pending for the next cycle

#### Scenario: An entry repeatedly fails to deliver

- **WHEN** a queued entry has failed delivery a bounded number of times
- **THEN** it is marked failed rather than retried again automatically
- **AND** it is presented to the user for manual retry or deletion

### Requirement: Delivered entries are reconciled against Garmin, not against local state

After a successful delivery attempt, the system SHALL re-read the corresponding day's log from Garmin and match it against what was intended to be sent, identified by date, meal type, food identifier, serving identifier and quantity. Reconciliation SHALL treat Garmin as authoritative over any process's local records.

#### Scenario: A retried delivery created a duplicate

- **WHEN** reconciliation finds two matching entries in Garmin for one locally-queued entry
- **THEN** one of the duplicates is deleted
- **AND** the duplicate resolution is recorded

#### Scenario: A successful response was not actually persisted

- **WHEN** a delivery attempt received a success response but reconciliation finds no matching entry in Garmin
- **THEN** the entry is re-queued for delivery
- **AND** the discrepancy is recorded loudly, not silently retried without a trace

### Requirement: Displayed totals are always read fresh from Garmin

Any surface showing a daily calorie or macro total (the app, a Home Screen widget, a Control's status text) SHALL read that total from Garmin's daily summary rather than from a locally-aggregated value, subject to a short cache to respect platform refresh budgets. A locally-pending entry MAY be shown as a provisional addition on top of the last known Garmin total, but MUST be visually distinguishable from confirmed data.

#### Scenario: Entry has been delivered and confirmed

- **WHEN** a food entry has been successfully delivered and reconciled
- **THEN** the displayed total reflects Garmin's own daily summary value

#### Scenario: Entry is still pending delivery

- **WHEN** a food entry is queued but not yet confirmed delivered
- **THEN** it may be shown added to the last known total
- **AND** it is visually marked as pending rather than confirmed
