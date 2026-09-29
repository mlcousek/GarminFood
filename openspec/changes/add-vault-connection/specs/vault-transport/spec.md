## ADDED Requirements

### Requirement: The plan file is fetched conditionally and never awaited by the UI

While the connection is enabled and not blocked, the system SHALL fetch the
projection file at most once a minute on foreground (and on pull to
refresh), sending the stored ETag so an unchanged file costs a `304`
without a body. The fetch SHALL run without any screen or user action
waiting for it, and SHALL never run on a confirm or save path.

#### Scenario: Unchanged file

- **WHEN** the app comes to the foreground and the projection has not changed since the last fetch
- **THEN** the request carries `If-None-Match` with the stored ETag, GitHub answers 304, and the last successful sync time is updated

#### Scenario: Two foregrounds within a minute

- **WHEN** the app becomes active twice within 60 seconds without pull to refresh
- **THEN** only one request is sent

### Requirement: Fetched data replaces the cached copy only after it validates

The system SHALL store a fetched file's bytes and ETag only after the
consumer's validator accepts them. A file that fails validation SHALL leave
the last good copy and its ETag in place, SHALL be logged once, and SHALL
NOT be downloaded again while its ETag is unchanged. The last good copy
SHALL be available after a cold launch without network.

#### Scenario: A broken file is published

- **WHEN** the vault publishes a projection that is not valid JSON
- **THEN** the app keeps using the previous copy, logs one `vault` error, and the next foreground receives 304 for the same broken file

#### Scenario: Cold launch offline

- **WHEN** the app is launched in airplane mode after a successful fetch the day before
- **THEN** the last good projection bytes are available to the app with their fetch time

### Requirement: The app may write only into its own events folder and read only its allowed files

The system SHALL refuse, before any network request, every write whose
normalised hub-relative path is not under `events/<ownDeviceId>/` with a
`.jsonl` extension, and every read outside `projection/*.json` and its own
events folder. Paths containing empty, `.` or `..` segments, backslashes,
percent-encoding, control characters or a device id other than this
install's SHALL be refused, not corrected. The hub root is
`Sport/Training/_hub` in the vault repository.

#### Scenario: Another device's folder

- **WHEN** a write to `events/ios-00000000/2026/10/x.jsonl` is attempted on an install whose id is `ios-7f3a91c2`
- **THEN** it is refused with no request sent, and an error is logged

#### Scenario: Traversal attempt

- **WHEN** a write to `events/ios-7f3a91c2/../../projection/projection.v1.json` is attempted
- **THEN** it is refused with no request sent

#### Scenario: Reading a daily note

- **WHEN** a read of any path outside `projection/` and the install's own events folder is attempted
- **THEN** it is refused with no request sent

### Requirement: Each install has its own device identity that is never copied

The system SHALL create a device id of the form `ios-` followed by 8
lowercase hex characters on the first successful connection test, store it
in the app's container with a persisted sequence counter that never hands
out the same number twice, and SHALL exclude it from every snapshot and
export.

#### Scenario: Sequence numbers after a crash

- **WHEN** three sequence numbers are reserved and the app is killed before using them
- **THEN** the next reservation after relaunch starts above all three

#### Scenario: Restore on a new phone

- **WHEN** a backup from the owner's phone is restored on a new phone and the connection is tested there
- **THEN** the new phone gets a different device id

### Requirement: Vault writes are durable, create-only and idempotent

The system SHALL queue each vault write as a sealed file whose bytes never
change after sealing, deliver it with a create-only request, and treat an
"already exists" answer as delivered only when the existing file's git blob
SHA equals the sealed bytes' SHA. The queue SHALL persist across launches,
SHALL stop a delivery cycle without spending attempts on an auth failure or
when offline, SHALL stop the whole cycle on a rate limit, SHALL back off
between attempts, and SHALL mark an entry failed and visible after five
attempts. No production code path SHALL enqueue a write in this change.

#### Scenario: Lost response

- **WHEN** a create succeeded on GitHub but the response was lost, and the retry gets 422
- **THEN** the retry compares blob SHAs, finds them equal, and marks the entry delivered without creating a second file

#### Scenario: Different file at the same path

- **WHEN** the retry gets 422 and the existing file's SHA differs from the sealed bytes'
- **THEN** the entry is marked failed with "a different file already exists" and an error is logged

#### Scenario: Offline delivery

- **WHEN** a drain runs with no network
- **THEN** it stops after the first entry and no entry's attempt count changes

### Requirement: Training code depends on a transport, not on GitHub

The system SHALL route every vault read and write through a transport
interface whose paths are relative to the hub root, with GitHub as its only
implementation in this change, so that another transport can replace it
without changes to the code that uses it. The path allow-lists SHALL apply
to every transport.

#### Scenario: A stub transport in tests

- **WHEN** the conditional fetch and the create-only uploader are tested with an in-memory transport
- **THEN** they behave as with the GitHub transport, including the allow-list refusals

### Requirement: Vault state in backups is limited to the connection settings

The system SHALL exclude the device identity, the vault status, the fetch
cache and the write queue from every snapshot and export, SHALL include the
connection settings (enabled, owner, name, branch), and SHALL treat any file
content starting with a GitHub token prefix as a secret that makes the file
excluded. Every new vault store file SHALL have a committed fixture loaded
through the real store in CI.

#### Scenario: Snapshot contents

- **WHEN** a daily snapshot is taken on a connected install
- **THEN** it contains `vault.connection.v1` and none of `VaultKit/device-identity.json`, `status.json`, `fetch-cache.json`, `cache/` or `write-queue.json`

#### Scenario: A store without a fixture

- **WHEN** a developer adds a VaultKit store file without a fixture
- **THEN** the store-coverage test fails and names the file
