## ADDED Requirements

### Requirement: Plan edits are commands in the event log

The system SHALL record each plan edit as an immutable event in the
phone's local event log before the action returns, with the types
`plan.session.moved` `{week, baseRevision, sessionId, from, to}`,
`plan.session.swapped` `{week, baseRevision, a, aDate, b, bDate}`,
`plan.session.skipped` `{week, baseRevision, sessionId, reason?}`,
`plan.session.unskipped` `{week, baseRevision, sessionId}`,
`plan.rule.overridden` `{week, baseRevision, sessionId, rule}` and
`event.retracted` `{target, reason?}`, where `week` is the ISO week
`YYYY-Www` and `baseRevision` is the revision of that week in the
projection the phone showed. Optional keys SHALL be written as `null` when
empty. The same commands SHALL always produce the same bytes. The system
SHALL NOT edit any plan file; it SHALL only send these events, through the
same delivery and guards as the check-ins.

#### Scenario: Golden commands

- **WHEN** the synthetic commands of the app's plan-command fixture are encoded
- **THEN** the bytes equal the fixture file exactly

#### Scenario: The vault's example commands

- **WHEN** a command or retraction line of the vault's example event fixture is decoded and encoded again
- **THEN** it is the same JSON object as the vault's line

#### Scenario: Connection off

- **WHEN** the vault connection is off or has no device id
- **THEN** no plan edit is offered and none is recorded

### Requirement: The app offers only edits the vault can apply

The system SHALL offer, for a session of a week in the projection's window
that has a revision: a move to another day of the same ISO week, a swap
with another session of that week on another day, a skip with an optional
reason, an unskip of a skipped session, an override of a rule edit, and a
withdrawal of a pending command. It SHALL NOT offer a move or swap when
either date is before the current training day, to a day of another week,
or for a session linked to a race (`raceId` set or type `race`); it SHALL
NOT offer a skip of a race session or of a done session; it SHALL offer
only the withdrawal while one of the phone's commands on that session is
still pending. It SHALL say why a race session cannot be moved.

#### Scenario: Moving within the week

- **WHEN** on Wednesday 23 October the owner opens Thursday's session of that week
- **THEN** Move lists Wednesday, Friday, Saturday and Sunday of the same week, and no Monday, Tuesday or day of the next week

#### Scenario: The race session

- **WHEN** the owner opens the race session on Sunday
- **THEN** there is no Move, Swap or Skip, the detail says the organiser sets the race's date, and the race is not offered as a swap partner of any other session

#### Scenario: Past days

- **WHEN** the owner opens Monday's missed session on Wednesday
- **THEN** Skip is offered and Move and Swap are not

#### Scenario: Stacked edits

- **WHEN** a move of a session is still pending
- **THEN** that session offers only Withdraw

### Requirement: A rule override is sent only after a clear warning

The system SHALL offer to override a rule only for a session the vault
changed by that rule, and SHALL record `plan.rule.overridden` only after
the owner confirms a warning that names the rule, shows the rule's note
and says the override is logged for the Sunday review. An applied override
SHALL be withdrawable, which asks the vault to restore the rule's edit.

#### Scenario: Ride it anyway

- **WHEN** two amber mornings left Wednesday's tempo with only the ride option and the owner taps Override the rule
- **THEN** a warning with the two-ambers note appears, and only "Override anyway" records the command

#### Scenario: Cancelled warning

- **WHEN** the owner dismisses the warning
- **THEN** nothing is recorded

### Requirement: Edits show at once as pending until the vault answers

The system SHALL apply the phone's commands that the vault has not
acknowledged (`seq` above `acks[deviceId].seq`) over the projection, in
sequence order, and SHALL mark each affected session "pending" with
whether the command is only saved on the phone or already sent, on the
week agenda, the session detail and Today's session card. A withdrawn
command SHALL no longer be applied and SHALL show "withdrawal pending"
until acknowledged. A rule override SHALL show the pending mark without
changing the session's options.

#### Scenario: Move in airplane mode

- **WHEN** the owner moves Thursday's run to Friday with no network
- **THEN** the week shows the run on Friday marked pending and saved on the phone at once, and nothing waits for a request

#### Scenario: Acknowledged

- **WHEN** a new projection acknowledges the move's sequence number
- **THEN** the phone stops applying it and shows the projection's placement and the vault's outcome

#### Scenario: Withdrawn before sending

- **WHEN** the owner withdraws a pending skip
- **THEN** the session shows as planned again, marked withdrawal pending, and both events are sent

### Requirement: The vault's outcome is shown in the app's language

The system SHALL show, for each of the phone's commands still in its local
log, the vault's outcome from the projection's `outcomes` -- applied (and
absorbed, shown as applied), superseded, refused or retracted -- with the
vault's reason in the app's language, in the session detail and in the
week's list of plan changes; a session whose latest command was refused or
superseded SHALL be marked on the week agenda. A command acknowledged
without an outcome SHALL read "received by the vault".

#### Scenario: Refused

- **WHEN** the projection lists the phone's move as refused with an English and a Czech reason
- **THEN** the Czech app shows the Czech reason next to "Refused", and the week marks the session "Not applied"

#### Scenario: Superseded after a re-plan

- **WHEN** the desk re-planned the week and the phone's move is superseded
- **THEN** the session is where the new revision puts it, and the plan changes list the move as not applied with the vault's reason
