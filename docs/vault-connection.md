# Vault connection

How the app connects to the owner's Obsidian vault on GitHub, what it can
and cannot do there, and how to create, rotate and revoke the token. The
design is `openspec/changes/add-vault-connection/` (design D1–D13); the
code is `ios/VaultKit` (the wire layer) and `ios/GarminFood/Vault` (the
screens).

This repository is public. Nothing here, in the code, in CI or in a test
fixture names the vault's repository or contains a token. The repository
is typed in on the phone.

## What the app does with GitHub

| | Path (relative to `Sport/Training/_hub` in the vault) | When |
|---|---|---|
| Reads | `projection/projection.v1.json` | On foreground, at most once a minute while the connection is on (pull to refresh skips the minute). A conditional GET: an unchanged file costs a `304` with no body. |
| Reads | the repository itself (`GET /repos/{owner}/{repo}`) | "Test connection", and once after the plan file first answers `404`, to tell "no plan yet" from "repository not found". |
| Writes | `events/<this phone's device id>/<yyyy>/<mm>/<yyyymmddThhmmssZ>-<firstSeq>.jsonl` | Since `add-training-checkins`: the training events recorded on the phone (morning check-in, habit ticks, RPE, notes; since `add-plan-editing` also plan changes -- move, swap, skip, unskip, a rule override -- and their withdrawal), sealed into one JSON Lines file per delivery, on foreground, on leaving the app and two minutes after an action. Only once "Test connection" has succeeded (the device id names the folder). Writes are create-only: an existing file is never overwritten. |

Everything else is refused before a request is built (`VaultPathPolicy`):
another phone's events folder, anything outside the hub, daily notes,
scripts, paths with `..`, encoded characters or backslashes. A refusal is
logged as an error in Settings → Diagnostics (category `vault`).

Other rules the app keeps:

- Only `https://api.github.com`. A redirect to any other host is refused,
  so the token never follows it.
- No request while the connection is off, on a standalone install, or
  after GitHub rejected the token or the repository (until you save a new
  token, fix the repository or tap "Try again").
- Rate limits (`429`, or `403` with rate-limit headers) pause all vault
  requests until GitHub's reset time. Offline and server errors are
  retried later. None of these show a banner.
- Nothing on screen ever waits for GitHub, and no food, weight or water
  entry depends on it.

## The blast radius, stated plainly

GitHub cannot limit a token to a path. A fine-grained token with
"Contents: Read and write" on the vault repository can read and write
**any file in that repository**, including scripts the desktop runs. The
app's path policy limits the app's own bugs; it does not limit someone who
steals the token. What limits that:

- the token is fine-grained, limited to **one** repository, with
  **Contents** as its only permission, and it expires;
- it lives only in this iPhone's Keychain, "after first unlock, this device
  only": not in iCloud Keychain, not in device backups, not on a restored
  phone;
- it is never logged, never in an error message, never in a snapshot or an
  exported backup (the backup scan also drops any file or preference that
  contains a GitHub token prefix: `github_pat_`, `ghp_`, `gho_`, `ghu_`,
  `ghs_`, `ghr_`);
- the vault side guards its own executable paths when it pulls (the
  vault's planning note; outside this repository's reach);
- a later change (`harden-vault-transport`) can replace direct GitHub
  access with an iCloud Drive bridge, after which the phone holds no vault
  credential at all.

If the phone is lost or the token may have leaked: **revoke it on
github.com first** (below). That is the kill switch; everything else is
secondary.

## Creating the token

On github.com: Settings → Developer settings → Personal access tokens →
**Fine-grained tokens** → Generate new token (the app's "Create a token on
GitHub" link opens this page).

1. **Token name**: something you'll recognise, e.g. "iPhone vault".
2. **Expiration**: 180 days (the app warns in its last 14 days).
3. **Resource owner**: your account.
4. **Repository access**: **Only select repositories** → the vault
   repository. Nothing else.
5. **Permissions** → Repository permissions → **Contents: Read and
   write**. Leave everything else at "No access" (Metadata: Read is added
   automatically).
6. Generate, copy the token (it starts with `github_pat_`).

Classic tokens (`ghp_…`) are refused: they can't be limited to one
repository.

## Connecting the phone

Settings → Vault (shown only on the Garmin-connected install):

1. Turn on "Connect to my vault".
2. Type the repository's owner and name (the branch is under "Advanced";
   `main` unless you point the phone at a test branch), then "Save
   repository".
3. Paste the token (the Paste button avoids the paste prompt), then "Save
   token". From then on Settings shows only its last four characters.
4. "Test connection": token accepted, repository reachable, plan file
   found (or "No plan data yet" — information, not an error), and the
   token's expiry if GitHub reports it. The first successful test creates
   this phone's device id (Settings → Vault → Details).

## Rotating the token

Before the old one expires (the banner starts 14 days before): create a new
token as above, paste it in Settings → Vault, "Save token", "Test
connection". Then delete the old token on github.com.

## Revoking and disconnecting

- **Revoke**: github.com → Settings → Developer settings → Personal access
  tokens → Fine-grained tokens → the token → Delete. The app shows "Vault
  token expired or revoked" on its next foreground and stops sending
  requests.
- **Disconnect** (Settings → Vault → Disconnect): deletes the token from
  the Keychain, clears the cached plan and the status, and turns the
  connection off. The device id is kept, so reconnecting writes into the
  same folder. Disconnecting does not revoke the token on GitHub — do both
  if the token should never work again.

## Backups

Backups (snapshots and exports) carry the connection **settings**
(`vault.connection.v1`: on/off, owner, name, branch) and nothing else:
never the token (Keychain only), never the device id, the status, the
cached plan or the write queue (`VaultKit/` is excluded). After restoring
on a new phone the connection is configured but has no token; the banner
asks you to paste it again, and the new phone gets its own device id on its
first successful test.

## Probing GitHub from the PC

`tools/probe-github-contents.mjs` records, read-only, what GitHub actually
returns (status codes, whether an ETag comes back, the 304, the expiry
header's name and format, rate-limit header names). It reads the token and
the repository only from the `VAULT_PROBE_TOKEN` and `VAULT_PROBE_REPO`
environment variables, sends only GET requests and prints no body, no token
and no repository name. Run it on your own PC, never in CI; copy what it
prints into the change's design.md "Evidence", dated.
