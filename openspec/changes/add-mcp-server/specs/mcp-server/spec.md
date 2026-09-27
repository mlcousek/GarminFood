## ADDED Requirements

### Requirement: The server runs locally over stdio and is configured by file paths

The MCP server SHALL run as a local Node process speaking MCP over stdio,
SHALL open no network listener, and SHALL read its configuration from
environment variables: `GARMINFOOD_BRIDGE_DIR` (the PC path of the bridge
folder), `GARMIN_TOKENS` or `VAULT_ROOT` (the existing token resolution of
`tools/lib/garmin-auth.mjs`), and `GARMINFOOD_MCP_EXPERIMENTAL_WRITES`
(optional). A missing bridge folder SHALL disable bridge tools only; a
missing token SHALL disable Garmin tools only.

#### Scenario: No bridge configured

- **WHEN** the server starts without `GARMINFOOD_BRIDGE_DIR`
- **THEN** Garmin read tools work, bridge tools return "PC bridge not configured" with setup steps, and `server.status` reports both states

### Requirement: Every write tool previews first and acts only on confirm

The MCP server SHALL treat every tool that changes Garmin data or queues a
bridge command as a write tool. Called without `confirm: true`, a write
tool SHALL change nothing and SHALL return a preview: what will change,
where (Garmin now, or the phone on next app open), the exact route or
command kind, and any warning. Called with `confirm: true`, it SHALL
perform the change and return its outcome.

#### Scenario: Dry run by default

- **WHEN** Claude calls `supplement.addProduct` without `confirm`
- **THEN** no file is written to `inbox/` and the reply shows the product as it would be created and says it applies when the app next opens

#### Scenario: Confirmed write

- **WHEN** the same call is repeated with `confirm: true`
- **THEN** exactly one command file appears in `inbox/` and the reply returns its `commandId`

### Requirement: Tool inputs are validated against the shared protocol schema

The MCP server SHALL validate every tool input and every bridge command it
writes against the JSON Schema in `docs/bridge-protocol/`, SHALL reject an
invalid input with a message naming the field, and SHALL NOT write an
invalid command file.

#### Scenario: Negative dose

- **WHEN** `supplement.tick` is called with `servings: -1`
- **THEN** the tool fails with a message naming `servings`, and nothing is written

### Requirement: Command files are written atomically and never overwritten

The MCP server SHALL write each command to a temporary name that the app
ignores and rename it to `inbox/<createdAt>-<commandId>.json` only when
complete. It SHALL generate a new UUID `commandId` per confirmed call and
SHALL never modify or delete a file in `inbox/`, `results/` or `archive/`
after writing it, except that `bridge.cancel` MAY delete a command of its
own that has no result yet.

#### Scenario: Sync picks up a half-written file

- **WHEN** iCloud for Windows uploads the folder while a command is being written
- **THEN** only a `.tmp` file can be uploaded, which the app ignores, and the complete `.json` appears afterwards

### Requirement: Reads say how fresh the phone's data is

Every tool that reads from `state.json` SHALL include the snapshot's
`generatedAt` and SHALL mark the answer stale when it is older than 24
hours. Every bridge write SHALL report how many earlier commands are still
waiting without a result.

#### Scenario: Old snapshot

- **WHEN** `state.json` was generated 3 days ago and Claude calls `supplement.list`
- **THEN** the reply lists the products and says the data is from 3 days ago and that opening the app refreshes it

### Requirement: Command outcomes can be checked from the PC

The MCP server SHALL provide `bridge.status` (folder path, last snapshot
time, app version and protocol version from the snapshot, pending commands
without a result, and the last 20 results) and `bridge.result` (one
command's result by id). A command still without a result 48 hours after
it was written SHALL be listed as overdue.

#### Scenario: Rejected on the phone

- **WHEN** the app rejected a `preset.log` command because the preset had been deleted
- **THEN** `bridge.result` for that id returns status `rejected`, reason `not_found`, and the app's message

### Requirement: The tool surface covers every user action with a documented path

The MCP server SHALL offer a tool for every user action listed in the
design's feature inventory whose path is marked "Garmin-direct" or
"Bridge", and SHALL offer none for actions marked "Not offered" (sign-in,
data mode switch, backup restore, barcode scanning, app icon change). Each
tool's description SHALL say whether it acts on Garmin immediately or on
the phone at next app open.

#### Scenario: Asking for a phone-only action

- **WHEN** Claude looks for a tool to restore a backup
- **THEN** no such tool exists, and `server.status` lists restore under actions that must be done on the phone
