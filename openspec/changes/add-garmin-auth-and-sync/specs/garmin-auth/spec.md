## Purpose

Obtain, store, share and refresh Garmin Connect credentials without the app ever handling the user's password, and keep the app usable — with a clearly signalled degraded state — whenever a token expires or credential sharing across processes is unavailable.

## ADDED Requirements

### Requirement: Credential bootstrap never exposes the user's password to the app

The app SHALL obtain Garmin credentials only through a browser-based sign-in session (`ASWebAuthenticationSession` against Garmin's mobile SSO page, last verified reachable 2026-09-14). The app process MUST NOT receive, log, or persist the Garmin account password in any form.

#### Scenario: User connects their Garmin account

- **WHEN** the user taps "Connect Garmin"
- **THEN** Garmin's own sign-in page is presented inside a browser-authentication session
- **AND** the app captures only the resulting service ticket from the redirect, never the credentials entered on that page

#### Scenario: Codebase audit for password handling

- **WHEN** the app's source is searched for any Garmin password field, variable or parameter
- **THEN** none exists outside the browser-authentication session's opaque page content

### Requirement: OAuth1 token is exchanged for a short-lived OAuth2 access token

The app SHALL sign an OAuth1 request with the stored long-lived token and exchange it at `POST /oauth-service/oauth/exchange/user/2.0` (verified working 2026-09-14, returning a token valid approximately 24 hours) whenever no unexpired OAuth2 access token is cached.

#### Scenario: Access token has expired

- **WHEN** the cached OAuth2 access token is within five minutes of its recorded expiry
- **THEN** the app signs and sends a fresh exchange request before making the dependent API call

#### Scenario: Access token is still valid

- **WHEN** the cached OAuth2 access token has more than five minutes of validity remaining
- **THEN** no exchange request is sent

### Requirement: Concurrent refresh from multiple processes does not corrupt the token

When credential sharing across processes is enabled, the system SHALL ensure at most one process performs the OAuth1-to-OAuth2 exchange at a time, using the atomicity of a Keychain item insertion as the coordination mechanism, so that the app and an extension refreshing simultaneously do not race.

#### Scenario: App and extension refresh at the same moment

- **WHEN** the app and the widget extension both detect an expired access token within the same second
- **THEN** exactly one of them performs the exchange
- **AND** the other re-reads the Keychain and finds a valid token without exchanging again

#### Scenario: A refresh lock is abandoned mid-flight

- **WHEN** a process holding the refresh lock is terminated before completing the exchange
- **THEN** the lock is treated as stale after a short timeout
- **AND** a subsequent process is able to acquire it and refresh

### Requirement: Expired long-lived credentials produce a loud, actionable state

The OAuth1 token SHALL be treated as expired when the exchange endpoint returns 401. The system MUST surface this as a persistent, visible "sign in again" state rather than a silent failure, and MUST NOT report it as "no data available".

#### Scenario: Long-lived token has expired

- **WHEN** the OAuth1-to-OAuth2 exchange returns HTTP 401
- **THEN** the app shows a persistent banner directing the user to reconnect their Garmin account
- **AND** any widget or Control depending on the token shows a distinct "sign in to Garmin" state

#### Scenario: A route is merely unavailable, not an auth failure

- **WHEN** an API call fails for a reason other than 401
- **THEN** the failure is not presented as "sign in again"

### Requirement: Credential sharing across processes degrades without breaking the app

Because the app ships on a free Apple Developer account (owner decision, 2026-09-14), Keychain Sharing between the app and its extensions is not guaranteed to be available. The system SHALL detect at build/setup time whether shared credential access works, and SHALL fall back to independent per-process credential bootstrap when it does not, rather than leaving any process permanently unauthenticated.

#### Scenario: Shared Keychain access group is available

- **WHEN** the app and its extensions can read a Keychain item written by another process in the same access group
- **THEN** one bootstrap in the app authenticates the widget and Control extensions as well

#### Scenario: Shared Keychain access group is not available

- **WHEN** an extension cannot read the app's stored token
- **THEN** the extension presents its own "Connect Garmin" bootstrap independently
- **AND** the app continues to function normally once the app's own bootstrap has completed
