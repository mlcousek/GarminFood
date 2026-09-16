// AuthState.swift
//
// An observable auth-state type the app (and, later, extension) UI can
// bind to, per design.md D7: "auth failure is loud; everything else is
// quiet". Three states, matching the task's instructions exactly:
//
//   - `.authenticated`  -- a stored OAuth1 token exists (and OAuth2 access
//                          works, or hasn't been tried yet this session).
//   - `.needsSignIn`    -- the long-lived OAuth1 token has expired: the
//                          OAuth1 -> OAuth2 exchange returned 401. This is
//                          the ONE condition design.md D7 requires to be
//                          loud -- a persistent banner / distinct widget
//                          state / badge, never silently swallowed.
//   - `.signedOut`      -- no bootstrap has happened yet in this process
//                          (D3: bootstrap is per-process), or the user
//                          explicitly disconnected.
//
// Deliberately narrow in what flips state to `.needsSignIn`: only
// `GarminAuthError.longLivedTokenExpired`. A 404 (no data for a date), a
// decoding error, a timeout, a `GarminClientError.httpError` for any other
// reason -- none of these touch auth state. This directly encodes the
// concrete failure design.md D7 names: the vault's `getNutritionLog()`
// wrapped every error in `catch { return null }`, so a 404 was reported as
// "no nutrition data" forever. This type makes that class of bug impossible
// to reintroduce by construction: nothing but `.longLivedTokenExpired`
// reaches `report(_:)`'s state-changing branch.
//
// No SwiftUI/UIKit import -- `@Observable` comes from the platform
// `Observation` module, not from SwiftUI, so this stays usable from a
// widget extension's own (SwiftUI-based, but that's the extension's
// problem, not this package's) view code too.

import Foundation
import Observation

@MainActor
@Observable
public final class GarminAuthState {
    public enum State: Equatable, Sendable {
        case signedOut
        case authenticated
        case needsSignIn
    }

    public private(set) var state: State = .signedOut

    /// Number of entries in this process's own outbox that have not yet been
    /// delivered -- surfaced here so a UI badge (design.md D7: "a badge on
    /// the outbox count") has a single place to read both auth state and
    /// pending count from. Updated externally by whoever drains the outbox
    /// (Outbox.swift does not import this type, to keep it decoupled from
    /// UI concerns -- the app wires the two together).
    public private(set) var pendingCount: Int = 0

    private let tokenProvider: TokenProvider

    public init(tokenProvider: TokenProvider = .shared) {
        self.tokenProvider = tokenProvider
    }

    /// Re-derives `.authenticated` vs `.signedOut` from whether an OAuth1
    /// token is stored. Call on launch and after an explicit sign-in/out.
    /// Never sets `.needsSignIn` -- that only happens via `report(_:)`,
    /// because detecting it requires an actual failed exchange, not just
    /// "a token is present" (a present-but-expired OAuth1 token looks
    /// identical to a valid one until it's actually used).
    public func refresh() async {
        let signedIn = (try? await tokenProvider.isSignedIn) ?? false
        if state == .needsSignIn && signedIn {
            // Still has an OAuth1 token on file, and nothing has yet proven
            // it invalid again -- stay in needsSignIn only if it hasn't
            // been replaced; if the user just re-bootstrapped,
            // markAuthenticated() below is what actually clears it.
            return
        }
        state = signedIn ? .authenticated : .signedOut
    }

    /// Report the outcome of a Garmin API call. Flips to `.needsSignIn`
    /// only for the one error that means the long-lived credential itself
    /// is dead; every other error is intentionally ignored here.
    public func report(_ error: Error) {
        if case GarminAuthError.longLivedTokenExpired = error {
            state = .needsSignIn
        }
        // GarminAuthError.notSignedIn, .exchangeFailed, .consumerKeyFetchFailed,
        // and any GarminClientError (including 401s from routes OTHER than
        // the exchange, and 404s) are deliberately NOT handled here.
    }

    /// Call after GarminAuthSession completes a successful bootstrap.
    public func markAuthenticated() {
        state = .authenticated
    }

    /// Call after an explicit user-initiated sign-out.
    public func markSignedOut() {
        state = .signedOut
    }

    public func updatePendingCount(_ count: Int) {
        pendingCount = count
    }
}
