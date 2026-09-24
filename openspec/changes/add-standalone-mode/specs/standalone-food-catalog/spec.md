## ADDED Requirements

### Requirement: Search and log foods without a Garmin food identity

In standalone mode the system SHALL search the user's own foods, the offline
Czech index and Open Food Facts (not Garmin), and SHALL let the user log any
result directly through the serving picker and confirm screen, without a
Garmin match. A result with no known calories SHALL NOT be loggable; other
missing nutrients SHALL be logged as unknown and shown as "some values
missing".

#### Scenario: Logging an Open Food Facts result

- **WHEN** a standalone user searches "tvaroh" and picks an Open Food Facts result with calories per 100 g
- **THEN** the serving picker and confirm screen open, and confirming logs it locally with no Garmin match screen

#### Scenario: Result without calories

- **WHEN** a standalone user picks a result that has no calorie value
- **THEN** it can't be confirmed, and the screen offers to create a custom food instead

### Requirement: Custom foods don't need a Garmin backing food in standalone mode

The system SHALL let a standalone user create and log a custom food from its
own name, serving and macros, without choosing a closest Garmin food, and
SHALL log it with its own macros. Existing custom foods that have a backing
food SHALL keep decoding and working unchanged. A custom food without a
backing food, seen in Garmin mode, SHALL ask for a Garmin match before it can
be logged to Garmin, and SHALL never be logged silently or dropped.

#### Scenario: Creating a custom food standalone

- **WHEN** a standalone user saves "Babiččiny buchty" with 280 kcal per piece and no backing food
- **THEN** it appears in search and logs 280 kcal per piece

#### Scenario: Old custom food after the update

- **WHEN** the app loads a custom-food file written before this change
- **THEN** every custom food keeps its backing food and logs exactly as before

### Requirement: Barcodes resolve without Garmin

In standalone mode a scanned barcode SHALL resolve from the offline Czech
index first, then (once its route is probed and recorded) from an online
Open Food Facts product lookup, and otherwise SHALL open the custom-food
editor with the barcode pre-filled.

#### Scenario: Czech product in the offline index

- **WHEN** a standalone user scans a Czech product that is in the offline index
- **THEN** its serving picker opens without any network request

#### Scenario: Unknown barcode

- **WHEN** the barcode is found nowhere
- **THEN** the custom-food editor opens with the barcode filled in

### Requirement: Meal presets, quick picks, Siri and Controls log through the current mode

The system SHALL route meal presets, quick picks, "Log again", Siri "log X"
and the quick-pick Controls through the same mode-aware logging, so in
standalone mode they commit locally and never report a Garmin sign-in
problem.

#### Scenario: Siri in standalone mode

- **WHEN** a standalone user asks Siri to log a food that is in her own foods
- **THEN** it is committed to the local log and Siri confirms without mentioning Garmin
