## ADDED Requirements

### Requirement: Finishing the setup fetches the plan once

When a settings action leaves the connection usable (switched on, a
repository and a token saved), the system SHALL start one projection fetch
without waiting for the next foreground: after the switch is turned on when
that made the connection usable or nothing was ever synced, after a
repository or a token is saved, and after a successful "Test connection"
when nothing was ever synced. The fetch SHALL NOT block the action, SHALL
go through the same request gate as every other fetch, and SHALL run only
on a Garmin-connected install outside onboarding. At most one such fetch
SHALL run at a time; a repository or token saved while it runs SHALL lead
to exactly one follow-up fetch. Settings -> Vault SHALL show that the plan
is being fetched and then whether it was fetched or refused, and Today and
Plan SHALL reload the cached plan when the fetch ends.

#### Scenario: Setup in the Settings order

- **WHEN** the owner turns the connection on, saves the repository, saves the token and then taps "Test connection"
- **THEN** exactly one projection request is sent, when the token is saved, and Today shows the plan once it has arrived, without leaving the app

#### Scenario: Connection not usable yet

- **WHEN** the repository is saved but no token is stored
- **THEN** no request is sent

#### Scenario: Test after a sync

- **WHEN** "Test connection" succeeds and the plan has already been synced once
- **THEN** no projection request is sent by the test

#### Scenario: New token during the fetch

- **WHEN** a token is saved again while the setup fetch is running
- **THEN** one more fetch runs after it ends, and no other
