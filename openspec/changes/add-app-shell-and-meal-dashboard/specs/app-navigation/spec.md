## Purpose

Give the app a stable top-level structure so every screen is reachable, and make external entry points (widgets, the barcode Control, Siri) land somewhere useful.

## ADDED Requirements

### Requirement: The app opens into a three-tab shell

The system SHALL present Today, Progress and Profile as top-level tabs, with Today selected on a cold launch, and each tab SHALL keep its own navigation history when the user switches away and back.

#### Scenario: Cold launch

- **WHEN** the app is launched without an external route
- **THEN** the Today tab is selected

#### Scenario: Switching tabs keeps position

- **WHEN** the user opens a meal's detail on Today, switches to Progress, and switches back
- **THEN** the meal detail is still showing

### Requirement: The barcode Control opens the scanner from anywhere

When the app is opened by the barcode Control, the system SHALL select the Today tab and present the barcode scanner, whichever tab or screen was showing before.

#### Scenario: App was on the Profile tab

- **WHEN** the barcode Control is triggered while the app was last showing Profile
- **THEN** the Today tab is selected and the scanner is presented

#### Scenario: The route is consumed once

- **WHEN** the scanner opened by the Control is dismissed
- **THEN** it does not reappear on the next foreground

### Requirement: Widget links open Today

The system SHALL handle `garminfood://open` by selecting the Today tab for the current day.

#### Scenario: Tapping the home-screen widget

- **WHEN** the app is opened through `garminfood://open`
- **THEN** the Today tab shows the current day
