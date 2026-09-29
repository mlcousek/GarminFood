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
- **Provisional:** written before the vault's event contract v1
  (`add-hub-ingest`) published its fixture. When it does, mirror the vault's
  file verbatim into `../Contract/vault/`, reconcile `Events/HubEvent.swift`
  and regenerate this file (tasks group 1).
