## ADDED Requirements

### Requirement: Picking an ingredient searches every food source

The system SHALL offer the same food sources when picking a meal-preset
ingredient as when logging a food: Garmin search results, Czech Open Food
Facts results, and the user's custom foods matched by name.

#### Scenario: Czech product found while building a meal

- **WHEN** the user adds an ingredient to a meal preset and searches for a Czech product that only Open Food Facts has
- **THEN** the Open Food Facts section is shown in the picker
- **AND** choosing that product, after the Garmin match is confirmed, adds the matched food to the meal instead of logging it

#### Scenario: Custom food found by typing while building a meal

- **WHEN** the user types part of a custom food's name in the ingredient picker
- **THEN** that custom food is listed and can be added to the meal

### Requirement: A tap in picker mode never logs a food

The system SHALL return the tapped food to the calling screen, and SHALL NOT
log it, whenever the catalog is open to pick an ingredient or a backing food.
This applies to quick-pick cards, favorites, custom foods and search results.

#### Scenario: Quick pick tapped while adding an ingredient

- **WHEN** the catalog is open to add a meal-preset ingredient and the user taps a Quick pick card
- **THEN** the food is added to the meal preset with that card's serving and quantity
- **AND** no food log entry is created
