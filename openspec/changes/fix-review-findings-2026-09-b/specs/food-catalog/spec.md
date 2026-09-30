## ADDED Requirements

### Requirement: A custom food never sends Garmin an out-of-range amount

The system SHALL log a custom food backed by a Garmin food only when the amount sent to Garmin, the logged amount times the custom food's quantity multiplier, is finite, greater than zero and at most the maximum any logged amount may be. Otherwise it SHALL queue nothing and SHALL tell the user why before they confirm. This applies whatever the stored multiplier is, including one never checked by the editor.

#### Scenario: Multiplier times amount above the maximum
- **WHEN** a custom food with a multiplier of 100 is confirmed at 200 servings
- **THEN** nothing is queued, "Log it" is disabled, and the screen says the amount recorded in Garmin is out of range

#### Scenario: Stored multiplier of zero
- **WHEN** a custom food whose stored multiplier is 0 is logged from any entry point
- **THEN** nothing is queued for Garmin

#### Scenario: Meal preset with an out-of-range custom ingredient
- **WHEN** a meal preset's portions make one custom ingredient's amount in Garmin exceed the maximum
- **THEN** no ingredient of the preset is queued
