## Purpose

Keep Garmin as the single system of record when logging a food that originated from the Czech (Open Food Facts) catalog: find and use a real Garmin-side equivalent when one exists, and only ever create a new Garmin food with explicit user confirmation when it doesn't.

## ADDED Requirements

### Requirement: A Czech-database food is matched against Garmin's catalog before logging

The system SHALL search Garmin's food catalog for a candidate equivalent of a chosen Czech-database food, using a normalized name comparison, before offering to log or create anything.

#### Scenario: A clear equivalent exists in Garmin

- **WHEN** a chosen Czech-database food's normalized name closely matches a Garmin search result for the same term, and their calorie values are not wildly inconsistent
- **THEN** the system identifies it as a match candidate

#### Scenario: No reasonable equivalent exists

- **WHEN** no Garmin search result's normalized name reasonably matches the chosen food, or a name-similar candidate's calories differ by more than the matching tolerance
- **THEN** the system reports no match found

### Requirement: A found match is shown to the user, never logged silently

The system SHALL present any candidate match to the user for confirmation before logging against it — the match is a suggestion, not an automatic resolution.

#### Scenario: Confirming a suggested match

- **WHEN** the system finds a candidate Garmin match for a Czech-database food
- **THEN** the user sees the matched Garmin food's name and can confirm or reject it before it is logged

### Requirement: Creating a new Garmin food requires explicit confirmation and is never automatic

When no Garmin match exists, the system SHALL offer to create a new food in Garmin with the Czech-database food's values, but SHALL NOT send that creation request without the user explicitly confirming the exact values to be sent.

#### Scenario: No match exists and the user confirms creation

- **WHEN** no Garmin match was found and the user reviews and confirms the values to create
- **THEN** the system sends the creation request to Garmin and, on success, logs the newly created food

#### Scenario: No match exists and the user does not confirm

- **WHEN** no Garmin match was found and the user has not explicitly confirmed creation
- **THEN** no creation request is sent to Garmin under any circumstance
