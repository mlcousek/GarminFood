## ADDED Requirements

### Requirement: A weigh-in whose save failed never syncs

The system SHALL save a weigh-in locally before queueing it for Garmin, and SHALL NOT leave anything queued when the local save fails.

#### Scenario: Local save fails
- **WHEN** the user saves a weigh-in and the local write fails
- **THEN** the user sees the failure and nothing is ever sent to Garmin for it
