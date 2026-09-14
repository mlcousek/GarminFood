## 6. Free-tier project skeleton and the Keychain-sharing spike

- [ ] 6.1 **Spike, before anything else.** Create a throwaway app + widget extension pair on a free Apple Personal Team. Add the Keychain Sharing capability (`keychain-access-groups` entitlement) to both targets with a common group name. Write an item from the app, read it from the extension. Record the result — this decides whether D3's shared-token design or its degraded fallback is what gets built.
- [ ] 6.2 Install SideStore (or AltStore) and confirm it can install and silently resign the throwaway app without deleting it. Confirm a value written before a resign is still present after — this is what makes the 7-day cycle safe for Keychain and local data instead of destructive.
- [ ] 6.3 Create the real Xcode project with three targets: app, widget extension, and Control (the Control may live in the widget extension bundle).
- [ ] 6.4 Apply 6.1's result: register the shared Keychain access group across all targets if the spike succeeded, or scaffold independent per-extension bootstrap if it did not.
- [ ] 6.5 Create the `GarminKit` local Swift package. It must not import UIKit or SwiftUI, so both the app and extensions can depend on it.

## 7. OAuth1 signing and token exchange

- [ ] 7.1 Port the OAuth1 HMAC-SHA1 request signing to Swift using `CryptoKit`'s `HMAC<Insecure.SHA1>`. The reference implementation is `scripts/lib/garmin.mjs` in the owner's vault, which is known to work.
- [ ] 7.2 Write unit tests for the signature base string and percent-encoding against known-good vectors captured from the working Node implementation. Signing bugs are silent and maddening; pin them with tests.
- [ ] 7.3 Implement the OAuth2 exchange: `POST /oauth-service/oauth/exchange/user/2.0` with the OAuth1 Authorization header. Verified working 2026-09-14, returns a token valid ~24h.
- [ ] 7.4 Implement `TokenProvider` with refresh at five minutes before expiry, guarded by the `SecItemAdd`-atomicity lock from design.md D4 (or, if task 6.1's spike found Keychain Sharing unavailable, guard only within a single process and accept independent per-process refresh).
- [ ] 7.5 Test the lock by forcing simultaneous refresh from the app and the widget extension. Confirm exactly one exchange request is issued (if Keychain Sharing is available) or that both succeed harmlessly (if it is not).

## 8. Browser-based bootstrap

- [ ] 8.1 Implement the "Connect Garmin" flow with `ASWebAuthenticationSession` pointed at Garmin's mobile SSO URL.
- [ ] 8.2 Capture the service ticket from the callback URL and exchange it for OAuth1 and OAuth2 tokens. Record the exact redirect URL and parameter name in `docs/garmin-routes.json`.
- [ ] 8.3 Confirm that a Cloudflare challenge, if presented, can be completed inside the session. If it cannot, stop and fall back to task 8.4.
- [ ] 8.4 Implement manual ticket paste as a documented fallback. Keep it even if 8.1 works — it is the recovery path when the redirect contract changes.
- [ ] 8.5 Store tokens in the Keychain with `kSecAttrAccessibleAfterFirstUnlock` and the shared access group. Verify the widget extension can read them while the device is locked.
- [ ] 8.6 Verify the app never receives, logs, or persists the password. Grep the codebase for any password handling and confirm there is none to find.

## 9. Per-process outbox and delivery

- [ ] 9.1 Define the outbox record: client-generated UUID, `foodId`, `servingId`, `numberOfUnits`, `mealType`, local date, state, attempt count, last error. Implement it once in `GarminKit` as a small local store (`UserDefaults` or a JSON file) that each process — app, widget extension, Control — instantiates its own copy of. No App Group; nothing here is shared across processes by design (D3).
- [ ] 9.2 Write entry and outbox record in a single transaction, so an entry can never exist without a delivery obligation.
- [ ] 9.3 Implement the drain: POST to the write route documented by `establish-garmin-nutrition-contract`, honour `Retry-After`, exponential backoff with jitter capped at 8 s, stop on 429.
- [ ] 9.4 Cap retries. After a bounded number of attempts mark the record failed and surface it for manual retry rather than looping forever.
- [ ] 9.5 Trigger each process's own drain independently: the app on foreground and via `BGAppRefreshTask`; the widget/Control extension via its own background `URLSession` whose events route back to it via `.onBackgroundURLSessionEvents(matching:)`.
- [ ] 9.6 Implement the two-second best-effort inline POST from the intent, and confirm `perform()` returns promptly whether or not it succeeds.

## 10. Reconciliation

- [ ] 10.1 After any process's successful drain, re-read the day's log from Garmin and match entries on date, meal type, food id, serving id and number of units. Reconciliation is always against Garmin, never against another process's local queue.
- [ ] 10.2 If Garmin holds a duplicate, delete one and record that it happened. Duplicates are expected occasionally; unnoticed duplicates are not.
- [ ] 10.3 If Garmin holds nothing despite a 2xx response, re-queue the entry and log the discrepancy loudly.
- [ ] 10.4 Test the airplane-mode path end to end: log three foods offline (one from the app, one from the widget, one from the Control), restore connectivity, confirm exactly three entries land in Garmin and the ring — read fresh from Garmin per D3 — matches.

## 11. Failure surfaces

- [ ] 11.1 Implement the expired-token state: persistent in-app banner, a distinct "Sign in to Garmin" widget state, and a badge on the pending count.
- [ ] 11.2 Confirm entries continue to accumulate locally while signed out, and drain once the session is restored.
- [ ] 11.3 Confirm that missing data is quiet and broken credentials are loud, and write a test that fails if a 401 is ever swallowed.
- [ ] 11.4 Make the first real write against a deliberately distinctive test food on a date the owner can inspect and delete by hand.
