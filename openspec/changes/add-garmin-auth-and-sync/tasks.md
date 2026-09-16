## 6. Mac-less build pipeline, free-tier project skeleton, and the Keychain-sharing spike

- [x] 6.1 **Spike, before anything else — the build pipeline itself.** **Done and verified 2026-09-14, not just written.** `ios/project.yml` (XcodeGen manifest) + `ios/GarminFood/{GarminFoodApp,ContentView}.swift` + `.github/workflows/build.yml` — pushed, and the resulting Actions run was watched to completion: Xcode 26.6, Swift 6.3.3, `xcodegen generate` succeeded, `xcodebuild build` against an iOS Simulator destination (no code signing) returned `** BUILD SUCCEEDED **` in 40 seconds. The Mac-less build loop genuinely works.
- [x] 6.2 **Revised after research, 2026-09-14 — not a spike anymore, settled.** Headless CI signing with a free Apple ID is not viable: `fastlane`'s `cert`/`sigh` have never supported free/personal-team accounts (an unresolved limitation on its own tracker since 2017), because free-tier signing runs through a private Xcode-GUI-only flow with no API surface to drive from CI. See design.md D9's revision. Extended the CI job instead to `archive` (not `build`) with signing fully disabled (`CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO`), extract the `.app` from the resulting `.xcarchive`, repackage it as an unsigned `.ipa`, and upload it as a workflow artifact. **Verified, not just written**: Actions run 34845947062 succeeded (1m40s); downloaded the resulting artifact and confirmed its internal structure by hand — `Payload/GarminFood.app/{Info.plist, PkgInfo, GarminFood}` — a genuinely well-formed unsigned `.ipa`, 8.5KB, ready for Sideloadly.
- [x] 6.3 **Confirmed by owner, 2026-09-14.** AltServer + AltStore installed the unsigned `.ipa`; the app opens on the real iPhone and shows the hello-world screen. The whole loop — CI archives unsigned, AltStore signs and installs locally with the owner's own Apple ID, app runs on device — is genuinely proven end to end, not just each half separately.
- [x] 6.4 **Settled, 2026-09-14 — definitive negative result, confirmed by the owner on a real device.** The app's own write to the custom Keychain group failed with status **-34018 (`errSecMissingEntitlement`)**; the widget's read failed with the identical status. Same error on both sides is unambiguous: AltStore's free-tier signing does not grant a custom `keychain-access-groups` entitlement at all — it's stripped or never provisioned. **This closes design.md D3's open question**: the shared-token design is not viable on this account. The degraded fallback (each process — app, widget, Control — bootstraps its own Garmin login independently) is now the plan, not a contingency. Design.md D3/D4 updated accordingly. Also noted: AltStore warned of a ~10-new-App-ID-per-week quota during install (each app *and* each extension consumes one) — a real pacing constraint on how many new targets get added per week going forward, not a blocker for what exists today.
- [ ] 6.5 Install SideStore (or AltStore) and confirm it can install and silently resign the throwaway app without deleting it. Confirm a value written before a resign is still present after — this is what makes the 7-day cycle safe for Keychain and local data instead of destructive.
- [ ] 6.6 Create the real Xcode project with three targets: app, widget extension, and Control (the Control may live in the widget extension bundle). Wire it into the CI workflow from 6.1.
- [ ] 6.7 Apply 6.4's result: register the shared Keychain access group across all targets if the spike succeeded, or scaffold independent per-extension bootstrap if it did not.
- [ ] 6.8 Create the `GarminKit` local Swift package. It must not import UIKit or SwiftUI, so both the app and extensions can depend on it.

## 7. OAuth1 signing and token exchange

**Implemented as `ios/GarminKit`, 2026-09-14. Compiles and unit-tests pass in CI — verified, not assumed.**

- [x] 7.1 `OAuth1Signer.swift`, ported from `scripts/lib/garmin.mjs`, using `CryptoKit`'s `HMAC<Insecure.SHA1>`.
- [x] 7.2 `OAuth1SignerTests.swift` — vectors derived by actually running the Node reference implementation, not hand-computed. Passing in CI.
- [x] 7.3 `TokenProvider.swift` calls the confirmed-live exchange route.
- [x] 7.4 `TokenProvider` refreshes at 5 minutes before expiry. **No lock** — task 6.4 found Keychain Sharing unavailable, so design.md D4 was revised: nothing is shared between processes, so there is nothing to lock. Each process refreshes independently.
- [ ] 7.5 Superseded by 7.4's revision — there is no shared lock to test. Real remaining question: does independent per-process refresh actually behave harmlessly when both fire near-simultaneously? Worth a real test once the widget/Control (Phase 4) also holds its own tokens.

## 8. Browser-based bootstrap

**`GarminAuthSession.swift` implemented, 2026-09-14 — compiles, but the ticket-exchange path is explicitly unconfirmed against this account (marked in code comments), not a false confidence.**

- [x] 8.1 `ASWebAuthenticationSession` flow implemented, pointed at Garmin's mobile SSO URL.
- [ ] 8.2 **Half settled (2026-09-16).** The ticket parameter name is now CONFIRMED (`ticket`): a real sign-in reached the ticket *exchange*, which is only reachable once `GarminSSOWebView` has found that parameter in a navigated-to URL. The *exchange* itself is still unconfirmed — but that attempt was made against a request carrying three independent defects, all now fixed: the CAS `service` at mint (`connect.garmin.com/modern`) disagreed with the `login-url` at redeem (`sso.garmin.com/sso/embed`), and the OAuth1 signature both baked the query string into the base URI and signed an empty `oauth_token=`. Needs one clean run to judge.
- [ ] 8.3 Cloudflare-challenge-inside-the-session — **not** what blocked the 2026-09-16 attempt; the interactive WebKit sign-in itself got through. Still untested as a scripted path.
- [x] 8.4 Manual ticket paste fallback implemented alongside 8.1, per the task's own instruction to keep both.
- [x] 8.5 Tokens stored in Keychain with `kSecAttrAccessibleAfterFirstUnlock`. **No shared access group** — task 6.4 confirmed custom groups don't work on this account; each process's Keychain entries are its own.
- [x] 8.6 No password handling exists in the codebase — `ASWebAuthenticationSession` never exposes it to app code by construction.

## 9. Per-process outbox and delivery

**`Outbox.swift` implemented, 2026-09-14 — compiles, unit tests (retry/backoff/429 handling) pass in CI.**

- [x] 9.1 Outbox record implemented as a JSON-file-backed per-process store, per D3/D9 (no App Group, no shared storage of any kind).
- [x] 9.2 Entry + outbox record written together.
- [x] 9.3 Drain implemented: exponential backoff with jitter, `Retry-After` honoured, stops on 429.
- [x] 9.4 Bounded retry count, `failed` state surfaced.
- [ ] 9.5 Not yet wired to `BGAppRefreshTask` or a background `URLSession` — that's app-lifecycle integration, deferred to when the app target actually calls into `Outbox` (Phase 2/4).
- [ ] 9.6 Same — the intent-side two-second inline POST is a widget/Control concern, owned by Phase 4.

## 10. Reconciliation

**`Reconciliation.swift` implemented, 2026-09-14 — compiles, unit tests pass in CI.**

- [x] 10.1 Matches on date, meal type, food id, serving id, number of units — against Garmin, never another process's queue.
- [x] 10.2 Duplicate detection and deletion implemented.
- [x] 10.3 Missing-despite-2xx re-queue implemented.
- [ ] 10.4 Real airplane-mode, three-surface, real-device test — needs Phase 4's widget/Control to exist first.

## 11. Failure surfaces

**`AuthState.swift` implemented, 2026-09-14 — compiles in CI.**

- [x] 11.1 Three-state `AuthState` (`authenticated`/`needsSignIn`/`signedOut`) exists; wiring it to actual app UI (banner, widget state, badge) is Phase 2/4's job.
- [x] 11.2 Outbox accumulates independent of auth state; drains once `TokenProvider` succeeds again.
- [x] 11.3 404/empty-data is quiet (`dailyFoodLog` returns `nil`), 401 maps to `longLivedTokenExpired` — loud, distinct states, per D7.
- [ ] 11.4 **Deliberately not automated.** The first real write against a distinctive test food remains a human-supervised action — no code path in `GarminKit` invokes `createFoodLogEntry` automatically.
