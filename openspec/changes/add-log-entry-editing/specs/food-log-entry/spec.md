## ADDED Requirements

### Requirement: A logged food's amount and meal can be edited

The system SHALL let the user change the quantity of a logged food, and move
it to another meal, from the entry's swipe or context actions. Garmin has no
edit route, so the change SHALL be delivered as a replacement: the corrected
entry is created with `PUT /nutrition-service/food/logs` (confirmed
2026-09-16), and only after that succeeds is the old entry deleted with
`DELETE /nutrition-service/food/logs/{date}` (live-tested by garmin_mcp; in use
by this app). The edited value SHALL show immediately, without waiting on the
network.

#### Scenario: Change the amount

- **WHEN** the user edits a logged "Rohlík, 1 piece" to 2 pieces
- **THEN** the entry shows 2 pieces immediately, marked pending
- **AND** after sync, Garmin has one Rohlík entry of 2 pieces and no 1-piece entry

#### Scenario: Delete step fails after the create succeeded

- **WHEN** the corrected entry was created but deleting the old one fails
- **THEN** the old entry's removal stays queued and is retried with backoff
- **AND** the pending removal is visible in the sync queue, so the food is never lost and the duplicate is never silent

#### Scenario: Move to another meal

- **WHEN** the user moves an entry from Lunch to Snacks
- **THEN** it appears under Snacks immediately and is removed from Lunch after sync

### Requirement: An entry can be duplicated

The system SHALL let the user duplicate a logged entry into the same meal
with the same food, serving and quantity.

#### Scenario: Second coffee

- **WHEN** the user duplicates a logged coffee
- **THEN** a second, identical coffee entry is logged to the same meal

### Requirement: A past meal can be copied

The system SHALL let the user copy the items of a meal from a previous day
into the same meal today. The user first sees a preview in which individual
items can be deselected.

#### Scenario: Same breakfast as yesterday

- **WHEN** the user chooses "Copy from… → Yesterday's breakfast" and confirms all 3 items
- **THEN** those 3 foods are logged to today's breakfast with their original servings and quantities

#### Scenario: Quick-add item cannot be copied

- **WHEN** yesterday's breakfast contains a calories-only quick-add entry
- **THEN** the preview marks it as not copyable and copies the rest
