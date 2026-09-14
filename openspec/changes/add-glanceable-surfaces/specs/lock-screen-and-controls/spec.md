## Purpose

Provide the fastest possible logging action — a Control placeable in Control Center, on the Lock Screen, and on the Action Button — that works while the device is locked, plus a read-only Lock Screen ring, since interactive Lock Screen widgets cannot themselves perform an action while locked.

## ADDED Requirements

### Requirement: A logging Control runs without requiring the device to be unlocked

The system SHALL provide at least one Control whose action intent is authorized to run while the device is locked, so that logging a quick-pick food requires no more than reaching the Control and activating it.

#### Scenario: Activating a Control while the device is locked

- **WHEN** the user activates a logging Control from Control Center, the Lock Screen, or the Action Button while the device is locked
- **THEN** the corresponding food entry is logged
- **AND** no device authentication step is required to complete it

### Requirement: Lock Screen accessory widgets are read-only

Because Lock Screen accessory widget buttons do not perform actions while the device is locked, the system SHALL NOT present interactive controls in a Lock Screen accessory widget. Any Lock Screen accessory widget SHALL be limited to displaying information.

#### Scenario: Lock Screen accessory widget is viewed while locked

- **WHEN** a Lock Screen accessory widget is visible on a locked device
- **THEN** it displays the current calorie total
- **AND** it presents no tappable action that depends on the device being locked to matter

### Requirement: A logging Control's quick-pick set reflects local usage ranking

The set of foods offered as Controls SHALL be drawn from the food catalog's locally-ranked quick-pick list, so that the fastest surface logs the foods most likely to be logged.

#### Scenario: Quick-pick ranking changes

- **WHEN** the local usage ranking changes which foods are most frequently logged
- **THEN** the Controls offered reflect the updated ranking

### Requirement: Barcode scanning from a Control opens the app rather than scanning inline

Because a camera capture session cannot run inside a widget or Control extension, a barcode-scan Control SHALL open the containing app directly into the scanning flow rather than attempting to scan within the extension.

#### Scenario: Activating the scan Control

- **WHEN** the user activates the barcode-scan Control
- **THEN** the app opens directly to the barcode scanner
- **AND** no scanning occurs within the Control's own process
