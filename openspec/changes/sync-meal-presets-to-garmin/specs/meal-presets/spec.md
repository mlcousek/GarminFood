## Purpose

Let a saved meal preset also exist as a real, named meal in the user's own Garmin account, matching a feature Garmin's own official app already has (evidenced by this account's real `customMealId` data).

## ADDED Requirements

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
