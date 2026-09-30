## ADDED Requirements

### Requirement: The morning check-in asks for the pain score

When the check-in row has a chosen light for the shown training day and
that day's pain is not recorded yet, the row SHALL offer a compact pain
step: one row per default site -- the Achilles sites scored on the most
recent earlier day that has an Achilles entry, else the left Achilles --
each pre-filled with 0, a 0-10 control in half steps per row, a way to
add another site (right or left Achilles, left or right knee, or other
with a short note of at most 200 characters) and to remove a row, and a
Save action. Saving SHALL record one `checkin.morning` for that day with
the same light, session and option as the row and `pains` from the rows
(`[]` when every row was removed). The step SHALL record nothing until
Save is tapped.

#### Scenario: One tap confirms zero

- **WHEN** the owner chose amber this morning, the pain is not recorded and nothing was scored before
- **THEN** the step shows "Achilles (left)" at 0/10, and tapping Save records `checkin.morning {light: amber, pains: [{site: achilles-left, score: 0}]}`

#### Scenario: Two sites

- **WHEN** the owner sets the left Achilles to 4.5 and adds the right knee at 1
- **THEN** Save records `pains` with both entries, and the card shows "Pain: Achilles (left) 4.5/10 · Knee (right) 1/10" (Czech "4,5/10")

#### Scenario: Default from the last scored morning

- **WHEN** the latest earlier day with pains scored both Achilles sites
- **THEN** the step opens with both Achilles rows at 0

### Requirement: The pain score can be corrected the same day

When the shown day's pain is recorded, the card SHALL show it and the row
SHALL offer to edit it; saving the edit SHALL record a new
`checkin.morning` with the same light and the new `pains`, which replaces
the earlier answer. Changing the light afterwards SHALL NOT erase the pain
answer.

#### Scenario: Edit after the run

- **WHEN** the morning check-in recorded the left Achilles at 2 and the owner edits it to 3
- **THEN** a check-in with `pains: [{site: achilles-left, score: 3}]` is recorded and the card shows 3/10

#### Scenario: Light corrected

- **WHEN** after recording the pain the owner changes the light from amber to green
- **THEN** the check-in is recorded without `pains` and the card still shows the recorded pain

### Requirement: The Controls stay light-only and the app offers the pain step

The lock-screen Controls SHALL keep recording the light only (no pain).
After a Control's check-in succeeds, the app SHALL show Today at the
current training day, where the pain step is offered because the day's
pain is not recorded yet.

#### Scenario: Amber from the lock screen

- **WHEN** the owner taps the Amber Control and the app opens
- **THEN** an amber check-in without pain is recorded and Today shows today's check-in row with the pain step open
