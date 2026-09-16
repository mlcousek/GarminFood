## Purpose

Search a second, legitimately-licensed food database (Open Food Facts) with genuine Czech product coverage, displayed clearly separate from Garmin's own catalog, without ever scraping or reproducing any proprietary Czech nutrition database.

## ADDED Requirements

### Requirement: Czech-database search results are drawn from Open Food Facts

The system SHALL search Open Food Facts's free-text search endpoint for a given term and SHALL NOT source this data from any proprietary third-party Czech nutrition database.

#### Scenario: Searching for a Czech product

- **WHEN** the user searches for a food by name
- **THEN** results from Open Food Facts are retrieved via its confirmed free-text search endpoint

#### Scenario: A Czech-specific filter is available

- **WHEN** the user searches with the Czech country filter enabled
- **THEN** only products tagged as available in the Czech Republic are returned

### Requirement: Czech-database results are visibly distinct from Garmin results

The system SHALL display Open Food Facts results in a section clearly separate from and labeled apart from Garmin's own search results, so the user always knows which database a given result came from.

#### Scenario: Both sources have results for the same search term

- **WHEN** a search term returns results from both Garmin and Open Food Facts
- **THEN** the two result sets are shown in visibly distinct, separately labeled sections, not merged into one list

### Requirement: Czech-database nutrition values are mapped to the app's existing food model

The system SHALL decode Open Food Facts's per-100g nutrition fields into the same `Food`/`Serving` shape used for Garmin results, so the rest of the logging flow treats a Czech-database food identically once selected.

#### Scenario: Decoding a real Open Food Facts response

- **WHEN** an Open Food Facts search result includes per-100g calorie, protein, carbohydrate, and fat values
- **THEN** they are mapped into the app's standard serving macro fields without loss
