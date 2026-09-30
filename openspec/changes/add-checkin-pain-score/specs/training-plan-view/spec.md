## ADDED Requirements

### Requirement: Plan days show the recorded pain

The week agenda's day rows and the month's day sheet SHALL show one pain
tag per recorded site of that day, "<site> <score>/10" in the app's
language, in the order recorded, and none when the pain was not asked or
nothing hurts. The vault's `pain-rising` and `pain-high` week notes SHALL
be shown like any other rule note of the week.

#### Scenario: The example's Wednesday

- **WHEN** the example projection's 2030-10-23 has the left Achilles at 5.5 and the right knee at 1
- **THEN** that day's row shows "Achilles (left) 5.5/10" and "Knee (right) 1/10" (Czech "Achilovka (levá) 5,5/10"), and W43 lists the `pain-high` note after its other rule notes
