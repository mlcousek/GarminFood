## ADDED Requirements

### Requirement: The app appears in the user's iOS language, English or Czech

The system SHALL declare English as its development language and Czech as a
supported localization in the app and the widget extension, and SHALL
display translated UI text in Czech whenever iOS resolves the app's language
to Czech (system language, or Settings › GarminFood › Language). For any
other language it SHALL fall back to English. The app SHALL NOT offer its
own in-app language override.

#### Scenario: Phone set to Czech

- **WHEN** the phone's language is Czech and the Today screen is opened
- **THEN** its title and the streak/level card read in Czech (e.g. "Úroveň 3")

#### Scenario: Per-app language pinned to English

- **WHEN** the phone's language is Czech but Settings › GarminFood › Language is set to English
- **THEN** the app shows English text

#### Scenario: Unsupported language

- **WHEN** the phone's language is German
- **THEN** the app shows English text

### Requirement: Package-provided display text is localized

Display text produced by FoodLogCore and Gamification (validation messages,
nutrient and meal names, notification titles and bodies, achievement,
challenge, level and rarity names) SHALL be resolved in the app's current
language from the package's own localized resources, falling back to
English when a translation is missing.

#### Scenario: Validation message in Czech

- **WHEN** the language is Czech and the owner enters a quantity above the maximum on the confirm screen
- **THEN** the error reads "Zadej množství větší než nula a nejvýše 10000."

#### Scenario: Rarity name in Czech

- **WHEN** the language is Czech and an achievement of rarity Legendary is shown
- **THEN** its rarity reads "Legendární"

### Requirement: Counted phrases use the language's plural rules

Any text that includes a count SHALL use the plural category of the current
language (Czech: one, few, many, other) for the whole phrase, including
verbs that agree with the count.

#### Scenario: Days left on a challenge in Czech

- **WHEN** the language is Czech and a challenge has 1, 3 and 5 days left
- **THEN** the texts read "Zbývá 1 den", "Zbývají 3 dny" and "Zbývá 5 dní"

#### Scenario: Days left in English

- **WHEN** the language is English and a challenge has 1 and 5 days left
- **THEN** the texts read "1 day left" and "5 days left"

### Requirement: Dates and numbers follow the current locale

Dates, weekday and month names, relative times and displayed decimal
numbers SHALL be formatted for the current locale. Numeric input SHALL
accept both "," and "." as the decimal separator.

#### Scenario: Decimal comma

- **WHEN** the language is Czech and a serving of 0.7 cups is shown
- **THEN** it reads "0,70"

#### Scenario: Weekday names

- **WHEN** the language is Czech and a date is shown with its weekday
- **THEN** the weekday is Czech (e.g. "pondělí")

### Requirement: Widgets, Controls, Siri phrases and permission prompts are localized

Widget and Control names, descriptions and labels, App Shortcut phrases and
titles, App Intent titles and errors, and Info.plist permission texts SHALL
be available in Czech.

#### Scenario: Widget gallery in Czech

- **WHEN** the language is Czech and the widget gallery is opened
- **THEN** the GarminFood "Log Food" widget is titled "Zapsat jídlo"

#### Scenario: Siri in Czech

- **WHEN** the language is Czech and the user asks Siri with the Czech phrase for scanning a barcode in GarminFood
- **THEN** the barcode scanner opens

### Requirement: Stored data never contains display text

Persisted stores SHALL store identifiers, not translated display text, so
that changing the language changes all text already on screen after the
next launch. Scheduled local notifications SHALL be re-planned when their
text differs from what the current language would produce.

#### Scenario: Language change after unlocking achievements

- **WHEN** achievements were unlocked while the app was in English and the language is then switched to Czech
- **THEN** the Achievements screen shows their Czech titles

#### Scenario: Pending reminder after language change

- **WHEN** a meal reminder was scheduled in English and the app is next opened in Czech
- **THEN** the pending reminder is replaced by its Czech text

### Requirement: CI rejects incomplete or malformed translations

The build pipeline SHALL fail when a localization file is invalid, when a
string has no Czech translation or is not marked translated, when a
translation's placeholders differ from its source's, or when a Czech plural
lacks the one, few or other form.

#### Scenario: Missing Czech string

- **WHEN** a pull request adds a catalog key without a Czech translation
- **THEN** the localization check fails and names the key

#### Scenario: Placeholder mismatch

- **WHEN** the Czech translation of "Level %lld" is "Úroveň %@"
- **THEN** the localization check fails and names the key
