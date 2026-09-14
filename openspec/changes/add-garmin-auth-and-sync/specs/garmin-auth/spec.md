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

### Requirement: Concurrent refresh within a single process does not duplicate the exchange

**Revised 2026-09-14**: task 6.4 confirmed (`errSecMissingEntitlement`/-34018, live device test) that no shared Keychain group exists on this account — there is no cross-process credential to coordinate in the first place, so the original cross-process lock design does not apply. Within a single process, the system SHALL ensure at most one in-flight OAuth1-to-OAuth2 exchange at a time, so that concurrent callers awaiting an access token do not each independently trigger a redundant exchange.

#### Scenario: Two concurrent callers need a token at once

- **WHEN** two callers within the same process request an access token while the cached one is expired, within the same moment
- **THEN** only one OAuth1-to-OAuth2 exchange is performed
- **AND** both callers receive the resulting token

#### Scenario: Two different processes refresh independently

- **WHEN** the app and a widget extension each hold their own OAuth1 token from their own independent bootstrap and both need to refresh
- **THEN** each refreshes using its own credential, and neither refresh affects the other

### Requirement: Expired long-lived credentials produce a loud, actionable state

The OAuth1 token SHALL be treated as expired when the exchange endpoint returns 401. The system MUST surface this as a persistent, visible "sign in again" state rather than a silent failure, and MUST NOT report it as "no data available".

#### Scenario: Long-lived token has expired

- **WHEN** the OAuth1-to-OAuth2 exchange returns HTTP 401
- **THEN** the app shows a persistent banner directing the user to reconnect their Garmin account
- **AND** any widget or Control depending on the token shows a distinct "sign in to Garmin" state

#### Scenario: A route is merely unavailable, not an auth failure

- **WHEN** an API call fails for a reason other than 401
- **THEN** the failure is not presented as "sign in again"

### Requirement: Each process bootstraps its own credential independently

**Revised 2026-09-14, settled by a live device test**: Keychain Sharing between the app and its extensions is confirmed unavailable on this free Apple Developer account (`errSecMissingEntitlement`/-34018) — not a possibility to detect at runtime, a fixed fact of this account. The system SHALL have each process (app, widget extension, Control) present its own "Connect Garmin" bootstrap independently, and SHALL NOT attempt to read another process's stored token.

#### Scenario: An extension needs to authenticate

- **WHEN** an extension has no Garmin token of its own
- **THEN** it presents its own "Connect Garmin" bootstrap, independent of the app's authentication state

#### Scenario: The app's own authentication is unaffected by an extension's state

- **WHEN** the app has already completed its own bootstrap
- **THEN** it functions normally regardless of whether any extension has completed its own separate bootstrap
