# challenges Specification

## Purpose
Offer short-horizon, achievable goals beyond the daily streak, drawn from a curated set of templates and evaluated entirely against the local log history.

## Requirements

### Requirement: One or two challenges are active at a time, drawn from a curated template set

The system SHALL maintain one or two active challenges at any time, selected from a fixed set of challenge templates, each with a locally-evaluable completion condition against the log history.

#### Scenario: No active challenge

- **WHEN** the app has no currently active challenge
- **THEN** a new one is selected from the template set and activated

### Requirement: Challenge progress is evaluated from the log history alone

The system SHALL evaluate a challenge's progress and completion purely from locally stored log entries and their existing metadata, without requiring a network call of its own.

#### Scenario: A goal-hitting challenge

- **WHEN** the active challenge requires hitting the day's nutrition goal on 4 of the last 5 nutrition-days
- **THEN** progress is computed directly from the local log history against goals already available locally

### Requirement: Completing a challenge is a rewarded, visible moment and triggers rotation

The system SHALL award XP on challenge completion, present a distinct completion moment (matching the levels capability's animated-moment requirement), and replace the completed challenge with a new one from the template set.

#### Scenario: A challenge's completion condition is met

- **WHEN** the active challenge's completion condition becomes true
- **THEN** the user sees a completion moment, XP is awarded, and a new challenge is activated

### Requirement: A challenge also rotates after a time window without completion

The system SHALL replace an active challenge that has not been completed within its defined time window, so a stale or unwinnable challenge does not persist indefinitely.

#### Scenario: A weekly challenge's window elapses uncompleted

- **WHEN** a challenge's defined time window elapses without its completion condition being met
- **THEN** it is replaced by a new challenge from the template set without awarding completion XP
