## Purpose

Provide a fast way to find a food to log — by search, barcode, or a locally-ranked quick-pick shelf — backed by Garmin's own food database so that anything found is guaranteed loggable back to Garmin, plus a custom-food path for items that database does not carry.

## ADDED Requirements

### Requirement: Food search is backed by Garmin's own database

The system SHALL search for foods via Garmin's `food/search` route (`GET /nutrition-service/food/search?searchExpression=<term>`, confirmed reachable 2026-09-14) rather than maintaining an independent food database, so that any food found is guaranteed to be a food Garmin recognises for logging.

#### Scenario: Searching for a common food

- **WHEN** the user searches for a food by name
- **THEN** results are retrieved from Garmin's food-search route
- **AND** each result includes its available serving options

#### Scenario: Searching in Czech

- **WHEN** the user searches using a Czech-language term
- **THEN** relevant results are returned, because Garmin's underlying database has non-US coverage

### Requirement: A quick-pick shelf is ranked from local usage, not from a fresh search

The system SHALL maintain a local record of previously logged foods and servings, and SHALL rank a "quick pick" list from that record by a combination of recency and frequency, so that the most likely food is available without typing or waiting on a search.

#### Scenario: A frequently logged food is picked again

- **WHEN** the user has logged the same food and serving multiple times recently
- **THEN** it appears near the top of the quick-pick list without a search being performed

#### Scenario: No usage history exists yet

- **WHEN** no food has ever been logged
- **THEN** the quick-pick list is empty rather than populated with unranked guesses

### Requirement: A food's serving choice is remembered as a default

Once a serving has been selected for a given food, the system SHALL remember that selection and pre-select it the next time the same food is chosen, while still allowing the user to change it.

#### Scenario: Re-logging a previously served food

- **WHEN** the user selects a food they have logged before
- **THEN** the previously chosen serving is pre-selected

#### Scenario: Changing the remembered serving

- **WHEN** the user selects a different serving than the remembered default
- **THEN** the new selection becomes the remembered default for that food going forward

### Requirement: Barcode scanning resolves a scanned product to a Garmin food

The system SHALL scan EAN-13, EAN-8, UPC-E, Code 128, ITF-14 and GS1 DataBar barcodes and attempt to resolve the scanned code to a Garmin food. Because UPC-A barcodes are reported by the scanning framework as EAN-13 with a leading zero, the system SHALL retry resolution with the leading zero stripped before treating the scan as unresolved.

#### Scenario: A UPC-A product barcode is scanned

- **WHEN** a UPC-A barcode is scanned and reported as a 13-digit code with a leading zero
- **THEN** the system also attempts resolution using the 12-digit code without the leading zero

#### Scenario: A scanned barcode cannot be resolved to any food

- **WHEN** no food can be found for a scanned barcode, with or without the leading zero
- **THEN** the user is offered custom-food creation rather than a dead end

### Requirement: Custom foods use the same shape a logged entry requires

The system SHALL allow creating a custom food with the same fields the food-log write contract requires, so that a custom food can be logged through the same flow as a Garmin catalog food.

#### Scenario: Creating a custom food

- **WHEN** the user creates a custom food with a name, serving unit and macro values
- **THEN** it can be selected and logged exactly as a searched food can

#### Scenario: Custom food creation is not possible via the Garmin API

- **WHEN** the write contract does not support creating a new food server-side
- **THEN** a custom food logs as the closest matching existing Garmin food with an adjusted quantity
- **AND** the discrepancy between the custom food and the food actually recorded in Garmin is shown to the user
