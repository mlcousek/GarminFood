## ADDED Requirements

### Requirement: The app is presented as "Jirka's Arc" in English and Czech

The system SHALL show the name "Jirka's Arc", with an ASCII apostrophe,
under the home-screen icon, in the widget gallery, in Siri and App Shortcut
phrases, in permission prompts and in every in-app string that names the
app, in both English and Czech. Strings that name Garmin, the service,
SHALL keep naming Garmin. The display name SHALL come from a single build
setting shared by the app and the widget, and SHALL NOT be overridden by a
Czech `InfoPlist` value.

#### Scenario: Home screen after the update

- **WHEN** the owner updates the app in place and looks at the home screen on a phone set to English
- **THEN** the icon is labelled "Jirka's Arc", untruncated

#### Scenario: Czech phone

- **WHEN** the same build runs on a phone set to Czech
- **THEN** the icon is labelled "Jirka's Arc" and onboarding's first page says "Vítejte v Jirka's Arc"

#### Scenario: A string about Garmin keeps Garmin

- **WHEN** a Garmin search fails because the sign-in expired
- **THEN** the message names Garmin as the service to sign in to and names Jirka's Arc as the app, and contains no "GarminFood"

#### Scenario: No leftover old name

- **WHEN** the localization check runs over the app, widget and package catalogs
- **THEN** no user-facing value in English or Czech contains "GarminFood"

### Requirement: Identifiers that hold data and integrations never change

The system SHALL keep the bundle identifiers `com.mlcousek.garminfood` and
`com.mlcousek.garminfood.widget`, the `garminfood` URL scheme, the Keychain
service names, the background task identifier, every store file path, the
backup manifest marker, the `GFT1.` theme-code prefix, the alternate icon
names and the layout card ids. Updating to this build in place SHALL keep
all local data and the Garmin sign-in.

#### Scenario: Update in place keeps everything

- **WHEN** the owner updates from the previous build through AltStore
- **THEN** the food log, custom foods, presets, weight, water, progress and supplements are all present, the Garmin sign-in still works without re-authenticating, and the sync queue is unchanged

#### Scenario: An old backup still imports

- **WHEN** the user imports a file named `GarminFood-backup-2026-09-20.json` made by the previous build
- **THEN** the import preview opens as before, and new exports are named `JirkasArc-backup-<date>.json`

#### Scenario: A theme code shared before the rename

- **WHEN** the user opens a `garminfood://theme?c=GFT1.…` link created before this change
- **THEN** the theme import preview opens as before

### Requirement: The icon is an arc mark in every theme's colours

The system SHALL ship a primary icon and the same 11 alternate icons, by the
same names, each showing the arc mark and the "by Jirka" line in white on
that icon's gradient. A user's chosen alternate icon SHALL still be chosen
after the update, now showing the new artwork. The icons SHALL be produced
by the committed generator, whose check mode SHALL report no difference
against the committed files.

#### Scenario: A chosen alternate survives the update

- **WHEN** the owner had selected the Forest icon before the update
- **THEN** after the update the home-screen icon is the Forest gradient with the arc mark, and Settings → Appearance still shows Forest as selected

#### Scenario: Generator and committed files agree

- **WHEN** `python tools/generate-app-icons.py --check` runs on the merged tree
- **THEN** it reports every icon up to date and exits 0

### Requirement: The in-app signature is the arc mark

The system SHALL render Today's pinned footer signature as the arc mark over
"by Jirka", drawn with theme tokens only, and SHALL expose it to VoiceOver as
"Jirka's Arc, by Jirka".

#### Scenario: Signature follows the theme

- **WHEN** the user switches from GF Teal to the Gold theme
- **THEN** the footer's arc mark redraws in the new theme's gradient without restarting the app

### Requirement: Every build carries a real version and build number

The system SHALL report marketing version 2.0 and a build number equal to
the CI workflow run that built it, identically in the app and the widget
extension, and SHALL show both in Settings → About and record them in every
backup manifest.

#### Scenario: About shows the CI build

- **WHEN** the owner installs the `.ipa` built by workflow run 412
- **THEN** Settings → About shows "2.0 (412)"

#### Scenario: Widget matches the app

- **WHEN** CI prints the archived app's and widget's version keys
- **THEN** both show `CFBundleShortVersionString` 2.0 and the same `CFBundleVersion`
