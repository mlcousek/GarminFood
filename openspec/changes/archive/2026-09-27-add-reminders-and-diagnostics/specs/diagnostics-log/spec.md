## Purpose

Make it possible to see what actually happened on a real device, given this project has no Mac and therefore no Console.app or attached debugger.

## ADDED Requirements

### Requirement: Network and delivery failures are recorded, not just shown generically

The system SHALL record, in a persistent local log, the real underlying error for every failed Garmin API request, every non-2xx Garmin API response, and every outbox delivery outcome -- in addition to whatever generic message is shown to the user.

#### Scenario: A Garmin API call fails

- **WHEN** a request to Garmin's API fails (network error or a non-2xx response)
- **THEN** an entry describing the failure is recorded in the diagnostics log

#### Scenario: An outbox drain completes

- **WHEN** a drain of queued entries finishes, having delivered or given up on at least one entry
- **THEN** a summary of the outcome is recorded in the diagnostics log

### Requirement: The log is viewable and copyable entirely on-device

The system SHALL provide an in-app screen listing recorded diagnostics entries (newest first) and a way to copy all of them as plain text, requiring no tool beyond the app itself.

#### Scenario: Viewing the log

- **WHEN** the user opens the diagnostics screen
- **THEN** recorded entries are listed with their level, category, timestamp, and message

#### Scenario: Copying the log

- **WHEN** the user chooses to copy the log
- **THEN** every visible entry is placed on the system pasteboard as plain text

### Requirement: The log is bounded and user-clearable

The system SHALL cap the diagnostics log at a fixed number of entries, discarding the oldest first, and SHALL let the user clear it manually.

#### Scenario: The cap is reached

- **WHEN** a new entry is recorded and the log is already at its cap
- **THEN** the oldest entry is dropped before the new one is added

#### Scenario: Clearing the log

- **WHEN** the user chooses to clear the diagnostics log
- **THEN** no entries remain until new ones are recorded
