## ADDED Requirements

### Requirement: A food can be marked as a local favorite for fast re-access

The system SHALL let the user mark or unmark any food shown in the primary
logging flow (search results, the quick-pick shelf, custom foods) as a
favorite, storing that choice locally, so that a food useful for future
logging can be found again without a search -- independent of whether
Garmin's own account state agrees, and without waiting on any network call.

#### Scenario: Marking a search result as a favorite

- **WHEN** the user taps the favorite toggle on a food shown in search
  results
- **THEN** the food is marked favorite instantly, with no network wait
- **AND** it subsequently appears in the Favorites shelf

#### Scenario: Unmarking a favorite

- **WHEN** the user taps the favorite toggle on a food that is already
  favorited
- **THEN** the food is no longer marked favorite
- **AND** it no longer appears in the Favorites shelf

#### Scenario: Favoriting is not offered while picking a food for another screen

- **WHEN** the catalog is being used to pick a backing food for a custom
  food, or an ingredient for a meal preset
- **THEN** no favorite toggle is shown on any row

### Requirement: A Favorites shelf surfaces favorited foods for fast re-logging

The system SHALL show a horizontally-scrolling Favorites shelf in the
primary logging flow whenever at least one food is favorited, at the same
prominence as the existing quick-pick shelf, so that favoriting is
immediately useful rather than a bookmark that is never revisited.

#### Scenario: No favorites yet

- **WHEN** the user has never favorited a food
- **THEN** the Favorites shelf is not shown at all

#### Scenario: Selecting a favorited food

- **WHEN** the user taps a card in the Favorites shelf
- **THEN** the same food-selection flow used for a search result begins
  (the remembered serving is pre-selected if one exists, otherwise a
  serving picker is shown)

### Requirement: Favoriting has no dependency on a Garmin write route

The system SHALL implement favoriting entirely as local state, with no
network call of any kind, because no third-party Garmin Connect client
this project has evidence-checked has ever implemented a favorite-foods
method, and this project's own convention prohibits guessing at an
undocumented write contract.

#### Scenario: Favoriting while offline

- **WHEN** the device has no network connectivity
- **THEN** marking or unmarking a favorite still succeeds immediately
