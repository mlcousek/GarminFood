# Event fixtures (app side, synthetic)

- **What:** `events.v1.app.jsonl` -- seven events in the envelope v1 this app
  writes (`add-training-checkins` design D2): two morning check-ins for the
  same day (the later one wins), two habit ticks (on, off), an RPE and a
  note for one session, and a rest-day check-in without a session.
- **Synthetic:** the session and habit ids come from the vault's synthetic
  2030 example season (`../Contract/vault/projection.v1.example.json`); the
  device id `ios-0000beef` and every id are made up. No real names, dates or
  data.
- **Golden:** `HubEventTests` encodes the same events and compares the bytes
  with this file exactly (sorted keys, unescaped slashes, `\n` after every
  line, LF only -- see `.gitattributes`), and decodes it back.
- **`plan-commands.v1.app.jsonl`** (add-plan-editing design D2): seven
  plan commands and a retraction in the same envelope -- a move, a swap,
  a skip with a reason and one without, an unskip, a rule override, and
  the retraction of the reasonless skip. Same ids and device, same
  byte-exact rule. `JSONEncoder`'s sorted keys compare case-insensitively
  on Apple platforms, which is why a swap's payload reads `a, aDate, b,
  baseRevision, bDate, week`.
- **Checked against the vault:** the vault's event contract v1
  (`add-hub-ingest`) validator accepts every line (2026-09-29; the plan
  commands on 2026-09-30, with the validator of the vault's main branch). Its own
  fixtures are mirrored verbatim in `../Contract/vault/`. When the vault
  changes the contract, reconcile `Events/HubEvent.swift` and regenerate
  this file.
