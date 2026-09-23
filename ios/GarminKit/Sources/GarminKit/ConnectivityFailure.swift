// ConnectivityFailure.swift
//
// Tells "the phone can't reach Garmin right now" apart from "Garmin
// rejected this". Scenario-review finding (2026-09-23): the outboxes counted
// a no-connection error as a failed attempt, exactly like a Garmin 4xx, so
// logging a few foods on a trail or a plane burned through `maxAttempts`
// within seconds (the backoff is capped at 8 s) and left them `.failed` --
// warning triangle, banner, and no automatic retry once back online. That
// broke CLAUDE.md's "everything else degrades quietly" rule: being offline is
// the normal case this local-first app is built for, not a delivery failure.
//
// So an outbox that gets one of these stops its drain cycle (every other
// entry would fail the same way), leaves the entry pending with its attempt
// count untouched, and lets the next drain -- next log, foreground or
// background refresh -- simply try again.
//
// `GarminClient.perform` rethrows `URLSession` errors unchanged, so a raw
// `URLError` is what reaches the outboxes. Depended on by: Outbox.swift,
// WeightSync.swift and HydrationSync.swift (all three drains).

import Foundation

public enum ConnectivityFailure {
    /// `true` for errors that mean the request never got a real answer from
    /// Garmin because the network isn't there (or isn't usable) -- NOT for
    /// anything Garmin itself returned, and not for cancellation.
    public static func matches(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .notConnectedToInternet,
             .networkConnectionLost,
             .timedOut,
             .cannotFindHost,
             .cannotConnectToHost,
             .dnsLookupFailed,
             .internationalRoamingOff,
             .dataNotAllowed,
             .callIsActive:
            return true
        default:
            return false
        }
    }
}
