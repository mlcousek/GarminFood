## Purpose

Maintain an evidence-backed, dated record of every private Garmin Connect endpoint this project depends on, together with read-only tooling that re-verifies that record on demand, so that when an undocumented route changes the failure is diagnosable in minutes rather than mistaken for absent data.

## ADDED Requirements

### Requirement: Registry records every depended-upon route with evidence

The project SHALL maintain a machine-readable registry at `docs/garmin-routes.json` in which every Garmin endpoint the project calls is recorded with its HTTP method, path, the date it was last observed working, and the status code observed on that date. Application code SHALL NOT call a route that has no registry entry.

#### Scenario: A new route is adopted

- **WHEN** a developer adds a call to a Garmin endpoint not previously used
- **THEN** the registry contains an entry for that endpoint with method, path, `lastVerified` date and `observedStatus`
- **AND** the probe harness includes it automatically, because the harness reads its route list from the registry

#### Scenario: A route is called that is absent from the registry

- **WHEN** application code issues a request to a Garmin path with no registry entry
- **THEN** the review that introduced it is rejected
- **AND** the reason given names the missing registry entry

### Requirement: Probe harness verifies the registry without mutating the account

The probe harness SHALL issue only non-mutating requests. It MUST NOT issue POST, PUT, PATCH or DELETE against any Garmin route, so that verification is always safe to run against a live personal account.

#### Scenario: Harness runs against a live account

- **WHEN** the probe harness is executed against the owner's Garmin account
- **THEN** every request it issues uses the GET method
- **AND** the account's food log, profile and settings are unchanged afterwards

#### Scenario: A write route is present in the registry

- **WHEN** the registry contains an entry whose method is POST, PUT, PATCH or DELETE
- **THEN** the harness reports that entry as documented but not exercised
- **AND** it does not send the request

### Requirement: Probe harness distinguishes the four failure modes

The harness SHALL report 400, 401, 402/403, 404 and 429 as distinct outcomes rather than collapsing them into a single failure, because each implies a different remedy. It SHALL print the full response body for any 400, since Garmin's validators name the parameter they expected.

#### Scenario: Route exists but the request is malformed

- **WHEN** a probed route answers 400
- **THEN** the harness reports the route as existing with an invalid request
- **AND** the full response body is printed
- **AND** the outcome is not reported as a missing route

#### Scenario: Stored credentials have expired

- **WHEN** a probed route answers 401
- **THEN** the harness reports an authentication failure
- **AND** the remedy it names is re-bootstrapping the token through a browser sign-in

#### Scenario: Account lacks the required subscription

- **WHEN** a probed route answers 402 or 403
- **THEN** the harness reports an entitlement failure distinct from both a missing route and an authentication failure

#### Scenario: Garmin throttles the harness

- **WHEN** a probed route answers 429
- **THEN** the harness stops issuing further requests
- **AND** it reports how many routes remained unverified

### Requirement: Empty data and absent routes are reported differently

The system SHALL distinguish "this route returned no data for this date" from "this route does not exist". A 404 MUST NOT be reported as an empty result, because an absent route silently treated as empty data is how the existing vault sync concealed a broken endpoint for its entire lifetime.

#### Scenario: A valid route has no data for the requested date

- **WHEN** a food-log route answers 200 with an empty payload
- **THEN** the outcome is reported as no data logged for that date

#### Scenario: A route no longer exists

- **WHEN** a food-log route answers 404
- **THEN** the outcome is reported as a missing route, naming the path
- **AND** it is not reported as no data logged

### Requirement: The write contract is documented before it is exercised

The project SHALL record the food-log write contract — method, path, every request body field, the meal-type enumeration, the response shape, and the observed status codes — in `docs/garmin-food-log-contract.md` before any application code issues a write. Each recorded fact MUST carry the date it was observed.

#### Scenario: Write contract has been captured

- **WHEN** the write route, its request body and its response have been observed
- **THEN** `docs/garmin-food-log-contract.md` documents them with per-fact observation dates
- **AND** dependent changes may begin

#### Scenario: Write contract has not been captured

- **WHEN** discovery has completed without identifying a working write route
- **THEN** the project records the stop condition as met
- **AND** a documented fallback is chosen before any further implementation work begins
