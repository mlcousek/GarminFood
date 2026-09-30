## ADDED Requirements

### Requirement: A custom food Garmin accepted is never created twice

The system SHALL treat any 2xx response to a custom-food create as a created food, whatever its body, and SHALL NOT offer another create from that screen afterwards. When the body can't be read, the user SHALL be told the food exists in Garmin and how to find it.

#### Scenario: 201 with an unexpected body
- **WHEN** Garmin answers the create with 201 and a body that isn't a food
- **THEN** the screen says the food was created but its details didn't come back, and the create button stays disabled

#### Scenario: Refused create
- **WHEN** Garmin answers with a non-2xx status
- **THEN** the error is shown and the user may try again
