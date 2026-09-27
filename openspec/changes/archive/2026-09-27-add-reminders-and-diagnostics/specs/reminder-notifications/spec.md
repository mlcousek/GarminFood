## Purpose

Nudge the user back into the app at chosen times, without ever reminding about something already done.

## ADDED Requirements

### Requirement: Each reminder is independently configurable

The system SHALL let the user enable or disable, and set a time for, each of: a breakfast reminder, a lunch reminder, a dinner reminder, a streak-at-risk reminder, and a daily-challenges reminder, independently of the others.

#### Scenario: Enabling one reminder leaves the others untouched

- **WHEN** the user enables the breakfast reminder at 8:00
- **THEN** lunch, dinner, streak, and daily-challenge reminders remain in whatever state they were already in

### Requirement: A meal reminder does not fire once that meal is logged

The system SHALL NOT keep a meal reminder scheduled for a day on which that meal already has a logged entry.

#### Scenario: Logging breakfast cancels today's breakfast reminder

- **WHEN** the breakfast reminder is enabled and scheduled for later today, and the user logs a breakfast entry
- **THEN** the breakfast reminder no longer fires today

#### Scenario: An already-logged meal does not get a reminder scheduled at all

- **WHEN** the user enables a meal reminder for a meal that's already logged today
- **THEN** no reminder is scheduled for today for that meal

### Requirement: The streak reminder only fires when a streak is genuinely at risk

The system SHALL only keep the streak reminder scheduled on a day when the user has an active streak and has not yet logged anything that day.

#### Scenario: No streak, no reminder

- **WHEN** the streak reminder is enabled and the user has no active streak
- **THEN** the streak reminder is not scheduled

### Requirement: Notification permission is requested only when the user opts in

The system SHALL request notification authorization only when the user enables their first reminder, not on app launch.

#### Scenario: First reminder enabled

- **WHEN** the user enables a reminder for the first time and no authorization decision has been made yet
- **THEN** the system notification permission prompt is shown

### Requirement: A denied notification permission is shown plainly

The system SHALL show the user, in the reminders settings screen, when notification permission has been denied at the OS level, with a way to open Settings to fix it.

#### Scenario: Permission denied

- **WHEN** the user has denied notification permission and opens the reminders settings screen
- **THEN** a note explaining reminders won't fire is shown, with a link to the system Settings app
