## ADDED Requirements

### Requirement: The vault connection is off by default and offered only in Garmin-connected mode

The system SHALL offer Settings → Vault only on installs in Garmin-connected
mode, SHALL keep the connection off until the user turns it on, and SHALL
make no request to GitHub while it is off. The repository owner, name and
branch SHALL be entered by the user on the device; no repository SHALL be
built into the app.

#### Scenario: Fresh update, nothing configured

- **WHEN** the owner updates to this build and uses the app for a day without opening Settings → Vault
- **THEN** no request is made to api.github.com and no vault banner appears

#### Scenario: Standalone install

- **WHEN** a standalone install opens Settings
- **THEN** no Vault row is shown

### Requirement: The token is kept only in this device's Keychain and never leaves it

The system SHALL accept only fine-grained GitHub tokens (`github_pat_`
prefix), SHALL store the token in the Keychain with
after-first-unlock, this-device-only accessibility and no access group,
SHALL never show it again in full (only its last four characters), and
SHALL never write it to the diagnostics log, an error message, a snapshot or
an exported backup.

#### Scenario: Classic token refused

- **WHEN** the user pastes a token starting with `ghp_` and taps Save
- **THEN** nothing is saved and the screen says to use a fine-grained token limited to one repository

#### Scenario: Token absent from logs after failures

- **WHEN** a saved token receives a 401, then a 403, then the network drops
- **THEN** the diagnostics log contains a `vault` entry for each failure and none of them contains any part of the token beyond what Settings shows

#### Scenario: Token absent from an export

- **WHEN** the user exports a backup while a token is saved
- **THEN** the exported file contains no string starting with `github_pat_`

### Requirement: "Test connection" reports what works, without writing

The system SHALL, on "Test connection", check the token and the repository
with read-only requests and report: whether the token was accepted, whether
the repository is reachable, whether the plan file exists (with its size),
and the token's expiry if GitHub reports it. It SHALL create the install's
device identity on the first successful test. It SHALL NOT write anything to
the repository.

#### Scenario: Connected, plan not generated yet

- **WHEN** the token and repository are valid but the projection file does not exist
- **THEN** the checklist shows the token accepted and the repository reachable, and "No plan data yet" as information, not as an error, and no banner appears

#### Scenario: Wrong repository name

- **WHEN** the repository name has a typo
- **THEN** the checklist shows "Repository not found, or the token can't see it" and the connection is marked as needing attention

### Requirement: Failures that need the user are loud; everything else is quiet

While the connection is enabled, the system SHALL show a persistent banner
on every tab when GitHub rejects the token (401), refuses access (403
without rate-limit signals), cannot find the repository (404), when no
token is stored, or when the token expires within 14 days. After a loud
failure it SHALL stop vault requests until the user changes the token or
repository or taps "Try again". It SHALL NOT show a banner for being
offline, for rate limiting or for server errors; it SHALL retry those later,
honouring `Retry-After` and the rate-limit reset time.

#### Scenario: Token revoked on github.com

- **WHEN** the owner revokes the token and brings the app to the foreground
- **THEN** a banner says the vault token expired or was revoked, tapping it opens Settings → Vault, and no further request is sent on the next foreground

#### Scenario: Rate limited

- **WHEN** GitHub answers 429 with `Retry-After: 120`
- **THEN** no banner appears, no vault request is sent for 120 seconds, and Settings shows the last successful sync time

#### Scenario: Offline

- **WHEN** the phone is in airplane mode at foreground
- **THEN** no banner appears and the last good plan data stays available

#### Scenario: Restored on a new phone

- **WHEN** a backup with an enabled connection is restored on a phone with no token saved
- **THEN** the banner asks the user to paste the vault token again

### Requirement: The connection's state is visible and can be removed

The system SHALL show in Settings → Vault the last successful sync time, the
last problem with its time, the token expiry countdown (or "Expiry
unknown"), and the device id once created. "Disconnect" SHALL, after
confirmation, delete the token from the Keychain, clear the cached vault
data and status, and turn the connection off, keeping the device id.

#### Scenario: Disconnect

- **WHEN** the user confirms Disconnect
- **THEN** the Keychain holds no vault token, no vault data is cached, the switch is off, and the next foreground makes no GitHub request

#### Scenario: Expiry countdown

- **WHEN** GitHub reports the token expires in 10 days
- **THEN** Settings shows "Expires in 10 days" and the banner shows the same warning on every tab
