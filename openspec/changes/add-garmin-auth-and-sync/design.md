## Context

Two constraints drive everything here.

**Login is browser-only.** Since March 2026 Garmin's SSO endpoints sit behind Cloudflare bot protection. A scripted POST of credentials returns 401 at `oauth-service/oauth/preauthorized`. Browser-based sign-in still works, which is why the community converged on a manual "sign in, copy the service ticket, paste it into the tool" bootstrap. An iOS app can do considerably better than paste: `ASWebAuthenticationSession` *is* a real browser (Safari's networking stack, Safari's TLS fingerprint), so the user signs in inside the app and the ticket is captured on redirect without leaving it.

**The token must work from a headless extension.** The whole point of the project is a Control Center button that logs food while the phone is locked. That intent runs in the widget extension's process, not the app's. It needs the token, and it needs to not fight the app over refreshing it.

Probing on 2026-09-14 confirmed the exchange half of this already works: the vault's stored OAuth1 token signed a request to `POST /oauth-service/oauth/exchange/user/2.0` and got back an access token valid 88227 seconds. The mechanism is sound; only acquisition is hard.

## Goals / Non-Goals

**Goals:**

- Never handle the user's Garmin password, at any point, in any form.
- Make a food entry durable the instant the user taps, independent of network, token validity, or Garmin being up.
- Deliver each entry to Garmin exactly once, and detect it when that fails.
- Make token expiry a calm, expected, once-a-year maintenance event with an obvious remedy.

**Non-Goals:**

- Surviving a Garmin API change without human intervention. Not achievable on an undocumented surface; the goal is fast diagnosis.
- Real-time sync. Minutes of latency are fine. Silent data loss is not.
- A single shared local database between the app and its extensions. Ruled out by the free-tier decision in D3; each process keeps its own state.

## Decisions

### D1 — No backend. Everything on device.

The temptation is a small server holding the token and exposing a clean API. Rejected.

A backend would mean the user's Garmin session lives on a machine they have to secure, patch and pay for, and the failure mode of a compromise is someone else's access to their health account. It buys nothing here: the OAuth1 signing is thirty lines of HMAC-SHA1, `CryptoKit` has `HMAC<Insecure.SHA1>`, and there is exactly one user, so there is no fan-out to amortise. The one thing a server would genuinely help with — surviving iOS background-execution limits — is better solved by the outbox.

*Consequence:* the app must do OAuth1 request signing in Swift. That is the only genuinely fiddly part, and it is well-specified.

### D2 — Bootstrap through `ASWebAuthenticationSession`, capture the ticket on redirect

The user taps "Connect Garmin". `ASWebAuthenticationSession` opens Garmin's real sign-in page — including MFA, including any Cloudflare challenge, all of which the user is perfectly capable of completing. On successful sign-in Garmin redirects with a service ticket; the app captures it from the callback URL and exchanges it for OAuth1 and OAuth2 tokens.

This is strictly better than the community's paste-the-ticket workflow, and it is the difference between a tool and an app. It also means MFA needs no special handling at all: it happens inside the web view, where it belongs.

*Alternatives.* A `WKWebView` gives more control over intercepting navigation but does not share Safari's cookie jar and is more likely to be fingerprinted as automation. Manual paste works and should remain as a documented fallback for the day Apple or Garmin breaks the redirect.

*Risk accepted:* the exact redirect URL and ticket parameter are undocumented and may change. They belong in the route registry with a `lastVerified` date like everything else.

### D3 — No App Group. Garmin is the shared source of truth; each process keeps its own queue.

The owner decided (2026-09-14) not to pay for the Apple Developer Program yet. That removes App Groups, and with them the one obvious way to share a SQLite file or a lock file between the app and its widget/Control extensions. Rather than block on that, the architecture is redesigned to not need it.

**Reads never depend on shared local storage.** Today's total, the running ring, the recent-entries list — every one of these is read straight from Garmin (`/usersummary-service/usersummary/daily` for the total, the food-log read route once D1 of `establish-garmin-nutrition-contract` finds it), by whichever process needs it, with a short in-process cache (tens of seconds) to stay inside widget reload budgets. Garmin already aggregates truth across every entry from every device; there is no reason to also aggregate it locally and then reconcile two copies. This is a simplification, not just a workaround — it removes an entire class of "local total disagrees with Garmin" bugs.

**Writes get a queue per process, not one shared queue.** The app and each extension keep their own local pending-entries store, in their own sandboxed container (`UserDefaults.standard` or a small JSON file — no App Group needed, because nothing outside the process reads it). Each drains independently: the app on foreground and via `BGAppRefreshTask`; the widget/Control extension via its own background `URLSession`. Neither needs to see the other's queue, because reconciliation (D5) checks against Garmin, not against a sibling process's local state.

**Tokens still need to cross the process boundary**, because the whole point is a Control that authenticates while the app isn't running. Keychain Sharing (`keychain-access-groups` entitlement) is a capability distinct from App Groups, and is plausibly available on a free Personal Team — but this is not confirmed by anything probed so far, and existing research on free-tier limits names App Groups, Push, iCloud and HealthKit specifically without settling Keychain Sharing either way. Task 6.1 spikes this directly, before any other work in this change:

- **If Keychain Sharing works**: the app and both extensions share one access group, exactly as originally designed. D4's lock is revised below to not need a shared file either.
- **If it does not**: each extension does its own bootstrap (D2) independently, meaning the user connects Garmin once for the app and once more for the widget/Control. Degraded, but not broken — the whole design keeps working, just with an extra one-time step.

*Consequence for the desktop-widget requirement:* since there is no App Group file to protect, the earlier `NSFileProtectionComplete` gotcha does not apply. Each process's own local queue should still use `NSFileProtectionCompleteUntilFirstUserAuthentication` so a background drain can run before the user unlocks their phone.

### D4 — One refresher per process, guarded by Keychain atomicity instead of a file lock

Both the app and an extension can discover an expired OAuth2 token simultaneously. Two concurrent OAuth1 exchanges against an undocumented endpoint is an experiment nobody should run on their only token — and without an App Group there is no shared file to put an advisory lock in.

`SecItemAdd` is atomic and fails with `errSecDuplicateItem` if the item already exists. A `TokenProvider` in `GarminKit` uses that directly as the mutex: before refreshing, it tries to add a small `refreshing-since-<timestamp>` marker item to the shared Keychain access group. Success means it holds the lock and proceeds to exchange and overwrite the token item; failure means someone else holds it, so it backs off and re-reads the token, which should now be fresh. The marker is deleted when the refresh completes, and any marker older than a short timeout (say 30s) is treated as stale and cleared, so a process that died mid-refresh cannot deadlock every future refresh. Refresh is attempted when the token is within five minutes of expiry, matching the working vault client. This only works if D3's Keychain Sharing spike succeeds; if it does not, each process refreshes independently and a brief duplicate refresh is accepted as harmless (both get a valid token, just wastefully).

### D5 — Local-first, per-process outbox, client-generated idempotency key

A tap writes two rows in one transaction, in whichever process the tap happened in: the entry itself, and an outbox record in that process's own local store (D3). The UI reads the entry immediately; the user is never shown a spinner.

The outbox record carries a client-generated UUID. Garmin's private API is unlikely to offer an idempotency key — task 4.3 of the previous change settles this — so de-duplication is the client's problem. Reconciliation happens against Garmin, not against a sibling process: after a drain, re-read the day's log and match on `(date, mealType, foodId, servingId, numberOfUnits)`. If Garmin holds two copies, delete one. If it holds none despite a 2xx, re-queue.

*This is the single most important decision in the change.* The naive alternative — POST on tap, show an error on failure — loses entries whenever the phone is in a lift, which for a food logger is most of the times a person logs food.

### D6 — The extension attempts a fast write, then gets out of the way

When the intent runs, it writes to its own local store, appends to its own outbox, and attempts one short-timeout POST (~2 s). If that succeeds, the next read (D3) reflects it immediately since reads go straight to Garmin. If not, it returns anyway.

It must return promptly regardless: WidgetKit reloads the timeline the moment `perform()` returns, and the widget extension is killed at a 30 MB high-water mark. Draining a backlog inside a widget extension is how you get jetsammed. The extension's own backlog is drained by its own background `URLSession`, whose events route back to it via `.onBackgroundURLSessionEvents(matching:)` — this does not require an App Group, only that the session events are scoped to the extension that created them. The app drains its own, separate backlog on foreground and via `BGAppRefreshTask`.

### D7 — Auth failure is loud; everything else is quiet

An expired OAuth1 token is not an error to swallow. It surfaces as a persistent banner in the app, a distinct widget state ("Sign in to Garmin"), and a badge on the outbox count. Entries keep accumulating locally and drain when the session is restored — nothing is lost, but the user is told.

This rule exists because of a concrete local failure: the vault's `getNutritionLog()` wraps every error in `catch { return null }`, so a 404 endpoint has been reported as "no nutrition data" for the lifetime of that script. Quiet degradation is right for missing data and wrong for broken credentials.

### D8 — Distribute via AltStore/SideStore's automatic resign, not manual Xcode reinstalls

A free Personal Team's provisioning profiles expire after 7 days. The owner's stated plan is to reinstall weekly, which is workable but the *mechanism* matters: a plain Xcode "Run" every 7 days deletes and reinstalls the app, which wipes its container — including the Keychain items and both local outboxes. That would mean re-running the Garmin bootstrap (D2) weekly, which defeats the point of a durable session.

AltStore or SideStore resign the *same installed binary* in place on a schedule, without deleting the app or its data. Team ID and Bundle ID stay constant across resigns (same free Apple ID, same project), so Keychain items keyed to them survive. Recommend SideStore specifically: after one initial computer pairing it refreshes itself over its own on-device VPN, rather than requiring AltServer running on a nearby Mac/PC every week.

*Consequence:* the setup task in this change is "install via SideStore" up front, not "reinstall via Xcode every week" — the latter is a plausible-sounding trap that silently breaks D2 through D6.

### D9 — Build on GitHub Actions' macOS runners; the owner has no Mac

Xcode is macOS-only. That is a fact about the platform, not a preference, and no amount of clever tooling changes it — Swift *language* tooling exists cross-platform, but WidgetKit, AppIntents, SwiftUI's iOS target, and Apple's code-signing toolchain do not run outside macOS. Since the owner has no Mac (confirmed 2026-09-14), the build step moves to CI: a `.github/workflows/build.yml` running on a `macos-latest` GitHub-hosted runner does `xcodebuild`/`xcodebuild -exportArchive`, producing a signed `.ipa` as a workflow artifact.

This is normally a paid convenience (macOS runner minutes carry a 10x multiplier against a private repo's included quota) but this repository is public, and **GitHub Actions is free and unlimited on public repositories, macOS runners included**. The cost genuinely is $0, provided the repo stays public — worth stating as a real constraint this decision depends on, not an incidental detail.

The resulting `.ipa` is sideloaded from the owner's Windows machine. Combined with D8, the full loop — write, build, sign, install, use — never requires macOS hardware the owner owns or rents.

*What this costs in practice, stated plainly:* no SwiftUI live previews, no interactive debugger, no Instruments profiling. Iteration is edit → push → wait for a CI build (macOS runners are slower to provision than a local build) → download the artifact → sideload → test on the phone. This is real friction for UI-heavy work like widget layout, and it is accepted deliberately rather than glossed over.

**Revised after research (2026-09-14): CI does not sign anything.** The original plan here was to code-sign a free Apple ID headlessly inside CI, treated as an open spike. Research settled it, and the answer is not "yes with effort" — it is "no, and stop trying." `fastlane`'s `cert`/`sigh` tools, the standard way to automate Apple certificate and provisioning-profile management, have never supported free/personal-team Apple IDs; this is a specifically-requested, unresolved limitation on fastlane's own issue tracker dating back to 2017 and still open. The reason is structural, not a missing feature: a free Apple ID has no access to the Apple Developer Portal's certificate/profile management surface at all — that surface is gated on a paid Developer Program membership. Xcode's free-tier "automatic signing" works through a separate, private, GUI-only flow, not through anything `fastlane`, `spaceship`, or a CI script can drive.

So the design changes to match how every free-tier sideloading tool (AltStore, SideStore, Sideloadly) actually works: **signing happens locally, once, using the owner's Apple ID typed directly into a purpose-built local tool — never in CI, never as a GitHub secret, never seen by anyone building this project.**

- CI archives with signing fully disabled (`CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO`, `archive` action, not `build`), extracts the `.app` from the resulting `.xcarchive`, repackages it as an unsigned `.ipa` (an `.app` inside a `Payload/` folder, zipped), and uploads it as a workflow artifact.
- The owner downloads that unsigned `.ipa` and opens it in **Sideloadly** on their Windows machine. Sideloadly signs it with a free-tier certificate it generates against the owner's own Apple ID — entered into Sideloadly's own window, going straight to Apple's servers — and installs it onto the iPhone over USB.
- The 7-day resign cycle (D8) is Sideloadly/SideStore's job thereafter, using the same locally-held credential, never CI's.

This is strictly better than the original plan, not just a fallback: the Apple ID never exists as a secret anywhere in this project's infrastructure at all.

## Risks / Trade-offs

- **Cloudflare may extend bot protection to the exchange endpoint** → then even the OAuth1→OAuth2 exchange fails and no on-device design works. Mitigation: none technical. The fallback is the Cronometer bridge from the previous change's D4. This is the single biggest existential risk and it is outside our control.

- **The redirect URL or ticket parameter changes** → bootstrap breaks while existing tokens keep working, so the failure appears months later at re-auth time, which is the worst possible moment. Mitigation: keep manual ticket paste as a documented fallback, and record the redirect contract in the route registry.

- **Garmin has no idempotency key and a retry duplicates an entry** → the user sees 2× calories. Mitigation: D5 reconciliation. Accept that a duplicate can exist briefly between drain and reconcile; never accept that it persists.

- **Two processes race on token refresh and one invalidates the other's token** → both fail, and the user is signed out for no reason. Mitigation: D4's Keychain-based lock. Test it explicitly by forcing simultaneous refresh from app and extension.

- **Keychain Sharing turns out to be as blocked as App Groups on a free team** → the extension cannot use the app's token at all. Mitigation: D3's degraded fallback (each process bootstraps independently). Costs the user one extra sign-in; costs nothing structurally.

- **Manual Xcode reinstalls are used instead of SideStore/AltStore** → weekly loss of Keychain tokens and both local outboxes, and the user re-discovers this the hard way. Mitigation: D8 states the correct mechanism up front, and the setup task names it explicitly rather than leaving "reinstall every 7 days" ambiguous.

- **iOS kills background drains and the outbox grows unbounded** → memory and confusion. Mitigation: cap retry attempts, mark entries `failed` after a bounded number, surface them for manual retry rather than looping forever.

## Open Questions

1. **Does Garmin's redirect hand back a service ticket usable for the OAuth1 exchange, or only a DI OAuth2 token?** The community's peloton-to-garmin work suggests a `serviceTicketId` exchanged for DI OAuth2 with ~30-day refresh. If DI OAuth2 is the only path, the refresh cadence is monthly rather than annual and D4's lock matters more.
2. **Can `ASWebAuthenticationSession` complete a Cloudflare challenge?** Expected yes; unverified. Task 2.2 settles it.
3. **Does the food-log write accept an arbitrary client-supplied id?** Would make D5 much cheaper. Settled by the previous change's task 4.3.
4. **Is Keychain Sharing available to a free Apple Personal Team?** Unconfirmed by any research so far — only App Groups, Push, iCloud and HealthKit are documented as blocked. This is the load-bearing unknown for D3 and is spiked first, in task 6.1, before any other work in this change.
