Every task ends with CI green: `swift test` for every package (VaultKit
included from task 2.1), the design-token lint, the app and widget
`xcodebuild`, and the `localization` job. Every new `.swift` file starts
with a header comment saying why it exists and what depends on it. All new
user-facing text is in English and Czech (plural forms for counts).
**Nothing in this repository, its CI or its fixtures may contain a token,
the vault repository's name or real vault data**: fixtures use
`example-owner/example-vault` and synthetic content. Branch
`mlcousek/add-vault-connection-wN`, one PR per wave. Relative size: S / M /
L. Built in parallel with `rebrand-to-jirkas-arc`.

## 0. Owner decisions (before wave 3)

Each has a proposed default; unanswered ones are built as the default and
marked *defaulted, owner may override*.

- [x] 0.1 Token lifetime: 180 days (default), 90 or 366 (design D3). *Owner accepted the default (Decisions Log A26, 2026-09-28).*
- [x] 0.2 Refuse classic `ghp_` tokens (default) or accept them with a warning (D3). *Owner accepted the default (Decisions Log A26, 2026-09-28).*
- [x] 0.3 Vault row hidden on standalone installs (default) or shown in both modes (D10). *Owner accepted the default (Decisions Log A26, 2026-09-28).*
- [x] 0.4 Connection settings (not the token) included in backups (default yes) (D12). *Owner accepted the default (Decisions Log A26, 2026-09-28).*
- [x] 0.5 Branch editable under "Advanced" (default yes, for a synthetic test branch) (D10). *Owner accepted the default (Decisions Log A26, 2026-09-28).*

## 1. Probes (owner's PC, read-only, before wave 3)

- [x] 1.1 `tools/probe-github-contents.mjs`: GET-only; reads the token from `VAULT_PROBE_TOKEN` and the repository from `VAULT_PROBE_REPO` (never from a file in this repository); prints status codes, header names and selected header values (`etag` present?, expiry, rate-limit names) and byte counts; never prints a body, the token or the repository name. Header comment explains why and how. Refuses to run without both variables. *Built 2026-09-28; refuses to run without both variables (checked). Not run: needs the owner's token (1.2-1.4).*
- [ ] 1.2 Run it: `GET /repos/{o}/{r}` (expect 200), the projection path with `Accept: application/vnd.github.raw+json` (200, or 404 if the vault hasn't generated it yet — then probe any small committed file under the hub root instead), then the same with `If-None-Match: <etag>` (expect 304). Record in design.md Evidence, dated: status codes, whether `ETag` came back on the raw response, whether the 304 lowered `x-ratelimit-remaining`.
- [ ] 1.3 Record the token-expiry header's exact name and date format from the same responses (or "absent"), and the rate-limit header names. Update D10's parser note if they differ.
- [ ] 1.4 Probe a 404 for a repository name that doesn't exist and a 401 with a deliberately wrong token (not the real token altered in the repository; typed in the shell). Record both.

## 2. Wave 1 — VaultKit core, no app change (L)

- [x] 2.1 `ios/VaultKit/Package.swift` (swift-tools 5.10, iOS 17 + macOS 14 like GarminKit, depends on GarminKit, test target with `exclude: ["Fixtures"]`); `build.yml` step "Run VaultKit unit tests"; `project.yml` package entry (app target dependency only, not the widget).
- [x] 2.2 GarminKit: public `RetryBackoff.delay(attempt:jitter:base:cap:)`; `Outbox`, `WeightOutbox`, `HydrationOutbox` call it. Existing tests unchanged; one new test pins it to the previous formula.
- [x] 2.3 `VaultRepository` (validation), `HubPath` (normalisation), `VaultPathPolicy` (write and read allow-lists). Tests: every allowed and refused shape in design D4.
- [x] 2.4 `VaultOutcome.classify` and `VaultStatus` (D6, D10). Table tests for every row, banner rules, rate-limit persistence.
- [x] 2.5 `GitHubContentsAPI` + `GitHubContentsClient` (ephemeral session, no URL cache, 20 s timeout, same-host redirects only, API version header, policy checked before any request). `StubURLProtocol` test helper. Tests: 200 + ETag, 304, 401, 403 ± rate-limit headers, 404 repository vs file, 429 + `Retry-After`, 5xx, offline, cross-host redirect refused, refused path sends nothing.
- [x] 2.6 `VaultTokenStore` (Keychain, service `com.mlcousek.garminfood.vault`, `AfterFirstUnlockThisDeviceOnly`, no access group; test seam for a test service name); prefix check (`github_pat_` only per 0.2). Tests where the Keychain is available on the macOS runner; the prefix check always.
- [x] 2.7 `DeviceIdentity` store (`VaultKit/device-identity.json`, `PersistedJSON`, `ensureSafeToWrite`). Tests: format, persistence, `reserveSequence` never reuses after a simulated crash, quarantine of a bad file.
- [x] 2.8 `DurableQueue<Record>` + `DurableQueueDelivering` (D7). Tests with a real store on a temp file: delivered, retry/backoff, auth and offline stop without spending, rate limit stops the cycle, `maxAttempts` → failed, manual retry, `isDraining` guard, quarantine, lazy file creation.
- [x] 2.9 `SealedFile`, git blob SHA, `CreateOnlyFileUploader` (201; 422 + equal SHA; 422 + different SHA; 409). Tests including the empty-blob vector.
- [x] 2.10 `ConditionalFileSync` (commit after validation, rejected ETag, cached bytes, fetch metadata file + `cache/*.bin`). Tests.
- [x] 2.11 `VaultTransport` + `GitHubVaultTransport` (hub-relative paths, `probe()` = repository GET + projection GET). An in-memory transport in the test target; `ConditionalFileSync` and the uploader tested over both.
- [x] 2.12 `RedactionTests`: a planted token in every failure path; no `DiagnosticsLog` line or error description contains it.
- [x] 2.13 Store fixtures for `device-identity.json`, `status.json`, `fetch-cache.json`, `write-queue.json` (synthetic) + `StoreFixtureTests`.

## 3. Wave 2 — Data safety integration (S)

- [x] 3.1 FoodLogCore `StoreCatalog`: the four VaultKit entries, `inBackup: false` (D12); `BackupExclusions` for `VaultKit/`; the store-coverage test also scans `ios/VaultKit/Sources`.
- [x] 3.2 `BackupSecretPolicy`: GitHub token prefixes. Tests: a planted `github_pat_…` in a preference, in a store file and in a custom food name is caught; the export and the snapshot contain none of them.
- [x] 3.3 `vault.connection.v1` included in the preferences backup; test that a restore brings it back without a token.

## 4. Wave 3 — App: settings, banner, foreground fetch (M)

- [x] 4.1 `GarminFood/Vault/VaultServices.swift`: app-only composition root (token store, client, transport, device identity, fetch sync, status), one instance per process; the widget never links VaultKit.
- [x] 4.2 `VaultSettingsView` (D10): switch, owner/name/branch, token entry with `PasteButton`, Save/Remove, "Test connection" checklist, status, expiry countdown, device id under Details, Disconnect with confirmation, help text and a link to GitHub's token page. Shown from Settings only in Garmin-connected mode (per 0.3).
- [x] 4.3 `VaultErrorPresentation`: every `VaultOutcome` and banner reason → localized text (plurals for "N days").
- [x] 4.4 `VaultBannerView` in `withStatusBanners()` under the Garmin banners; only while enabled and `needsAttention`; opens Settings → Vault.
- [x] 4.5 `AppEnvironment.refreshOnForeground`: unstructured `ConditionalFileSync.refresh` of `projection/projection.v1.json` while enabled and not blocked, at most once per 60 s; pull to refresh bypasses the interval. Minimal validator (JSON object, ≤ 5 MB) until `add-training-today-and-plan`.
- [x] 4.6 `DiagnosticsLog` category `vault`: fetch outcomes (status, hub-relative path, byte count), never the token, owner or repository name.
- [x] 4.7 `docs/vault-connection.md`: creating the fine-grained token (one repository, Contents read/write, 180 days), what the app reads and writes, the path policy, the blast radius stated plainly, how to revoke, how to rotate. No repository name.
- [x] 4.8 `CLAUDE.md` architecture section: VaultKit's role and its boundary rule.
- [x] 4.9 Czech strings for every new key; `node tools/check-localizations.mjs --scan` passes; `sh tools/lint-design-tokens.sh` passes. *`--scan` and the lint pass locally (2026-09-28).*

## 5. Close-out

- [ ] 5.1 CI green on every wave PR; `openspec validate add-vault-connection --strict` passes.
- [x] 5.2 PR review checklist: grep the diff for token prefixes and for anything that looks like the vault's repository name; both empty. *Done on the branch diff 2026-09-28: no token-shaped literal (test tokens are assembled at run time), no vault repository name; fixtures use `example-owner/example-vault`.*

## 6. On-device verification (owner)

- [ ] 6.1 Create the fine-grained token per `docs/vault-connection.md`. Settings → Vault: enter owner/name, paste the token, Test connection: token accepted, repository reachable, plan file found (or "not generated yet"), expiry shown or "unknown". Record what the expiry line showed.
- [ ] 6.2 Foreground twice a minute apart: Diagnostics shows one 200 then 304s (`vault` category), no token or repository name in any line.
- [ ] 6.3 Airplane mode, foreground: no banner; Settings keeps the last sync time.
- [ ] 6.4 Save a wrong token: loud banner on every tab; tapping it opens Settings → Vault; no request on the next foreground. Save the right token: the banner clears after Test connection.
- [ ] 6.5 Export a backup and search it for `github_pat_`: none. Settings → Data snapshot list unchanged in behaviour.
- [ ] 6.6 Disconnect: token gone (Test connection now says no token), no vault traffic on the next foreground.
- [ ] 6.7 The fiancée's standalone install: no Vault row, no GitHub traffic.

## Implementation notes (2026-09-28)

- Built on `mlcousek/add-vault-connection` as one branch instead of one per
  wave; the commits follow the waves (GarminKit `RetryBackoff`, VaultKit,
  data safety, app, docs). CI has not run yet (5.1): nothing here was
  compiled locally (no Mac).
- `VaultSyncCoordinator` (VaultKit) holds the D6/D11 orchestration -- gate,
  60 s interval, the repository GET after a first file 404, "Test
  connection" creating the device id -- so the app's `VaultController` is
  only state and taps, and every rule is tested in `swift test`.
- The token-expiry header is parsed tolerantly (`TokenExpiryParser`); its
  exact name and format are still "documented, not observed" until 1.3.
- The create-only idempotency check compares the git blob SHA of the bytes
  a raw GET returns (works for any transport) rather than reading the
  `sha` field of the JSON media type.
- `BackupSecretPolicy` counts a GitHub prefix as a token only at a word
  boundary (or after a JSON escape) and with at least 16 token characters
  after it, so words like `thighs_...` never drop a store from a backup.

