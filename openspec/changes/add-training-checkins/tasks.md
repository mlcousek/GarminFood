Every task ends with CI green: `swift test` for every package, the
design-token lint, the app and widget `xcodebuild`, and the `localization`
job. Every new `.swift` file starts with a header comment saying why it
exists and what depends on it. All new user-facing text is in English and
Czech. **Fixtures are synthetic** (the vault example's 2030 season ids, the
device `ios-0000beef`); never a token, the vault repository's name or real
vault data. Branch `mlcousek/add-training-checkins`, stacked on
`mlcousek/add-training-today-and-plan` (#108). Relative size: S / M / L.

## 0. Owner decisions

Each has a proposed default; unanswered ones are built as the default and
marked *defaulted, owner may override*.

- [ ] 0.1 Reminder times: morning 04:05, evening 20:10 (default) (design D8). *Defaulted, owner may override.*
- [ ] 0.2 Training reminders on by default in the training experience (default yes) (D8). *Defaulted, owner may override.*
- [ ] 0.3 Deliver 120 s after an action as well as on foreground and backgrounding (default) (D4). *Defaulted, owner may override.*
- [ ] 0.4 Event log excluded from backups (default; it lives under `VaultKit/`) (D3). *Defaulted, owner may override.*
- [ ] 0.5 RPE 1–10 only (default), or also a 1–5 feel (D6). *Defaulted, owner may override.*

## 1. Contract mirror (the vault's event contract v1, `add-hub-ingest`)

- [ ] 1.1 When the vault publishes `scripts/fixtures/hub/contract/events.v1.*.jsonl`, grep it for the owner's name, handle, real race or phase names and any token-like string, then copy it **verbatim** into `ios/TrainingCore/Tests/TrainingCoreTests/Fixtures/Contract/vault/` and record it in that folder's `CONTRACT.md` (version, date copied, source change; no vault path or repository name).
- [ ] 1.2 Reconcile `Events/HubEvent.swift` with it field by field (design D2's table: `deviceId` vs `src.device`, `payload` vs `data`, `date` vs `day`, `light` words vs letters, `habit.tick`, `session.rpe`/`session.note` names), update `events.v1.app.jsonl` and the goldens, and add a test that decodes the vault's fixture with no `.other` types for the four kinds this app writes.
- [ ] 1.3 Record each answer, dated, in design.md ("Contract details confirmed").

## 2. Event core in TrainingCore (L)

- [x] 2.1 `Events/HubEvent.swift`: envelope v1, the four payloads (the light is TrainingCore's `MorningLight`), deterministic JSONL encode, tolerant decode (`.other`), `HubEventClock`. `Events/UUIDv7.swift`.
- [x] 2.2 Synthetic golden `Fixtures/Events/events.v1.app.jsonl` (+ `README.md`); `HubEventTests`: byte-exact encode, decode round trip, unknown field and type, UUIDv7 version/variant/ordering, `at` with offset and milliseconds, RPE and note bounds.
- [x] 2.3 `Events/TrainingEventLog.swift` (PersistedJSON, durable append, mark sealed, prune sealed after 21 days, never prune unsealed); `TrainingEventLogTests` on temp files (reload from disk, quarantine of a corrupt file, prune rules).
- [x] 2.4 `Events/EventSegment.swift`: path, bytes, commit message, 500-event chunks, enqueue then mark; tests: path shape accepted by `VaultPathPolicy`, bytes equal the JSONL, a second seal finds nothing, other device's events left alone.
- [x] 2.5 `Events/CheckInOverlay.swift` (latest by `seq`, delivery state from the queue) and the `EffectivePlan` light overlay; tests.
- [x] 2.6 `Events/TrainingRecorder.swift` (`record`, `seal`, `drain`, `overlay`, `pendingCount`, `CheckInPlanning` for the day and session); tests with the in-memory transport: record without identity throws, drain delivers one segment create-only, 422 with equal content is delivered, offline keeps it queued.

## 3. View models (M)

- [x] 3.1 `TrainingSnapshot`/`TrainingSource` carry the overlay and real `TrainingCapabilities` (`.checkIns(enabled:)`).
- [x] 3.2 `TodayTrainingModel.checkIn` (`CheckInRowModel`: three buttons, selected, delivery line, VoiceOver); the morning-light highlight from the overlay; strings in both `.lproj`.
- [x] 3.3 `HabitTick.tickable(done:pending:)` from the overlay over `habitsDone`.
- [x] 3.4 `SessionDetailModel.rating` (`SessionRatingModel`: RPE, note, delivery lines).
- [x] 3.5 `TrainingReminderPlanner` (morning and evening, today and tomorrow, skip when done); tests.
- [x] 3.6 Builder tests: check-in row on a traffic-light day and a rest day, hidden without capability; highlight follows the local light; tick states; rating; Czech strings.

## 4. App (M)

- [x] 4.1 `GarminFood/Training/TrainingEventsService.swift`: the process's one `TrainingRecorder` (over `VaultServices`), the Control hook, the guard (enabled, configured, device id), change notifications.
- [x] 4.2 `TrainingModel`: overlay and capabilities into the snapshot; `checkIn`, `tickHabit`, `rate`, `saveNote` actions (local commit, then a debounced drain); drain on foreground and backgrounding from `AppEnvironment`, only when the vault request gate allows.
- [x] 4.3 Today: the check-in row in `TrainingDayCard`, the habit toggles in `HabitsTodayCard` (tokens only, letter + shape, Differentiate Without Color, one VoiceOver element per button).
- [x] 4.4 `SessionDetailView`: "How did it feel?" RPE buttons and note editor with Save.
- [x] 4.5 `Shared/MorningCheckInIntents.swift` (intent + hook, both catalogs) and `GarminFoodWidget/Controls/MorningCheckInControls.swift` (three Controls, iOS 18+), registered in the widget bundle; the hook installed in `GarminFoodApp.init()`.
- [x] 4.6 `NotificationScheduler.syncTrainingReminders` (`training.` prefix) and the "Training reminders" switch in Settings → Notifications (training experience only).
- [x] 4.7 Settings → Vault: the existing "Pending writes" row counts the events not yet uploaded (`VaultStatus.pendingWrites`, updated after every record and drain).
- [ ] 4.9 Follow-up: list failed segments in Settings → Vault with Retry (`DurableQueue.retry`); until then a failed segment waits in the queue (design D4).
- [x] 4.8 Czech for every new key; `node tools/check-localizations.mjs --scan` and `sh tools/lint-design-tokens.sh` pass.

## 5. Close-out

- [x] 5.1 `CLAUDE.md` (TrainingCore's event log) and `docs/vault-connection.md` (writes are live).
- [ ] 5.2 CI green; `openspec validate add-training-checkins --strict` passes.
- [ ] 5.3 Group 1 done (vault event fixture mirrored, envelope reconciled) before merge.

## 6. On-device verification (owner)

Against a test branch of the vault (Settings → Vault → Advanced → branch).

- [ ] 6.1 Airplane mode: tap A on Today; A is selected and "Saved on phone". Back online, foreground: "Sent"; the file appears in `events/<device id>/<yyyy>/<mm>/`.
- [ ] 6.2 Add the three Controls to the lock screen; tap Amber at night: the app opens, the check-in is recorded for the right training day; note whether Face ID was asked.
- [ ] 6.3 Tick and untick a habit, rate a session and save a note; check the segment's lines.
- [ ] 6.4 Reminders: 04:05 on a run day without a check-in; checking in first removes it; 20:10 while habits are open.
- [ ] 6.5 Revoke the token: the loud banner; events stay queued and go out after a new token.
- [ ] 6.6 The fiancée's standalone install: unchanged.
