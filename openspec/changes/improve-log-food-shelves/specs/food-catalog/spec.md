## ADDED Requirements

### Requirement: The Log Food screen offers swipeable shelves in a fixed order

When the search field is empty, the system SHALL show horizontal card shelves
in this order: Quick pick, Favorites, Usual for <meal>, Meals, Recent. The
system SHALL hide any shelf that has no items.

#### Scenario: Meals shown as cards
- **WHEN** the user has two meal presets and opens Log Food
- **THEN** both presets appear as cards in the Meals shelf, after Usual for <meal>
- **AND** tapping a card opens the preset's confirm screen

#### Scenario: Empty shelf hidden
- **WHEN** the user has no favorites
- **THEN** no Favorites shelf is shown and the next shelf moves up

### Requirement: A per-meal shelf surfaces the foods usually eaten at that meal

The system SHALL show a "Usual for <meal>" shelf. It lists the foods most
often logged for the meal currently being logged, ranked by frequency with a
recency decay. The shelf SHALL only appear once that meal has at least 3
logged events.

#### Scenario: Breakfast staples at breakfast
- **WHEN** the user opens Log Food from the Breakfast card, and oatmeal was logged at breakfast 8 times and at dinner 0 times
- **THEN** the shelf is titled "Usual for breakfast" and oatmeal appears in it

#### Scenario: Dinner shelf differs
- **WHEN** the user opens Log Food from the Dinner card
- **THEN** oatmeal does not appear in "Usual for dinner" unless it was logged at dinner

### Requirement: A Recent shelf lists the last foods logged

The system SHALL show a Recent shelf with the last 10 distinct foods logged,
newest first.

#### Scenario: Just-logged food is first
- **WHEN** the user logs a banana and reopens Log Food
- **THEN** the banana is the first card in Recent
