## Why

The owner's training plan lives in his private Obsidian vault, a git
repository on GitHub, and the vault is its source of truth (his decision
A1, 2026-09-28). The app is to become the phone side of that plan (A2) and
connects **directly to the vault's GitHub repository** for now, with
hardening later (A3). Every write is designed so that each file has
exactly one writer, which makes sync conflicts impossible by construction
(A4).

The vault side publishes one generated file for the app to read, a
**projection** (`projection.v1.json`, one JSON document with the plan
window, habits and acknowledgements), and will ingest **event files** the
app writes into its own folder. The planning note behind this is the
vault's training-hub architecture note, sections 2 to 3 and 9. What the
app needs first is the wire layer: a way to hold a GitHub token safely,
read that one file cheaply and without ever waiting on the network, and
(designed now, used later) write immutable files into its own folder and
nowhere else.

Three constraints shape it:

- **This repository is public.** Its CI logs and `.ipa` artifacts are
  public too. No token, vault repository name or vault content may ever be
  compiled in, logged, committed or used in CI. The repository to connect
  to is typed in on the phone.
- **The token is powerful.** GitHub fine-grained tokens can't be limited
  to a path. A token that can write the vault can write anything in it,
  including scripts the desktop runs. The app must keep the token out of
  every backup, export and log, and write only where the design allows.
- **The house rules apply**: local-first (the network is never awaited on a
  user action), auth failures are loud, everything else degrades quietly,
  rate limits are honoured, and all logic that can be tested lives in an
  SPM package that CI tests.

Garmin's outbox pattern already exists three times (food, weight,
hydration). A fourth copy for vault writes would be one too many; this
change builds one generic durable queue instead.

## What Changes

- **New SPM package `VaultKit`**: the GitHub wire layer. It holds no
  training concepts, the same boundary `GarminKit` keeps for food.
  - `GitHubContentsClient` behind a protocol: conditional GET of a file
    (`If-None-Match` with the stored ETag, `304` when unchanged) and a
    create-only PUT, over an ephemeral `URLSession` that refuses redirects
    to other hosts.
  - `VaultTokenStore`: the fine-grained token in the Keychain, own service
    name, `AfterFirstUnlockThisDeviceOnly`, default access group. Never
    logged, never in a backup or export, never shown back in full.
  - `VaultPathPolicy`: a pure allow-list. The app may write only under
    `Sport/Training/_hub/events/<ownDeviceId>/` and read only the
    projection files and its own event folder. Enforced inside the client,
    so no caller can get around it.
  - `DeviceIdentity`: an `ios-<8 hex>` id and a persisted sequence counter,
    created on the first connection, stored in the app container, never
    restored from a backup.
  - `DurableQueue<Record>`: a generic, durable, per-process queue with the
    proven outbox semantics (capped backoff, rate limit stops the cycle,
    auth failure stops it without spending attempts, a re-entrancy guard,
    visible failures) plus a `CreateOnlyFileUploader` that makes a
    create-only upload idempotent by comparing git blob SHAs. **Designed
    and tested now; nothing enqueues in production until
    `add-training-checkins`.**
  - `ConditionalFileSync`: fetches a file and stores its bytes and ETag
    only after the caller's validator accepts them, so a bad file never
    replaces the last good one.
  - `VaultTransport`: the seam between the domain and the wire. The GitHub
    implementation is the only one now; the iCloud Drive bridge that
    `add-mcp-server` is proving can replace it later without touching
    training code.
  - Error classification mirroring `DrainAuthOutcome`: `401`, `403`
    without rate-limit headers and a `404` repository are **loud**; `429`
    or `403` with rate-limit headers are a quiet backoff honouring
    `Retry-After`/`x-ratelimit-reset`; network and `5xx` are quiet
    retries.
- **Settings → Vault** (Garmin-connected installs only; never shown in
  standalone mode; off by default): an on/off switch; repository owner,
  name and branch typed in; paste the token; "Test connection"; last
  sync; token expiry countdown; disconnect. Help text explains how to make
  a fine-grained token limited to one repository with Contents
  read/write.
- **Loud vault banner** on every tab, beside the Garmin banners, when an
  enabled connection needs the user: token rejected, repository not
  found, token expiring within 14 days, or a token is missing after a
  restore.
- **Foreground refresh**: while enabled, each foreground (at most once a
  minute unless pulled to refresh) does one conditional GET of the
  projection, off the main actor, never blocking anything on screen.
- **Data safety**: new store files get fixtures and catalog entries; the
  device identity, the fetch cache and the write queue are excluded from
  snapshots and exports; the secret scan learns GitHub token prefixes.
- **CI**: a `swift test` step for VaultKit; every HTTP behaviour tested
  through a `URLProtocol` stub. No test and no workflow ever touches
  GitHub's real API or holds a vault token.
- All new text in English and Czech.

## Capabilities

### New Capabilities

- `vault-connection`: the user-facing connection (settings, token
  handling, test, status, loud and quiet failures, disconnect,
  availability per data mode).
- `vault-transport`: the wire rules (conditional fetch, path allow-lists,
  device identity, durable create-only writes, the transport seam, what
  backups contain).

### Modified Capabilities

None. `add-data-safety`'s `data-safety` requirements already cover new
stores ("every persisted store format is proven readable in CI", "backups
never contain secrets"); this change adds catalog entries, fixtures and
exclusions under them without changing their behaviour.

## Non-goals

- **Any training concept**: projection models, event types, screens. Owned
  by `add-training-today-and-plan` (reading) and `add-training-checkins`
  (writing events).
- **Writing to the vault in production.** The create-only upload and the
  queue exist and are tested with stubs; the first real write, and the
  probe that records GitHub's create-only responses, belong to
  `add-training-checkins`.
- **Plan editing commands.** Owned by `add-plan-editing`.
- **The iCloud Drive transport.** Owned by a later `harden-vault-transport`,
  after `add-mcp-server` proves the bridge folder on a free account.
- **Background refresh** (`BGAppRefresh`) of the projection. Foreground
  only for now; a later change can add it once there is something worth
  refreshing in the background.
- **Migrating the Garmin food, weight and hydration outboxes** onto
  `DurableQueue`. Their on-disk formats are pinned by data-safety fixtures;
  touching them is its own change, if ever.
- **A vault connection on standalone installs.** The fiancée's install
  never sees it (tasks 0.3 lets the owner change that later).
- **Any GitHub Actions secret or integration test against a real vault.**
  Forbidden by design: the repository is public.

## Impact

- New `ios/VaultKit/` package (`Package.swift`, sources, tests, store
  fixtures). Depends on `GarminKit` only, for `PersistedJSON`,
  `DiagnosticsLog` and the backoff helper.
- `GarminKit`: the existing outbox backoff calculation made public as
  `RetryBackoff` (behaviour-preserving; existing tests unchanged).
- `FoodLogCore/Backup/`: `StoreCatalog` entries and `BackupExclusions` for
  VaultKit's files; `BackupSecretPolicy` scans for `github_pat_`, `ghp_`,
  `gho_`, `ghu_`, `ghs_`, `ghr_`; the store-coverage test also scans
  VaultKit's sources.
- App (app target only, never the widget): `GarminFood/Vault/`
  (`VaultServices` composition root, `VaultSettingsView`,
  `VaultBannerView`, `VaultErrorPresentation`), one Settings row, one line
  in `withStatusBanners()`, one call in `AppEnvironment.refreshOnForeground`.
- `ios/project.yml`: the `VaultKit` package, a dependency of the app target
  only.
- `.github/workflows/build.yml`: "Run VaultKit unit tests".
- `tools/check-localizations.mjs`: no change (VaultKit has no user-facing
  strings; the app maps its typed errors to localized text).
- New `tools/probe-github-contents.mjs` (GET-only, reads the token and the
  repository from environment variables, prints status codes and header
  names only) and `docs/vault-connection.md` (how to create the token,
  what the app can and cannot do with it). Neither names the vault.

**Depends on**: nothing unshipped. `add-data-safety` (merged) for the
store contract, fixtures and exclusions.

**Parallel with**: `rebrand-to-jirkas-arc`.

**Unblocks**: `add-training-today-and-plan` (reads the projection through
`VaultTransport`), then `add-training-checkins` (first production writes
through `DurableQueue`), `add-plan-editing`, and the later
`harden-vault-transport`.
