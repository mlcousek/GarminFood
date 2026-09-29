# GarminFood (the app is "Jirka's Arc")

**Naming.** The app is called **Jirka's Arc** (repository, targets and
identifiers still named GarminFood) since `rebrand-to-jirkas-arc`: only the
display name (`APP_DISPLAY_NAME` in `ios/project.yml`), the icon and
user-facing text say "Jirka's Arc". Bundle ids, the `garminfood` URL scheme,
Keychain services, the BG task id, store paths, the backup marker, theme-code
prefix, alternate icon names, layout card ids, Swift type names and every
path in this file keep "GarminFood" -- a new bundle id on a free Personal
Team is a new app with an empty container. Rule for new code: identifiers
and storage say GarminFood; user-facing text says Jirka's Arc (ASCII
apostrophe, the same in Czech).

**Two experiences** (AppearanceKit `AppExperience`/`AppShell`): food-first
(Today, Progress, Profile -- the default and the only one without a vault
connection) and training (Today, Plan, Progress, Profile). `AppShell` is the
single source of the tab set, the start tab and route targets.

A personal iOS food-tracking app (Jiří's own Garmin account) — fast logging, a
streak, levels, challenges — with Garmin Connect as the system of record,
since Garmin has no public write API for nutrition. Talks to Garmin's private
mobile API (`connectapi.garmin.com`), which is undocumented and unversioned.
Personal-use interop with the owner's own account/data only.

## Read first

- [`openspec/config.yaml`](openspec/config.yaml) — hard constraints, ground
  truth from live-probing Garmin's API, conventions, Design & UX principles.
  This is the actual source of truth; treat it as more current than this file
  for anything it covers.
- [`README.md`](README.md) — the OpenSpec change list and what's verified vs
  not. Partially stale (references screens/files renamed or removed since it
  was written — e.g. the home screen is now `Today/TodayView.swift`, not
  `Home/TodayHeroView.swift`) — prefer reading actual code over this file.
- [`docs/garmin-food-log-contract.md`](docs/garmin-food-log-contract.md) and
  [`docs/garmin-routes.json`](docs/garmin-routes.json) — the private-API route
  registry, each entry dated with when it was last confirmed working.

## Hard constraints (do not violate)

- **No Mac.** Swift cannot be built or tested on this Windows machine — no
  `swift`/`xcodebuild` locally. All verification happens in CI
  (`.github/workflows/build.yml`, hosted macOS runners) after pushing a
  branch/PR, or by sideloading a build to a real iPhone via AltServer/
  AltStore. Write code carefully (it can't be locally compiled first); lean
  on `swift test` in CI for the pure-logic packages.
- **Free Apple Developer account, no paid team.** No App Groups, no Keychain
  Sharing (confirmed blocked, `errSecMissingEntitlement`), no Push/iCloud/
  HealthKit. Every process (app, widget extension) bootstraps its own Garmin
  login independently — there is no shared state between them.
- **Garmin's private API can break without notice.** Every route this project
  depends on is recorded in `docs/garmin-routes.json` with a last-verified
  date. A new dependency on an unconfirmed route must be clearly marked as
  such in code comments and gated behind explicit user action if it writes
  data (see `GarminClient.createCustomFood`'s doc comment for the pattern).
- **Local-first, zero-network-wait.** A logged entry is durably committed to
  a local outbox file and shown to the user immediately; Garmin delivery
  happens after, via `Outbox.drain`, never blocking the confirm action. Don't
  add a network `await` to any confirm/save path that today completes purely
  from local state.
- **Auth failures are loud; everything else degrades quietly.** Silent auth
  failure is a real incident this project already had once (the Obsidian
  vault's sync). A failed delivery/retry must surface to the user somewhere
  (see `SyncQueueView`).

## Architecture

```
ios/
  GarminKit/       SPM package — OAuth1 signing, token bootstrap, GarminClient
                    (the wire layer), Outbox (durable local queue),
                    Reconciliation. No UI, no domain concepts like "meal".
  FoodLogCore/      SPM package (depends on GarminKit) — the domain layer:
                    Food/Serving, CustomFood, MealDashboard (Today screen's
                    data), LogEntryCoordinator (the confirm-and-commit
                    action), UsageHistory/ServingDefaults (quick-pick
                    ranking, remembered servings), FoodSearchEngine (one
                    ranked, Czech-aware search over your own foods, Garmin
                    and Open Food Facts: SearchText/CzechLightStemmer/
                    SearchRanker/SearchDedup; Local/Garmin/OpenFoodFacts
                    sources; golden suite in SearchRelevanceTests),
                    OpenFoodFactsClient, and the offline Czech OFF index
                    (OfflineFoodIndex/OfflineCzechIndexSource/
                    OfflineIndexStore; built weekly by
                    tools/build-czech-food-index + food-index.yml).
  Gamification/     SPM package (depends on FoodLogCore) — streaks, XP/levels,
                    daily/rotating challenges, achievements. App-only, not
                    linked into the widget extension.
  VaultKit/         SPM package (depends on GarminKit) — the GitHub wire layer
                    to the owner's Obsidian vault (add-vault-connection):
                    fine-grained token in the Keychain, VaultPathPolicy
                    allow-lists, conditional fetch (ConditionalFileSync),
                    generic DurableQueue + create-only uploads, and the
                    VaultTransport seam. No training concepts, no
                    user-facing strings. App-only, never the widget.
  TrainingCore/     SPM package (depends on VaultKit, GarminKit) — the
                    training domain (add-training-today-and-plan): tolerant
                    decoding of the vault's projection v1 (OpenEnum,
                    LossyArray, LocalizedText, LocalDate/ISOWeek), the last
                    good plan and its freshness (ProjectionStore), the
                    training day, and pure view models + formatters for
                    Today's training cards and the Plan tab, in English and
                    Czech (lproj via TrainingText/TrainingKey). Golden-tested
                    on the vault's two contract fixtures, mirrored verbatim
                    under Tests/.../Fixtures/Contract/vault. Never SwiftUI.
                    App-only, never the widget.
  GarminFood/       The app target (SwiftUI views), organized by screen:
                    Today/, Plan/, Training/, Catalog/, CustomFood/,
                    LogEntry/, Profile/, Progress/, App/ (composition root:
                    AppEnvironment.swift).
  GarminFoodWidget/ Widget/Control extension target — static "open the app"
                    surfaces only; cannot show live data (no shared state,
                    see Hard constraints).
  Shared/           Compiled into BOTH the app and widget extension targets
                    (App Intents that must be nameable from a Control, plus
                    AppServices.swift — the one-instance-per-store
                    composition root both processes share within themselves).
  project.yml       XcodeGen manifest — the source of truth for the Xcode
                    project. Sources are path-globbed per target, so a new
                    .swift file dropped into an existing target's folder is
                    picked up automatically; no project file to hand-edit.
```

Module boundary rule: UI (`GarminFood/`) never talks to `GarminKit` directly
for anything domain-shaped — it goes through `FoodLogCore` (e.g.
`LogEntryCoordinator`, not `Outbox`, from a view). `FoodLogCore` never imports
SwiftUI.

VaultKit keeps the same boundary for the vault: it knows GitHub's contents
API and nothing about sessions or plans. Everything above it depends on
`VaultTransport` (hub-relative paths), never on `GitHubContentsClient`;
only `GarminFood/Vault/VaultServices.swift` knows the transport is GitHub.
Every vault request goes through `VaultPathPolicy` first, and nothing may
log the token, the repository owner or its name (`VaultLog`,
`RedactionTests`). This repository is public: no vault repository name,
token or vault content in code, CI or fixtures. See
`docs/vault-connection.md`.

TrainingCore sits on top: the app's views reach the plan only through it
(`GarminFood/Training/TrainingModel.swift` holds its `TrainingSource`,
views draw its builders' models), never through VaultKit. **The phone never
computes what the vault computes** -- adherence, weekly volume (`actual`),
matching activities to sessions, the done option, gate status: all are
read from the projection. The training experience turns on with the vault
connection switch (on a Garmin-connected install); the food-first
experience has no training card at all.

`AppServices.swift` (`Shared/`) holds the one real instance of every JSON-file
store per process; `AppEnvironment.swift` (`GarminFood/App/`) is the SwiftUI
composition root that exposes them via `.environment(_:)`. Add a new store
there, not as a fresh instance inside a view.

Two smaller cross-cutting pieces worth knowing about:
- `GarminKit/DiagnosticsLog.swift` — a persistent, capped, in-app-visible
  log (viewable/copyable from Settings → Diagnostics). This exists because
  there's no Mac to attach a debugger or Console.app to; log real errors
  here (`DiagnosticsLog.log(.error, category:, "...")`), not just a generic
  user-facing message. Already wired into `GarminClient`'s two choke points
  and `Outbox.drain` — extend from there rather than adding new logging
  infra.
- `NotificationScheduler`/`NotificationPreferencesStore` (`GarminFood/App/`)
  + `FoodLogCore/NotificationPlanning.swift` — local reminders (meals,
  streak-at-risk, daily challenges), each re-planned fresh on every
  foreground/log/setting-change and diffed against what's actually pending,
  because a local notification can't check app state at fire time on its
  own. See `openspec/changes/add-reminders-and-diagnostics/design.md` for
  why.

## Conventions

- **OpenSpec.** Larger changes are planned under `openspec/changes/<name>/`
  (proposal.md, design.md, specs/, tasks.md) before/while being built, then
  archived to `openspec/changes/archive/`. Not every small fix goes through
  this ceremony (see the git log for plenty of direct bug-fix commits), but a
  new capability generally should, especially one with an unconfirmed Garmin
  route or real architectural surface.
- **Feature branches + PRs into `main`.** `git log --oneline` shows the
  pattern: `mlcousek/<change-name>` branches, merged via PR, CI green before
  merge.
- **Every `.swift` file starts with a header comment** explaining *why* it
  exists and what it depends on/is depended on by — not what the code
  obviously does. Match this style in new files; it's load-bearing given no
  local Xcode/Instruments to rediscover context by exploring interactively.
- **Pure logic lives in the SPM packages and is unit-tested there** (fast,
  runs in CI with no simulator). UI code in `GarminFood/`/`GarminFoodWidget/`
  is not unit-tested (no local way to run XCTest against it meaningfully
  without previews/simulator) — keep it thin, push logic down into
  `FoodLogCore`/`Gamification` so it's actually verifiable.
- **Localization (English + Czech, more later).** All new user-facing text
  is localizable and translated from day one — see
  `openspec/changes/add-localization/design.md` and
  `docs/localization-analysis.md`:
  - App/widget: fixed copy as string *literals* in SwiftUI APIs
    (`Text("…")`, `Label`, `.navigationTitle`, …, which are keys), or
    `String(localized: "…")` when a `String` must be built; never
    `Text(someEnglishString)` for fixed copy. Add the key + Czech to
    `GarminFood/Resources/Localizable.xcstrings` (or the widget's). Keys are
    the English text; `Int` → `%lld`, `Double` → `%lf`, `String` → `%@`.
  - Packages: `String(localized: "…", bundle: .module, comment: "…")`, with
    the key in BOTH `Resources/en.lproj` and `Resources/cs.lproj`
    `Localizable.strings` (`.stringsdict` for plurals) — not `.xcstrings`,
    which `swift test` can't compile.
  - Counts use plural variations (Czech: one/few/many/other), never
    `n == 1 ? … : …`; no sentences glued from translated fragments; stores
    persist ids, never display text; `DiagnosticsLog` stays English.
  - `node tools/check-localizations.mjs` (CI job `localization`) must pass.
- **Test file/helper conventions**: see `FoodLogCoreTests/LogEntryCoordinatorTests.swift`
  for the pattern — real `GarminKit.Outbox`/store instances pointed at a
  unique temp file per test (never mocked), `XCTest`, one assertion group per
  behavior.

## Verifying a change

There is no local build. After editing Swift:

1. Sanity-check syntax by reading it back carefully — no compiler to catch
   typos here.
2. Push a branch and open a PR (or push to a branch with a workflow_dispatch)
   so `.github/workflows/build.yml` runs `swift test` for each touched
   package and `xcodebuild` for the app + widget. That is the actual
   correctness signal.
3. For anything touching a Garmin write route, the request/response shape is
   probably unconfirmed — say so in a comment (see `GarminClient.
   createCustomFood`'s header) and never let it run without an explicit user
   action, per `openspec/config.yaml`'s task rule: "Never include a task that
   writes to the Garmin account before the write contract is documented."
4. Real-device verification (does it actually work against the live Garmin
   account) only happens when the owner sideloads a build via AltStore and
   reports back — flag in the PR/commit message what still needs that.
