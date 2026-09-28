## ADDED Requirements

### Requirement: Each install runs either the food-first or the training experience

The system SHALL run the food-first experience unless the training
experience is enabled for the install, and SHALL enable the training
experience only when the app reports an enabled vault connection or the
hidden Diagnostics preview toggle is on. Every standalone install without a
vault connection SHALL run the food-first experience.

#### Scenario: The fiancée's standalone install

- **WHEN** a standalone install with no vault connection launches the new build
- **THEN** it runs the food-first experience

#### Scenario: Preview toggle

- **WHEN** the owner turns on "Preview training shell (testing)" in Settings → Diagnostics
- **THEN** the app switches to the training experience at once, without a restart, and switches back when the toggle is turned off

### Requirement: The food-first experience is unchanged

In the food-first experience the system SHALL show exactly three tabs,
Today (`fork.knife`), Progress and Profile, in that order, with Today
titled "Food log", and SHALL render Today's cards from the same catalog,
order, visibility and variants as before this change.

#### Scenario: Nothing moves for a food-first user

- **WHEN** a food-first install that never edited its layout opens Today
- **THEN** the tabs, titles, icons and card order are identical to the previous build

#### Scenario: Layout editor lists no training cards

- **WHEN** a food-first user opens "Edit layout…" on Today
- **THEN** the editor lists exactly the cards it listed before this change

### Requirement: The training experience has four tabs with food logging kept on Today

In the training experience the system SHALL show four tabs, Today · Plan ·
Progress · Profile, each with its own navigation stack, and SHALL title
Today "Today". Today SHALL keep every food-logging entry point it has in the
food-first experience: the toolbar "Log a food" button, the "Log again"
quick picks, the "Log a meal" shelf, the meal cards and the weight and water
card, subject to the user's layout.

#### Scenario: Two-tap logging from training Today

- **WHEN** a training-experience user taps a "Log again" item on Today and then "Log it"
- **THEN** the food is committed locally and shown in its meal, exactly as in the food-first experience

#### Scenario: Plan tab before any plan exists

- **WHEN** the training experience is on and no plan data is available
- **THEN** the Plan tab shows an empty state explaining that the plan appears once a vault is connected, and no error

#### Scenario: Tabs keep their place

- **WHEN** the user pushes a meal detail on Today, switches to Plan, and back to Today
- **THEN** Today still shows the meal detail

### Requirement: The start tab and external routes respect the experience

The system SHALL offer Plan as a start tab only in the training experience,
and SHALL open Today when the stored start tab is not shown in the current
experience. A `garminfood://plan` link SHALL open the Plan tab in the
training experience and Today in the food-first experience. The log-food
link and the barcode Control SHALL open Today and the food catalog in both
experiences.

#### Scenario: Stored Plan start tab on a food-first install

- **WHEN** the stored start tab is `plan` and the install runs the food-first experience
- **THEN** the app opens on Today

#### Scenario: Barcode Control in the training experience

- **WHEN** the user fires the Scan Barcode Control while the Plan tab is showing
- **THEN** the app switches to Today, opens the catalog and presents the scanner

#### Scenario: Leaving the training experience while on Plan

- **WHEN** the Plan tab is selected and the preview toggle is turned off
- **THEN** the selected tab becomes Today
