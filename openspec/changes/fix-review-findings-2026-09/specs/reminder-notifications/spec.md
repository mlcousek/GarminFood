## ADDED Requirements

### Requirement: Reminders keep firing while the app stays closed

The system SHALL keep each enabled daily reminder scheduled for a rolling window of the coming days (food reminders and the training check-in and habits reminders), re-planned whenever the app runs, within the system's limit on pending notifications. Reminders whose firing depends on today's state SHALL only be scheduled for today.

#### Scenario: App not opened after midnight
- **WHEN** the breakfast reminder is on and the app is not opened on the next day
- **THEN** the next day's breakfast reminder still fires

### Requirement: Granting permission schedules the reminders already switched on

The system SHALL re-sync every reminder when notification permission changes from undecided to allowed.

#### Scenario: First reminder switched on
- **WHEN** the user switches on the first reminder and accepts the permission prompt
- **THEN** that reminder is scheduled without reopening the app
