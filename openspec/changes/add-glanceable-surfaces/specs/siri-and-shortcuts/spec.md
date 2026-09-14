## Purpose

Enable voice- and Spotlight-driven food logging through a small, well-chosen set of App Shortcuts, staying comfortably within Apple's platform limits rather than attempting exhaustive coverage.

## ADDED Requirements

### Requirement: The app exposes a small, fixed set of App Shortcuts

The system SHALL declare no more than 5 App Shortcuts, remaining well under Apple's compile-time limit of 10, and each phrase SHALL include the application-name token so it is voice-triggerable via Siri and discoverable in Spotlight.

#### Scenario: Invoking a shortcut by voice

- **WHEN** the user speaks a declared shortcut phrase including the app's name
- **THEN** the corresponding logging action is performed without opening the app first, where the action supports background execution

#### Scenario: Shortcut count stays within platform limits

- **WHEN** a new shortcut is proposed for addition
- **THEN** it is only added if the total remains at or below 5

### Requirement: A completed voice log is donated for future Siri and Spotlight suggestions

The system SHALL donate a completed logging action to the system's intent donation mechanism, so that Siri Suggestions and Spotlight results improve based on actual usage, and SHALL remove the donation if the corresponding entry is later deleted.

#### Scenario: A voice-logged entry is later deleted

- **WHEN** an entry that was logged via a Siri shortcut is deleted
- **THEN** its corresponding donation is also removed
