## ADDED Requirements

### Requirement: Each day can carry a note and tags

The system SHALL let the user write a free-text note and toggle quick tags
for any day. The tags are Race, Training, Celebration, Sick, Travel, Party and
Rest day. The note and tags are edited from the bottom of that day's home
screen and SHALL be saved locally without an explicit save action.

#### Scenario: Tag a race day

- **WHEN** the user opens last Saturday with the day switcher, taps the Race tag and types "Half marathon PB"
- **THEN** reopening last Saturday shows the Race tag selected and the note text

#### Scenario: Clearing a note

- **WHEN** the user deletes all text and deselects every tag
- **THEN** no note is stored for that day

### Requirement: Tagged days are marked in Trends

The system SHALL show a marker for each tagged day on the Trends screen's
daily charts. Tapping a marker SHALL reveal that day's note.

#### Scenario: Spike explained

- **WHEN** a day tagged Celebration shows 3800 kcal in Trends
- **THEN** that day's bar carries the 🎉 marker and tapping it shows the note
