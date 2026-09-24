## ADDED Requirements

### Requirement: Seasonal events run only inside their yearly date window

The system SHALL provide twelve Czech seasonal and holiday food events
(Masopust, Velikonoce, the owner's name day, strawberry season, grill
season, mushroom season, Svatý Martin, Mikuláš, Adventní cukroví, Štědrý
den, Silvestr, Nový rok), each with a date window computed for the current
year by logged date. Easter-relative windows SHALL be computed with the
Gregorian computus. An event SHALL be shown as upcoming from 3 days before
its window, as active inside its window, and SHALL NOT be completable
outside its window.

#### Scenario: Easter 2027

- **WHEN** the year is 2027
- **THEN** Easter Sunday is 28 March 2027, the Velikonoce window is 25–29 March 2027, and the Masopust window is 4–9 February 2027

#### Scenario: Goose outside the window

- **WHEN** the owner logs "Pečená husa" on 20 November
- **THEN** the Svatý Martin event does not progress

#### Scenario: Teaser

- **WHEN** today is 5 November
- **THEN** the Svatý Martin event is shown as starting in 3 days

### Requirement: Event quests are matched by seasonal food tags

The system SHALL complete an event when all its required quests are
satisfied by entries logged inside the window, and SHALL evaluate each
optional bonus quest independently. On Štědrý den, the required quest SHALL
accept potato salad together with either carp, any fish, or schnitzel.

#### Scenario: Christmas Eve with schnitzel

- **WHEN** on 24 December the owner logs "Bramborový salát" and "Vepřový řízek"
- **THEN** the Štědrý den event is completed

#### Scenario: Christmas Eve incomplete

- **WHEN** on 24 December the owner logs only "Bramborový salát"
- **THEN** the Štědrý den event is not completed

#### Scenario: Capers are not carp

- **WHEN** on 24 December the owner logs "Kapary" and "Bramborový salát"
- **THEN** the Štědrý den event is not completed

#### Scenario: Lentils for luck

- **WHEN** the owner logs "Čočková polévka" with logged date 1 January
- **THEN** the Nový rok event is completed

### Requirement: The owner's name day is derived from the Garmin profile

The system SHALL take the owner's first name from the first word of the
Garmin profile full name, look it up in a bundled Czech civil name-day
calendar ignoring case and diacritics, and SHALL run a name-day event on that
date whose required quest is logging any entry that day. When the first name
is unknown or not in the calendar, the name-day event SHALL be absent.

#### Scenario: Jiří

- **WHEN** the Garmin profile full name is "Jiří Mlčoušek"
- **THEN** the name-day event runs on 24 April and is titled with "Jiří"

#### Scenario: Name without diacritics

- **WHEN** the first name is "Jiri"
- **THEN** the name day resolves to 24 April

#### Scenario: Unknown name

- **WHEN** the first name is not in the name-day calendar
- **THEN** no name-day event is shown and collector badges do not require it

### Requirement: Completing an event grants a limited-edition badge and yearly XP

The system SHALL, when an event is completed, award 50 XP once for that
event and year, unlock that event's limited-edition badge if not already
unlocked, record the year, and show a celebration moment. Each bonus quest
SHALL award 25 XP once per event and year. Completing the same event in a
later year SHALL award the XP again and add the year to the badge without
unlocking it a second time.

#### Scenario: Second year

- **WHEN** the owner completes Svatý Martin in 2026 and again in 2027
- **THEN** 50 XP is awarded in each year, the badge is unlocked once, and it lists 2026 and 2027

#### Scenario: Collector

- **WHEN** the owner has completed 4 different events
- **THEN** the "collector-4" badge unlocks
