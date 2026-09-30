Every task ends with CI green: `swift test` for every package, the
design-token lint, the app and widget `xcodebuild`, and the `localization`
job. Every new `.swift` file starts with a header comment saying why it
exists and what depends on it. All new user-facing text is in English and
Czech. **Fixtures are synthetic** (the vault example's 2030 season ids, the
device `ios-0000beef`); never a token, the vault repository's name or real
vault data. Branch `mlcousek/add-plan-editing`, on `main` `362e385`.
Relative size: S / M / L.

## 0. Owner decisions

Each has a proposed default; unanswered ones are built as the default and
marked *defaulted, owner may override*.

- [ ] 0.1 While a command on a session is pending, only Withdraw is offered for that session (default) (design D3). *Defaulted, owner may override.*
- [ ] 0.2 Skip is not offered for a done session (default) (D3). *Defaulted, owner may override.*
- [ ] 0.3 Withdraw is offered for pending commands and applied rule overrides only; an applied move/swap/skip is undone by a new command (default) (D3). *Defaulted, owner may override.*
- [ ] 0.4 Skip reason optional, free text up to 2000 characters (default) (D2). *Defaulted, owner may override.*
- [ ] 0.5 Plan edits are delivered on the check-ins' 120 s debounce, foreground and backgrounding (default) (D6). *Defaulted, owner may override.*

## 1. Contract (S)

- [x] 1.1 Re-read the vault's merged `add-hub-ingest` (event log v1, plan-edits spec, D8-D10, A17/A48/A50) and confirm the mirrored `events.v1.example.jsonl` is current (23 events; seq 16 the refused race move, seq 23 superseded). *2026-09-30: unchanged since the last mirror; no re-mirror needed.*

## 2. Wire format (M)

- [x] 2.1 `Events/HubEvent.swift`: the six payloads (moved, swapped, skipped, unskipped, rule overridden, retracted), typed decode, deterministic encode with `reason` as `null`, validation (D2).
- [x] 2.2 Synthetic golden `Fixtures/Events/plan-commands.v1.app.jsonl` (+ README); `HubEventTests`: byte-exact encode, decode back, every command and retraction line of the vault's example re-encodes to the same JSON object, `device.hello` still `.other`, bounds.
- [x] 2.3 `CheckInOverlay.fold` ignores commands and retractions.

## 3. Pending overlay and policy (L)

- [x] 3.1 `Events/PlanCommandOverlay.swift`: `PlanOutcome` parsed from `outcomes[]`; `PendingOverlay.fold` (status order of D4); `applying(to:)` (preview of D5); `TrainingRecorder.planEdits(acks:outcomes:)`.
- [x] 3.2 `Events/PlanEditPolicy.swift`: `options(for:)` and the builders (move, swap, skip, unskip, override, withdraw) with D3's rules; `PlanEditError`.
- [x] 3.3 `TrainingSnapshot`/`EffectivePlan`/`TrainingSource` carry the overlay; `TrainingCapabilities.recording(enabled:)`.
- [x] 3.4 `ViewModels/PlanEditModels.swift`: `SessionEditModel` (actions, status line, reason, why not), `PlanChangeLineModel`; `SessionDetailModel.editing`, `SessionRowModel.pendingText`, `WeekAgendaModel.planChanges`, `SessionCardModel.pendingBadge`; strings in both `.lproj` tables and `TrainingKey`.
- [x] 3.5 `PlanEditingTests` on the vault's example: move targets on the week of `asOf`, race refused (options, builders, swap partners), past days, done sessions, revision, stacked edits; fold statuses (pending saved/sent, withdrawing, received, each outcome with its reason in both languages, unknown status); preview of move, swap, skip, unskip, override; recorder round trip with the in-memory transport; Czech strings.

## 4. App (M)

- [x] 4.1 `TrainingModel`: the plan overlay into the snapshot (acks and outcomes of the cached projection), `recording(enabled:)`, actions `move`, `swap`, `skip`, `unskip`, `overrideRule`, `withdraw` through `PlanEditPolicy` and the existing recorder.
- [x] 4.2 `SessionDetailView`: the "Change the plan" card -- status and reason, Move and Swap as confirmation dialogs, Skip with an optional reason, Unskip, the A17 override alert, Withdraw.
- [x] 4.3 `WeekAgendaView`: the pending / not-applied badge on session rows; the week's plan changes with Withdraw. Today's session card shows `pendingBadge`.
- [x] 4.4 Czech for every new key; `node tools/check-localizations.mjs --scan` and `sh tools/lint-design-tokens.sh` pass.

## 5. Close-out

- [x] 5.1 `CLAUDE.md` (TrainingCore's plan edits) updated.
- [ ] 5.2 CI green; `openspec validate add-plan-editing --strict` passes. *Validate passes locally; CI not run (no push yet).*

## 6. On-device verification (owner)

Against a test branch of the vault (Settings -> Vault -> Advanced -> branch).

- [ ] 6.1 Airplane mode: move a future session to another day of the week; it shows there, "Pending · Saved on phone". Online and foreground: "Sent"; after the desk's ingest and a projection refresh: "Applied", the session where it was moved, "Moved from ...".
- [ ] 6.2 The race session offers no Move/Swap/Skip and says why; it is not a swap partner.
- [ ] 6.3 Skip with a reason, then Withdraw before the desk runs: the session is planned again; the outcome later reads "Withdrawn".
- [ ] 6.4 After two ambers, Override the rule: the warning appears; after ingest the session has its options back; Withdraw the override restores the ride-only option.
- [ ] 6.5 Force a refusal (move a session, then have the desk re-plan the week before ingest): "Not applied" with the vault's reason, in Czech with the app in Czech.
- [ ] 6.6 Food-first and the fiancée's standalone install: unchanged.
