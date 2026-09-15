## Purpose

Provide the fastest possible logging action -- a Control placeable in
Control Center, on the Lock Screen, and on the Action Button -- that works
while the device is locked, plus a static Lock Screen shortcut, since
interactive Lock Screen widgets cannot themselves perform an action while
locked and, separately, no widget/Control extension process on this account
can ever read this app's own data (see the requirement below).

## ADDED Requirements

### Requirement: A logging Control runs without requiring the device to be unlocked

The system SHALL provide at least one Control whose action intent is
authorized to run while the device is locked, so that logging a quick-pick
food requires no more than reaching the Control and activating it.

**REVISED 2026-09-14, genuinely unconfirmed rather than assumed**: whether
`authenticationPolicy = .alwaysAllowed` (permitting the intent to run while
locked) still avoids a Face ID/passcode prompt once the intent must ALSO
foreground the app (see the requirement immediately below) is untested --
showing app content on a locked device is normally exactly what triggers
the unlock prompt in the first place. This needs a real device test.

#### Scenario: Activating a Control while the device is locked

- **WHEN** the user activates a logging Control from Control Center, the
  Lock Screen, or the Action Button while the device is locked
- **THEN** the corresponding food entry is logged
- **AND** no *manual* authentication step is required to complete it,
  though a brief app-foreground transition is expected (see the next
  requirement) and whether that transition itself ever surfaces a system
  authentication prompt is the one item above flagged as unconfirmed

### Requirement: A logging Control's action runs inside the app's own process, not the extension's

**REVISED 2026-09-14.** `add-garmin-auth-and-sync` task 6.4 confirmed there
is no App Group and no Keychain Sharing on this account
(`errSecMissingEntitlement`/-34018, confirmed live). A Control's extension
process therefore has no Garmin credential and no access to the app's own
local data. The system SHALL run a logging Control's action intent inside
the app's own process (by foregrounding the app, briefly, as part of
activating the Control) rather than entirely within the widget/Control
extension's own background process.

#### Scenario: A logging Control is activated

- **WHEN** the user activates a logging Control
- **THEN** the app is briefly foregrounded so its action can run with
  access to the app's own stored Garmin credential and local data
- **AND** the corresponding food entry is looked up and logged only after
  that foregrounding has occurred, never before

### Requirement: A logging Control's label reflects a fixed rank, not a live food name

Because no widget/Control extension process can read this app's local usage
data (see the requirement above), a logging Control's static label (as
configured in Control Center/on the Lock Screen) SHALL identify its quick-pick
rank (e.g. "Quick Log #1") rather than the current food at that rank. The
actual food logged for that rank is resolved only once the Control's action
is running inside the app's own process.

#### Scenario: Quick-pick ranking changes

- **WHEN** the local usage ranking changes which food is most frequently
  logged
- **THEN** the food a given rank's Control logs changes accordingly the
  next time it is activated
- **AND** the Control's own displayed label is unaffected, since it was
  never showing a food name to begin with

### Requirement: Lock Screen accessory widgets are static and show no data

Because Lock Screen accessory widget buttons do not perform actions while
the device is locked, and because no widget extension process on this
account can read any live or local data (home-screen-widget spec's
equivalent requirement), the system SHALL NOT present interactive controls
in a Lock Screen accessory widget, and SHALL NOT display any calorie total
or other data-derived content there. A Lock Screen accessory widget is
limited to a static icon/label and a tap-to-open-the-app action.

#### Scenario: Lock Screen accessory widget is viewed while locked

- **WHEN** a Lock Screen accessory widget is visible on a locked device
- **THEN** it displays the same static content regardless of the user's
  actual logging history or Garmin account state
- **AND** it presents no tappable action that depends on the device being
  locked to matter (tapping it opens the app, which itself requires
  unlocking, the same as any app icon)

### Requirement: Barcode scanning from a Control opens the app rather than scanning inline

Because a camera capture session cannot run inside a widget or Control
extension, a barcode-scan Control SHALL open the containing app directly
into the scanning flow rather than attempting to scan within the extension.

#### Scenario: Activating the scan Control

- **WHEN** the user activates the barcode-scan Control
- **THEN** the app opens directly to the barcode scanner
- **AND** no scanning occurs within the Control's own process
