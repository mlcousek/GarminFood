## ADDED Requirements

### Requirement: The daily water total comes from Garmin

The system SHALL show the day's water total as Garmin's `valueInML` plus local
drinks not yet delivered. Garmin's total comes from
`GET /usersummary-service/usersummary/hydration/daily/{date}`
(live-verified 2026-09-23). Water logged on the watch or in Garmin Connect
SHALL therefore count.

#### Scenario: Water logged in Garmin Connect counts
- **WHEN** Garmin reports 1500 ml for today and the user logged nothing in the app
- **THEN** the water card shows 1500 ml

#### Scenario: Pending local drink counts once
- **WHEN** Garmin reports 1500 ml and a 250 ml drink logged in the app has not been delivered yet
- **THEN** the card shows 1750 ml
- **AND** after the drink is delivered and Garmin reports 1750 ml, the card still shows 1750 ml

### Requirement: Removing a drink corrects Garmin's total

The system SHALL correct Garmin's total when the user removes a delivered
drink. It sends a negative delta through the durable hydration outbox, and
cancels the drink locally if it was never delivered.

#### Scenario: Remove a delivered drink
- **WHEN** the user removes a 250 ml drink that was already delivered
- **THEN** a −250 ml delta is queued and the shown total drops by 250 ml at once

### Requirement: Water goal defaults to Garmin's

The system SHALL use Garmin's `goalInML` as the water goal unless the user sets
a local override in Settings.

#### Scenario: Garmin auto goal
- **WHEN** Garmin's goal for today is 2800 ml and no override is set
- **THEN** the water card's goal is 2800 ml
