## Context

Written 2026-09-28 against `origin/main` @ `a4ee380`. It implements the
app side of the transport the owner's vault planning note proposes
(sections 2.4, 3 and 9 of its training-hub architecture note), as far as
reading goes, and designs the writing side without exercising it.

The owner's decisions it rests on (2026-09-28): the vault is the source of
truth (A1); the app connects directly to the vault's GitHub repository for
now, hardening later (A3); one writer per file (A4); this app repository
stays public (A13).

What the code already provides and this change reuses rather than copies:

- `GarminKit/TokenProvider.swift`: a Keychain wrapper with
  `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (the 2026-09-21
  security fix: `ThisDeviceOnly` keeps the item out of device backups) and
  no access group (Keychain Sharing is blocked on a free account).
- `GarminKit/Outbox.swift` and its two siblings (`WeightSync`,
  `HydrationSync`): the durable queue semantics, the `DrainAuthOutcome`
  split between loud auth failures and quiet everything else,
  `backoffDelay(attempt:jitter:base:cap:)` (internal), and
  `ConnectivityFailure` (being offline never spends an attempt; learned on
  2026-09-23).
- `GarminKit/PersistedJSON.swift`: load with quarantine, never wipe, and
  `ensureSafeToWrite` for the "file exists but unreadable before first
  unlock" case.
- `GarminKit/DiagnosticsLog.swift`: the in-app log, English only.
- `App/AuthBannerView.swift`: the loud, persistent banner pattern, placed on
  every tab by `withStatusBanners()`.
- `FoodLogCore/Backup/`: `StoreCatalog`, `BackupExclusions`,
  `BackupSecretPolicy` and per-package store fixtures (`add-data-safety`).
- `add-mcp-server` D2: the iCloud Drive bridge folder, unverified on this
  account, which is the future hardening transport.

## Evidence (probes)

Nothing was probed for this change: no token was available in the planning
session, and none may be used from this public repository's CI. GitHub's
REST API is public and documented, unlike Garmin's, but the details the
design leans on are still recorded as **documented, not yet observed** and
are probed from the owner's PC, read-only, before wave 3 (tasks 1.1–1.3):

| Behaviour | Source | Status |
|---|---|---|
| `GET /repos/{owner}/{repo}/contents/{path}` with `Accept: application/vnd.github.raw+json` returns the file's bytes | GitHub REST docs, "Get repository content" | **observed 2026-09-29** (200, 83 528 bytes) |
| That response carries an `ETag`, and `If-None-Match` with it returns `304` with no body | GitHub REST docs, "Conditional requests" | **observed 2026-09-29** (strong ETag on the raw response; 304, 0 bytes) |
| A `304` does not count against the primary rate limit | GitHub REST docs, rate limits | **observed 2026-09-29** (`x-ratelimit-remaining` 4992 before and after) |
| Fine-grained tokens get 5,000 requests/hour; content-creating requests have secondary limits (about 80/minute, 500/hour) | GitHub REST docs | documented |
| Responses to requests made with an expiring token carry `github-authentication-token-expiration` | GitHub docs ("Token expiration") | **observed 2026-09-29**: exact name, value `yyyy-MM-dd HH:mm:ss UTC` (the parser's first format); present on 200/304/404, absent on 401 |
| `PUT …/contents/{path}` without `sha` creates a file and returns `201`; if the path exists it returns `422` | GitHub REST docs, "Create or update file contents" | documented; probed only in `add-training-checkins` |
| `GET /repos/{owner}/{repo}` returns `404` for a private repository the token can't see | GitHub REST docs | **observed 2026-09-29** (404 for a non-existent name; 401 for a wrong token) |

`tools/probe-github-contents.mjs` (GET-only) records, dated, in this file:
status codes, the presence and name of `ETag`, the expiry header's exact
name and date format, and the rate-limit header names. It prints no body,
no token and no repository name.

**Probe run 2026-09-29 (owner's PC, fine-grained token, Contents read/write on one repository):**

| Step | Status | Notes |
|---|---|---|
| 1. `GET /repos/{o}/{r}` | 200 | weak ETag; expiry header present |
| 2. projection, raw media type | 200 | 83 528 bytes; strong ETag (42 chars); `last-modified` present |
| 3. same, `If-None-Match` | 304 | 0 bytes; rate limit not spent; no redirect |
| 4. non-existent repository | 404 | expiry header present |
| 5. wrong token | 401 | no rate-limit or expiry headers |

Rate-limit headers seen: `x-ratelimit-limit` (5000), `x-ratelimit-remaining`, `x-ratelimit-used`, `x-ratelimit-reset` (epoch seconds), `x-ratelimit-resource` (`core`). `retry-after` did not appear (no limit was hit). The owner chose a one-year expiry instead of the suggested 180 days; the 14-day banner covers either.

## Goals / Non-Goals

**Goals**
- A connection that is off unless turned on, holds its token safely, and
  never makes the app wait.
- One conditional GET per foreground for the projection, cached so the app
  works offline with the last good copy.
- A write path that is designed, tested and incapable of writing outside
  the app's own folder, ready for `add-training-checkins`.
- Failures that need the user are loud; everything else is quiet.
- A seam that lets another transport replace GitHub later.

**Non-goals**: see proposal.md.

## Decisions

### D1 — `VaultKit`: a wire package with no training concepts

```
VaultKit  (depends on GarminKit: PersistedJSON, DiagnosticsLog, RetryBackoff,
           ConnectivityFailure)
  VaultRepository        owner/name/branch value + validation
  HubPath                a path relative to the hub root, normalised
  VaultPathPolicy        pure allow-lists (D4)
  GitHubContentsAPI      protocol: getFile(path, ifNoneMatch), createFile(path, bytes, message),
                         getRepository()
  GitHubContentsClient   URLSession implementation (D2, D6)
  VaultTokenStore        Keychain (D3)
  DeviceIdentity         container-stored id + seq counter (D5)
  DurableQueue<Record>   generic queue (D7)
  CreateOnlyFileUploader SealedFile delivery with blob-SHA idempotency (D7)
  ConditionalFileSync    fetch → validate → commit bytes + ETag (D8)
  VaultTransport         protocol; GitHubVaultTransport implements it (D9)
  VaultStatus            pure status model + outcome classification (D6, D10)
```

It mirrors the existing boundary: GarminKit knows Garmin's wire and nothing
about meals; VaultKit knows GitHub's wire and nothing about sessions or
habits. `TrainingCore` (next change) depends on `VaultTransport`, never on
`GitHubContentsClient`.

It depends on GarminKit only for the four shared utilities listed. Moving
those into a small common package is a sensible later clean-up, not a
prerequisite (the same note `add-data-safety` made).

VaultKit has **no user-facing strings**. Errors and statuses are typed;
the app maps them to localized text (`VaultErrorPresentation`), so the
package needs no `.lproj` resources and the localization checker needs no
change. `DiagnosticsLog` lines stay English.

It is linked into the **app target only**. `Shared/AppServices.swift` is
compiled into the widget too, so the vault's objects live in an app-only
`VaultServices` (one instance per process, `GarminFood/Vault/`), the way
`GamificationEngine` stays out of the widget.

### D2 — Reading: one conditional GET of one file

- `GET https://api.github.com/repos/{owner}/{repo}/contents/{hubRoot}/projection/projection.v1.json?ref={branch}`
  with `Accept: application/vnd.github.raw+json`,
  `X-GitHub-Api-Version: 2022-11-28`, `Authorization: Bearer <token>`, and
  `If-None-Match: <etag>` when one is stored.
- The hub root `Sport/Training/_hub` is a **contract constant** agreed with
  the vault, not a secret; the repository owner and name are never
  compiled in.
- `304` means "unchanged": the cached bytes stay, `lastSuccessAt` moves.
- `200` hands the bytes to the caller's validator (D8).
- **Least data**: the app never lists trees, never clones, never reads any
  path outside the read allow-list (D4).
- The host is fixed to `api.github.com`. A redirect to any other host is
  refused (`URLSessionTaskDelegate`), so the `Authorization` header can't
  follow a redirect elsewhere. Same-host redirects (a renamed repository)
  are followed.
- The session is ephemeral with `urlCache = nil`: no response is cached by
  `URLSession` on disk; the only copy is ours (D8). Request timeout 20 s.
- **Fallback if `ETag`/`304` don't behave as documented** (probe 1.2): keep
  the fetch unconditional; the file is small (tens of KB) and fetched at
  most once a minute in the foreground.

### D3 — The token

- **Fine-grained personal access token**, resource owner the owner, access
  to **one repository**, permission **Contents: Read and write** (Metadata
  read is implicit). Nothing else. Expiry about 180 days (tasks 0.1).
  `docs/vault-connection.md` and the Settings help text walk through
  creating it without naming any repository.
- **Classic tokens are refused** (`ghp_…`): they can't be limited to one
  repository. The field accepts only `github_pat_…`; anything else gets
  "Use a fine-grained token limited to one repository". Owner may override
  (tasks 0.2).
- **Storage**: `VaultTokenStore`, Keychain generic password, service
  `com.mlcousek.garminfood.vault`, account `github.token`,
  `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, no access group. The
  same wrapper shape as `KeychainStore`; a test seam for a different
  service name. `ThisDeviceOnly` keeps it out of device backups and off a
  restored phone.
- **Entry**: a `SecureField` plus a `PasteButton` (no "Allow Paste"
  prompt); whitespace trimmed; saved on "Save". It is never shown again;
  Settings shows "Token saved · ends in …a1b2" (last four characters) and
  the save date.
- **Never logged**: requests are built per call and never stored in an
  error; error types carry a status code, a hub-relative path and header
  values the classifier needs, nothing else. A test plants a token and
  scans every `DiagnosticsLog` line and every error description the
  failure paths produce.
- **Never exported**: the Keychain is outside every backup already;
  `BackupSecretPolicy` additionally scans backup content for the GitHub
  token prefixes (`github_pat_`, `ghp_`, `gho_`, `ghu_`, `ghs_`, `ghr_`),
  so a token pasted into a note or a custom food's name is caught too.
- **Disconnect** deletes the token from the Keychain, clears the fetch
  cache and status, and turns the switch off. The device identity is kept:
  reconnecting the same install to the same vault keeps writing into the
  same folder.

### D4 — `VaultPathPolicy`: pure allow-lists, enforced in the client

- **Write**: allowed only for `events/<ownDeviceId>/…` under the hub root,
  file extension `.jsonl`, where `<ownDeviceId>` is this install's id.
- **Read**: allowed only for `projection/*.json` under the hub root, and
  for the install's own `events/<ownDeviceId>/…` (needed by the create-only
  idempotency check, D7).
- **Normalisation before the check** (`HubPath`): relative, `/`-separated,
  no empty, `.` or `..` segment, no backslash, no percent-encoding, no
  control characters, ASCII letters, digits and `-_.` only per segment, no
  leading or trailing slash. A path that isn't normal is refused, never
  "fixed".
- Device ids must match `^ios-[0-9a-f]{8}$`; `events/ios-7f3a91c2x/…` and
  `events/ios-7f3a91c2/../ios-00000000/…` are refused.
- **Enforced inside `GitHubContentsClient`**, the only type that builds
  request URLs; `createFile` and `getFile` check the policy before any
  network call and return `.refusedByPolicy`, logged as an error. No public
  API accepts a full repository path.
- It limits bugs, not a stolen token: GitHub has no per-path token
  permissions. The vault side guards its own executable paths (its
  planning note's pull guard); that is out of this repository's reach and
  stated in `docs/vault-connection.md`.

### D5 — `DeviceIdentity`

- `ios-` + 8 lowercase hex characters from a random UUID, created **on the
  first successful "Test connection"** (not on install), stored in
  `Application Support/VaultKit/device-identity.json` with its creation
  date and the next sequence number.
- `reserveSequence(count:)` persists the new counter **before** returning
  the numbers, so a crash can skip numbers but never reuse one.
- Stored in the container, not the Keychain: a fresh container
  (reinstall, a new phone) must get a new id, so two installs never share
  an events folder.
- **Never restored from a backup** (a `BackupExclusions` entry). A restore
  keeps the file already on the phone, so restoring on the same phone keeps
  its id and restoring on a new phone creates a new one.
- Unused in production until `add-training-checkins`, apart from being
  shown in Settings → Vault → Details (so the owner can find the folder).

### D6 — Classifying responses: loud, quiet, retry

The classifier (`VaultOutcome.classify(status:headers:error:)`) is pure
and table-tested:

| Response | Outcome | User sees |
|---|---|---|
| `2xx`, `304` | success | "Last sync: just now" |
| `401` | `.authFailed(.tokenRejected)` | **loud** banner: "Vault token expired or revoked" |
| `403` without rate-limit signals | `.authFailed(.forbidden)` | **loud**: "The token can't access this repository" |
| `404` on the repository | `.authFailed(.repositoryNotFound)` | **loud**: "Repository not found, or the token can't see it" |
| `404` on the projection, repository reachable | `.fileNotFound` | quiet: "Connected. No plan data yet." |
| `429`, or `403` with `x-ratelimit-remaining: 0` or `retry-after` | `.rateLimited(until:)` | quiet; next attempt after `retry-after` or `x-ratelimit-reset` |
| `422` on create | `.alreadyExists` | handled by D7 |
| `409` | `.conflict` | quiet retry with backoff |
| `5xx` | `.serverError` | quiet retry with backoff |
| `ConnectivityFailure.matches` | `.offline` | quiet; no attempt spent |
| anything else | `.unexpected(status)` | quiet, logged; shown in Details |

- To tell a missing repository from a missing file, "Test connection" and
  the first fetch after a `404` do one `GET /repos/{owner}/{repo}` (cheap,
  counts once).
- Loud outcomes stop every vault call until the user acts (saves a new
  token, edits the repository, or taps "Try again"), so a revoked token
  doesn't produce a request per foreground.
- Rate limiting persists `rateLimitedUntil` in the status file; nothing is
  sent before it. "Treat 429 as stop and resume later, not retry harder"
  (`openspec/config.yaml`).

### D7 — Writing, designed now: `DurableQueue` and create-only uploads

**`DurableQueue<Record: Codable & Sendable & Identifiable>`** is the
generic form of the three Garmin outboxes, keeping their proven rules:

- one JSON file per queue per process, loaded through `PersistedJSON`
  (quarantine, never wipe; `ensureSafeToWrite` on every save);
- states `pending`, `sent`, `failed`; `attemptCount`, `nextAttemptAt`,
  `lastError`;
- `drain(using:)` takes a `DurableQueueDelivering` that returns
  `.delivered`, `.retry(after:)`, `.stopCycle(.auth)`,
  `.stopCycle(.rateLimited(until:))`, `.stopCycle(.offline)` or
  `.failedPermanently(reason:)`;
- auth and offline stop the cycle **without spending an attempt**; a rate
  limit stops the whole cycle; `maxAttempts` (5) turns an entry `failed`,
  which is visible and retryable by hand;
- backoff: `RetryBackoff.delay(attempt:jitter:base:cap:)`, GarminKit's
  existing `backoffDelay` made public under a neutral name, with
  `Outbox`/`WeightSync`/`HydrationSync` calling it (behaviour unchanged,
  their tests unchanged);
- an `isDraining` guard, so concurrent triggers share one drain;
- `DiagnosticsLog` category `vault`.

**`SealedFile`** `{ id, path: HubPath, bytes, blobSHA, commitMessage,
createdAt }` is the record a vault write queues. "Seal, then send": the
bytes are fixed when the record is created, so every retry sends the same
bytes.

**`CreateOnlyFileUploader`** delivers one `SealedFile`:

1. `PUT` without `sha` (create-only). `201` → delivered.
2. `422` "already exists" → `GET` the same path (allowed: it is the
   install's own folder), compute the git blob SHA of our bytes,
   `sha1("blob " + byteCount + "\0" + bytes)`, and compare with the
   response's `sha`. Equal → delivered (an earlier attempt succeeded but
   its response was lost). Different → `.failedPermanently("a different
   file already exists")`, logged as an error: it can only mean a bug,
   because paths embed the device id and a timestamp.
3. `409` → retry (parallel writes race on the branch ref; writes are
   serialised in one actor anyway).

Paths, file names and commit messages are the caller's business:
`add-training-checkins` defines the segment layout
(`events/<deviceId>/<yyyy>/<mm>/<timestamp>-<firstSeq>.jsonl`) and the
envelope. **Nothing in this change enqueues a record in production.** The
queue's file is created lazily on the first enqueue, so no install gets one
from this change.

**Backups**: the queue is per-device delivery state, like the Garmin
outboxes, and is excluded. Whether the *event log* behind it (a later
store) is backed up is `add-training-checkins`' decision; the vault's
dedupe by event id makes that safe.

### D8 — `ConditionalFileSync`: commit only what validated

```
refresh(path, validate: (Data) throws -> Void) async -> FetchReport
```

- Sends the stored ETag (if any). `304` → `.unchanged`.
- `200` → runs `validate(bytes)`. Only if it passes are the bytes and the
  new ETag committed (atomic write, `PersistedJSON` for the metadata file,
  the bytes as a sibling file). If it throws → `.rejected(reason)`, the
  last good bytes and ETag stay, and the rejected ETag is remembered so the
  same bad file isn't downloaded and logged on every foreground (the next
  request sends it as `If-None-Match` and gets `304`).
- `cachedBytes(path)` returns the last good bytes with their fetch date, so
  a cold launch offline still has the last plan.
- In this change the validator is minimal (a JSON object, at most 5 MB).
  `add-training-today-and-plan` passes TrainingCore's decoder.
- Files: `Application Support/VaultKit/fetch-cache.json` (per path: ETag,
  rejected ETag, fetched and generated dates, byte count, file name) and
  `VaultKit/cache/<sha256-of-path>.bin`. Both excluded from backups (they
  are a re-fetchable copy of vault data; the vault is their system of
  record).

### D9 — `VaultTransport`: the seam for a later iCloud bridge

```swift
public protocol VaultTransport: Sendable {
    func fetch(_ path: HubPath, ifNoneMatch: String?) async -> VaultFetchResult
    func createOnly(_ file: SealedFile) async -> VaultWriteResult
    func probe() async -> VaultProbeResult   // for "Test connection"
}
```

- Paths are **hub-relative** (`projection/projection.v1.json`,
  `events/ios-…/…`). `GitHubVaultTransport` prefixes the hub root and
  builds the API URL; a later `ICloudBridgeTransport` would map the same
  paths into the bridge folder that `add-mcp-server` D2 is proving
  (`…/hub/events/…`), and then the phone would hold no vault credential at
  all.
- `ConditionalFileSync`, `CreateOnlyFileUploader` and everything in
  TrainingCore take a `VaultTransport`. Only `VaultServices` knows it's
  GitHub.
- The allow-lists (D4) apply to hub-relative paths, so they hold for any
  transport.

### D10 — Settings → Vault and the banner

**Where**: Settings, a "Vault" row in the Data area, **only in
Garmin-connected mode** (the fiancée's standalone install never sees it,
matching the vault planning note's "the standalone install never sees
it"). Off by default. Owner may change the standalone rule (tasks 0.3).

**The screen** (`VaultSettingsView`):

1. "Connect to my vault" switch (off by default). Turning it on reveals the
   rest; turning it off stops all vault traffic and keeps the settings.
2. Repository: owner and name fields, typed in (validated with GitHub's
   naming rules; owner 1–39 of `[A-Za-z0-9-]`, name 1–100 of
   `[A-Za-z0-9._-]`), and an "Advanced" branch field (default `main`).
   Stored in `UserDefaults` under `vault.connection.v1`; never logged.
3. Token: the entry (D3), "Save token", "Remove token", and a link to
   GitHub's token page.
4. "Test connection": `probe()` → a checklist:
   - token accepted (or the loud reason);
   - repository reachable;
   - plan file found (size, last changed) or "not generated yet";
   - token expiry: "Expires in 172 days" or "Expiry unknown";
   - device id (after the first success).
5. Status: last successful sync ("12 min ago"), last problem (classified,
   localized, with its time), and later the pending-writes count (0 now).
6. "Disconnect" (D3), with a confirmation.

**Expiry countdown**: read from the expiry header on every response
(probe 1.3 confirms its name and format; tolerant parsing). At 14 days or
fewer, the banner shows "Vault token expires in N days" (plural forms). If
the header never appears, Settings says "Expiry unknown" and nothing
warns.

**The banner** (`VaultBannerView`, in `withStatusBanners()` under the
Garmin banners): shown only while the connection is **enabled** and the
status needs the user: a loud auth outcome, the token missing (e.g. after
a restore on a new phone), or expiry within 14 days. It says what happened
and "Tap to fix", opening Settings → Vault. It never shows for offline,
rate limits, server errors or "no plan data yet".

**Status model** (`VaultStatus`, pure): `enabled`, `configured`,
`hasToken`, `lastSuccessAt`, `lastOutcome`, `tokenExpiresAt`,
`rateLimitedUntil`, `pendingWrites`, and derived `needsAttention` and
`bannerReason`. Persisted in `VaultKit/status.json` (excluded from
backups). Table-tested.

### D11 — When the app talks to GitHub

- On foreground (`AppEnvironment.refreshOnForeground`), while enabled and
  not blocked by a loud outcome or `rateLimitedUntil`: one
  `ConditionalFileSync.refresh` of the projection, at most once per 60 s
  (pull-to-refresh bypasses the interval). Launched unstructured, like the
  offline-index check, so nothing on screen waits for it.
- "Test connection" on demand.
- Independent of the Garmin data mode's sync plan: the vault isn't Garmin.
- No background refresh (non-goal). No call on any confirm or save path.

### D12 — Data safety

| File (under Application Support) | Catalog id | In backups | Why |
|---|---|---|---|
| `VaultKit/device-identity.json` | `vault.device-identity` | no | A restore must never copy an id to another phone (D5) |
| `VaultKit/status.json` | `vault.status` | no | Device-local state |
| `VaultKit/fetch-cache.json` + `VaultKit/cache/*.bin` | `vault.fetch-cache` | no | Re-fetchable vault data (D8) |
| `VaultKit/write-queue.json` (lazy) | `vault.write-queue` | no | Delivery state, like the outboxes (D7) |

- `vault.connection.v1` (preferences: enabled, owner, name, branch) **is**
  in backups. After a restore on a new phone the connection is configured
  but has no token, which the banner reports ("Paste your vault token
  again").
- Each file gets a synthetic fixture in `VaultKit/Tests/VaultKitTests/
  Fixtures/Stores/` and a `StoreFixtureTests` load through the real store,
  per `docs/data-compatibility.md`.
- The store-coverage test (FoodLogCore) also scans `VaultKit/Sources`.
- Fixtures hold no real repository name, token or vault content: owner
  `example-owner`, repository `example-vault`, device `ios-0000abcd`, a
  projection body of `{"schema":"example"}`.

### D13 — Testing (all in CI, none against GitHub)

- `URLProtocol` stub (`StubURLProtocol`), injected through
  `URLSessionConfiguration.protocolClasses`: scripted responses per
  request; asserts on method, path, headers (`If-None-Match`, `Accept`,
  `Authorization` present but never logged).
- `GitHubContentsClientTests`: 200 with ETag, 304, 401, 403 with and
  without rate-limit headers, 404 repository vs 404 file, 429 with
  `Retry-After`, 5xx, offline, cross-host redirect refused.
- `VaultPathPolicyTests`: every allowed shape, every refused shape (other
  device, prefix tricks, `..`, encoded dots, backslash, uppercase id, empty,
  absolute, wrong extension, read outside `projection/`).
- `DeviceIdentityTests`: format, persistence, sequence never reused across
  a simulated crash (reserve then reload).
- `DurableQueueTests` (real store on a temp file): delivered, retry with
  backoff, auth stops without spending, offline stops without spending,
  rate limit stops the cycle, `maxAttempts` → failed, manual retry,
  quarantine of a bad file, `ensureSafeToWrite`.
- `CreateOnlyFileUploaderTests`: 201; 422 then equal SHA → delivered; 422
  then different SHA → failed permanently; 409 → retry; blob-SHA vectors
  (the empty blob is `e69de29bb2d1d6434b8b29ae775ad8c2e48c5391`).
- `ConditionalFileSyncTests`: commit only after validation; rejected ETag
  remembered; cached bytes survive a failed fetch; offline cold start.
- `VaultOutcomeTests`: the D6 table; `VaultStatusTests`: banner rules.
- `RedactionTests`: a planted token appears in no log line or error text.
- GarminKit: existing outbox tests unchanged after the `RetryBackoff`
  extraction; one test pins `RetryBackoff` to the old values.
- FoodLogCore: the secret scan catches every GitHub prefix; the catalog
  lists VaultKit's files as excluded.

## Fallbacks for external-API dependencies

GitHub's REST API is documented and versioned (`X-GitHub-Api-Version`), so
this is not a private-API dependency, but it can still fail:

- **GitHub down or unreachable**: the last good projection stays on
  screen with its age; nothing else depends on it.
- **ETag/304 not as documented**: unconditional GETs, at most once a minute
  (D2).
- **Expiry header absent or renamed**: "Expiry unknown"; the owner sets a
  calendar reminder; a `401` is still loud.
- **Direct GitHub access no longer wanted** (a leak, a policy change): the
  `VaultTransport` seam takes the iCloud bridge (`harden-vault-transport`),
  and the owner revokes the token on github.com, the documented kill
  switch.

## Risks / Trade-offs

- **The token can write anywhere in the vault.** The path policy stops the
  app's own bugs, not a thief. Mitigations: fine-grained, one repository,
  Contents only, ~180-day expiry with a countdown, `ThisDeviceOnly`
  Keychain, never exported or logged, revocation documented, and the
  planned iCloud transport. The vault side's pull guard is outside this
  repository. Stated plainly in `docs/vault-connection.md`.
- **A public repository.** Everything about the vault is typed in on the
  phone. Fixtures are synthetic. No workflow gets a vault secret, ever.
  Reviewers grep PRs for a repository-looking string and for token
  prefixes.
- **Unexercised write code** can rot before its first real use. It is
  tested against stubs in every CI run, and `add-training-checkins` starts
  with a probe of the real create-only responses.
- **GarminKit as a dependency** for four utilities. Accepted, as in
  `add-data-safety`; extraction is a later clean-up.

## Migration Plan

1. Wave 1 (VaultKit core and tests) changes no app behaviour.
2. Wave 2 adds the settings screen, off by default; nothing talks to GitHub
   until the owner turns it on and saves a token.
3. Rollback: revert the PR. The Keychain item and the `VaultKit/` files are
   ignored by older builds; the owner can remove the token from Settings
   first, or revoke it on github.com.

## Open Questions

Carried into tasks.md group 0 with proposed defaults:

1. Token lifetime: 180 days (default), 90 or 366?
2. Refuse classic `ghp_` tokens (default) or accept them with a warning?
3. Hide the Vault row on standalone installs (default), or allow it there
   too?
4. Include the connection settings (not the token) in backups (default
   yes)?
5. Let the branch be edited (default: yes, under "Advanced", so the owner
   can point the phone at a test branch with a synthetic projection)?
