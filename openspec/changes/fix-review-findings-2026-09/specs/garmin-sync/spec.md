## ADDED Requirements

### Requirement: Queued entries are only delivered to the account they were logged under

The system SHALL stamp every queued food, weight and water entry with the Garmin account signed in when it was logged, and SHALL NOT deliver a stamped entry to any other account, nor while the signed-in account is not yet known. Such entries SHALL be held, not deleted. Signing out SHALL tie entries not yet tied to an account to the account being signed out.

#### Scenario: Another account signs in
- **WHEN** entries queued under account A are waiting and account B signs in
- **THEN** none of them is sent to B, and they stay in the queue

#### Scenario: The same account signs in again
- **WHEN** account A signs in again and its profile is read
- **THEN** A's held entries are delivered

### Requirement: An accepted write is never blindly sent again

The system SHALL record that a send has started before the request goes out, and SHALL NOT send an entry whose start could not be recorded. After a relaunch, an entry whose send started but whose outcome was never recorded SHALL NOT be sent again without evidence: food is checked by reconciliation, a weigh-in is looked up in Garmin's day view first, and a drink is left failed with a note for the user.

#### Scenario: Weigh-in accepted, outcome not saved, app restarted
- **WHEN** Garmin accepted a weigh-in but the app stopped before saving that, and Garmin's day view lists it
- **THEN** it is marked delivered and not sent again

#### Scenario: Drink accepted, outcome not saved, app restarted
- **WHEN** the same happens to a drink
- **THEN** it is not sent again and waits, failed with a note, in the sync queue

### Requirement: Background delivery covers every outbox kind

The system SHALL schedule a background refresh when leaving the app whenever any food, weight or water entry is waiting, reading the queues themselves, and each background pass SHALL deliver all three and reconcile every accepted food entry not yet reconciled.

#### Scenario: Weight-only queue
- **WHEN** only a weigh-in is waiting and the user leaves the app
- **THEN** a background refresh is scheduled and delivers it

#### Scenario: Accepted food entry whose re-read failed
- **WHEN** a background pass delivered a food entry but couldn't re-read the day
- **THEN** a refresh stays scheduled and a later pass reconciles it
