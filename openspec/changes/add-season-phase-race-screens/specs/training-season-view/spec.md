## ADDED Requirements

### Requirement: The Plan tab offers the season as a third view

The system SHALL offer, in the training experience's Plan tab, a Season
view next to Week and Month, remembered like them per install. It SHALL
show the season's title, period and goal, the season timeline, and the
season's phases and races as rows that open their screens. With no
season in the plan (or a season without a period) it SHALL show that no
season has been published instead of an empty timeline.

#### Scenario: Opening the season

- **WHEN** the owner selects Season on the Plan tab of a plan whose season runs from 2 September 2030 to 31 August 2031
- **THEN** the view shows the season's title, its period and goal, the timeline, and one row per phase and per race

#### Scenario: No season

- **WHEN** the plan file has `season: null`
- **THEN** the Season view shows "No season yet" and no timeline, and the Week and Month views are unchanged

### Requirement: The timeline places phases and races on one axis without hiding what isn't planned

The system SHALL draw every phase that has a period as a band and every
season race as a marker on one axis spanning the season's period, SHALL
mark today (the current training day), SHALL label each stretch of the
season that no phase covers as "No phase planned", SHALL put race labels
that would overlap on separate lanes without dropping any, and SHALL
clamp a phase or race lying outside the season to the edge and flag it
rather than omit it. The selected phase, a closed phase and a draft phase
SHALL be distinguishable without relying on colour alone.

#### Scenario: A stretch without a phase

- **WHEN** the season's last phase ends on 31 January 2031 and the season ends on 31 August 2031
- **THEN** the timeline shows a gap from 1 February to 31 August 2031 labelled "No phase planned"

#### Scenario: Two races close together

- **WHEN** a race on 21 September and one on 3 November fall within the width of one label
- **THEN** their labels are on different lanes and both are shown

#### Scenario: A race outside the season

- **WHEN** a race is dated before the season's first day
- **THEN** its marker sits at the start of the axis and is flagged as outside the season

### Requirement: Race rows say when and what each race is

The system SHALL list each season race with its name, date (marked when
approximate), priority (A, B or C, or hero), distance, and a countdown
from today that also covers races in the past, and SHALL say when no
phase covers a race.

#### Scenario: Past, next and far races

- **WHEN** today is 23 October 2030 and the season has a C race on 21 September 2030, a B race on 3 November 2030 and an approximately dated hero race on 21 June 2031 that no phase anchors
- **THEN** the rows read "32 days ago", "in 11 days" and "in about 241 days", the last is marked as the hero race and says "No phase covers this race yet", and the B race is highlighted as the next race

#### Scenario: Czech countdown

- **WHEN** the app's language is Czech and a race was 32 days ago
- **THEN** the row reads "před 32 dny"
