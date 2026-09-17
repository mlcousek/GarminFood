## Purpose

Give the user a profile and a place to see and control how the app is connected and how it behaves.

## ADDED Requirements

### Requirement: The profile shows who the user is and what they've achieved

The system SHALL show the Garmin display name and profile photo from `GET /userprofile-service/socialProfile` (200, last verified 2026-09-16), alongside local stats: current level, current and longest streak, total logged entries, days logged and challenges completed. If the Garmin profile cannot be loaded, the local stats SHALL still be shown.

#### Scenario: Garmin profile unavailable

- **WHEN** the profile request fails
- **THEN** the screen shows the local stats and a neutral placeholder instead of the name and photo

### Requirement: Settings show the Garmin connection and allow signing out and in

The system SHALL show whether the app is connected to Garmin. It SHALL let the user sign out after confirming, which removes the stored Garmin credentials but keeps queued entries, and SHALL let the user sign in again.

#### Scenario: Signing out

- **WHEN** the user confirms sign-out
- **THEN** the connection shows as signed out, the sign-in banner appears, and queued entries remain queued

### Requirement: Settings show Garmin's nutrition goals read-only

The system SHALL show the calorie goal and the macro goals from `GET /nutrition-service/settings/{date}` (200, last verified 2026-09-16), plus the meal windows, and SHALL state that these are changed in Garmin Connect.

#### Scenario: Goals loaded

- **WHEN** the settings route returns a calorie goal of 2400
- **THEN** the nutrition section shows 2400 kcal and offers no way to edit it

### Requirement: The sync queue can be inspected and managed

The system SHALL list entries not yet accepted by Garmin, with their meal, date, state and last error. It SHALL allow retrying a failed entry, deleting any queued entry after confirming, and syncing now.

#### Scenario: Retrying a failed entry

- **WHEN** the user retries an entry marked failed
- **THEN** it becomes queued again, and the next sync attempts it

### Requirement: Preferences persist across launches

The system SHALL persist these preferences across launches: haptic feedback, celebratory animations, using Garmin's meal windows for the default meal, and Czech-only search.

#### Scenario: Turning off haptics

- **WHEN** the user turns haptics off and relaunches the app
- **THEN** haptics are still off, and confirming an entry produces no haptic

### Requirement: Queued entries are delivered in the background

The system SHALL ask iOS for background refresh time while entries are waiting. When granted, it SHALL attempt delivery and then request the next refresh. Foreground delivery SHALL continue to work regardless.

#### Scenario: App backgrounded with a queued entry

- **WHEN** the app moves to the background with an undelivered entry
- **THEN** a background refresh is requested

### Requirement: About shows the version

The system SHALL show the app version and build.

#### Scenario: Opening About

- **WHEN** the user opens About
- **THEN** the version and build number are shown
