## MODIFIED Requirements

### Requirement: One or two challenges are active at a time, drawn from a curated template set

The system SHALL maintain one or two active challenges at any time, selected from a fixed set of at least 200 challenge templates spanning multiple difficulty tiers, each with a locally-evaluable completion condition against the log history.

#### Scenario: No active challenge

- **WHEN** the app has no currently active challenge
- **THEN** a new one is selected from the template set and activated

#### Scenario: Catalog depth supports long-term use

- **WHEN** the full challenge catalog is inspected
- **THEN** it contains at least 200 templates spanning at least four difficulty tiers, so a multi-year user does not exhaust it in the first month

### Requirement: Challenge progress is evaluated from the log history alone

The system SHALL evaluate a challenge's progress and completion purely from locally stored log entries and their existing metadata, without requiring a network call of its own.

#### Scenario: A goal-hitting challenge

- **WHEN** the active challenge requires hitting the day's nutrition goal on 4 of the last 5 nutrition-days
- **THEN** progress is computed directly from the local log history against goals already available locally

#### Scenario: A same-food streak challenge

- **WHEN** the active challenge requires logging the identical food on consecutive nutrition-days
- **THEN** progress is computed by comparing each day's logged food identifiers against the previous day's, using only locally stored log entries
