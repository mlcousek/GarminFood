## ADDED Requirements

### Requirement: A screenless log earns the same rewards exactly once

The system SHALL award a food logged by a quick-pick Control or a Siri shortcut through the same gamification path as an in-app confirm (XP, lifetime stats, achievements, challenge progress and rewards, moments), exactly once per logged entry, including when the log is made before the app's own state has loaded.

#### Scenario: Control log while the app runs
- **WHEN** the user logs the #1 quick pick from a Control
- **THEN** the entry is committed and the log is awarded once, as if confirmed in the app

#### Scenario: Log before the app has loaded
- **WHEN** a Siri log commits an entry before the app has attached its gamification handler
- **THEN** the log is awarded once the handler attaches, and never a second time

#### Scenario: Failed commit
- **WHEN** the commit is refused (for example an invalid amount)
- **THEN** nothing is awarded
