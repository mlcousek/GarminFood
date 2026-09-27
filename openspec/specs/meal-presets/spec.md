# meal-presets Specification

## Purpose
Let the user save a named, fixed group of ingredients once and log the whole group in one action, instead of repeating the search-and-confirm flow for every ingredient every time the same meal is eaten again.

## Requirements

### Requirement: A meal preset is a named group of ingredients

The system SHALL let the user create a named meal preset containing one or more ingredients, where each ingredient is a real catalog food, an Open-Food-Facts-matched food, or one of the user's own custom foods, each with its own quantity.

#### Scenario: Creating a preset

- **WHEN** the user names a new meal and adds two or more ingredients, each with a quantity
- **THEN** the preset is saved and appears in the user's list of meals

#### Scenario: A preset cannot be saved with zero ingredients

- **WHEN** the user tries to save a meal with no ingredients added
- **THEN** the save action is unavailable until at least one ingredient is added

### Requirement: Logging a preset commits every ingredient in one action, without waiting on the network

The system SHALL, on confirming a meal preset, durably enqueue one log entry per ingredient — sharing the same meal type, date, and logging timestamp — and SHALL NOT require network connectivity to complete that commit.

#### Scenario: Logging a preset with three ingredients

- **WHEN** the user confirms logging a saved meal preset with three ingredients
- **THEN** three separate entries are committed, one per ingredient, all recorded against the same meal type and date
- **AND** the confirmation completes without waiting for delivery to Garmin to finish

#### Scenario: Logging while offline

- **WHEN** the device has no network connectivity
- **THEN** confirming a meal preset still commits every ingredient locally, exactly as it would online

### Requirement: A custom-food ingredient logs through its existing backing-food fallback

The system SHALL log a preset ingredient that originated from a custom food using that custom food's existing backing-food mechanism, exactly as if it had been logged on its own outside a preset.

#### Scenario: A preset contains a custom food

- **WHEN** a meal preset includes an ingredient that is one of the user's custom foods
- **THEN** logging the preset records that ingredient against its custom food's backing Garmin food and serving, scaled by the custom food's own multiplier and the ingredient's preset quantity

### Requirement: The whole preset can be scaled by a portions multiplier at log time

The system SHALL let the user scale every ingredient's preset-defined quantity together by a single multiplier when logging, without altering the saved preset itself.

#### Scenario: Logging half a preset

- **WHEN** the user sets the portions value to 0.5 before confirming a meal preset
- **THEN** every ingredient's logged quantity is half of its preset-defined quantity
- **AND** the saved preset's own ingredient quantities are unchanged afterward

### Requirement: A saved preset can be edited or deleted

The system SHALL let the user edit an existing meal preset's name, ingredients, and ingredient quantities, and SHALL let the user delete a meal preset.

#### Scenario: Editing an existing preset's ingredient quantity

- **WHEN** the user opens a saved meal preset for editing and changes one ingredient's quantity
- **THEN** saving updates that preset in place, and future logs of it use the new quantity

#### Scenario: Deleting a preset

- **WHEN** the user deletes a saved meal preset
- **THEN** it no longer appears in the user's list of meals
- **AND** entries already logged from it before deletion are unaffected

### Requirement: A saved preset made entirely of real foods can be synced to Garmin

The system SHALL let the user explicitly trigger creating a Garmin meal from an already-saved preset, when every ingredient is a real catalog or matched food, and SHALL record the result locally without altering how the preset logs.

#### Scenario: Syncing an eligible preset

- **WHEN** the user confirms syncing a saved preset whose ingredients are all real catalog/matched foods
- **THEN** a request to create a Garmin meal is sent, and on success the returned identifier and sync time are recorded against that preset

#### Scenario: Sync failure changes nothing about logging

- **WHEN** a sync attempt fails
- **THEN** the preset's own ability to be logged (as separate entries, per the existing behavior) is unaffected

### Requirement: A preset containing a custom-food ingredient cannot be synced

The system SHALL NOT offer to sync a preset to Garmin when it contains an ingredient backed by a custom food, and SHALL explain why.

#### Scenario: A mixed preset

- **WHEN** the user opens a saved preset that includes at least one custom-food ingredient
- **THEN** no sync action is offered, and a plain explanation is shown instead

### Requirement: Syncing to Garmin is never automatic

The system SHALL only attempt to create a Garmin meal from a preset in direct response to the user's own explicit confirmation, never as a side effect of saving, editing, or logging a preset.

#### Scenario: Saving a preset does not sync it

- **WHEN** the user saves a new or edited preset
- **THEN** no request to create a Garmin meal is sent unless the user separately confirms the sync action
