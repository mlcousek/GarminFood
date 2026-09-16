import Foundation
import GarminKit

/// Shared, human-readable messages for Garmin API failures (task: real-
/// device feedback 2026-09-16 -- a Garmin search failing because the user
/// was never actually signed in was showing the same generic "check your
/// connection" message as a real network failure, which is actively
/// misleading since there's nothing to retry until the user signs in).
/// Used by both `FoodCatalogView`'s Garmin search and
/// `MatchConfirmationView`'s Garmin-equivalent lookup, since both call the
/// same underlying `GarminClient`/`FoodCatalogSearch` and can fail the same
/// way.
enum GarminErrorPresentation {
    static func searchErrorMessage(for error: Error) -> String {
        switch error {
        case GarminAuthError.notSignedIn, GarminAuthError.longLivedTokenExpired:
            return "Sign in to Garmin to search its food database."
        default:
            return "Couldn't reach Garmin right now. Check your connection or try again."
        }
    }

    /// The ticket -> OAuth1 bootstrap is the one genuinely unverified route in
    /// this project (see `GarminAuthSession`'s header comment), so its
    /// failures have to say what actually came back. The 2026-09-16
    /// real-device attempt reported only "That ticket didn't work", which
    /// reads as "you pasted it wrong" but is equally consistent with a
    /// rejected ticket, a bad OAuth1 signature, or an unreachable
    /// consumer-key host -- three different fixes, and the user can do
    /// nothing about two of them. Per design.md D7 an auth failure is
    /// supposed to be loud; a catch-all sentence that hides the status code
    /// is the quiet kind.
    static func bootstrapErrorMessage(for error: Error) -> String {
        if let bootstrap = error as? GarminBootstrapError {
            switch bootstrap {
            case .exchangeFailed(let statusCode, let body):
                let status = statusCode.map { "HTTP \($0)" } ?? "no HTTP response"
                let detail = (body ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if detail.isEmpty {
                    return "Garmin rejected the sign-in ticket (\(status))."
                }
                return "Garmin rejected the sign-in ticket (\(status)): \(detail.prefix(300))"
            case .malformedExchangeResponse:
                return "Garmin accepted the ticket but sent back a response this app couldn't read."
            case .invalidExchangeURL:
                return "Couldn't build Garmin's exchange URL. That's an app bug -- retrying won't help."
            }
        }
        if let auth = error as? GarminAuthError, case .consumerKeyFetchFailed(let statusCode) = auth {
            let status = statusCode.map { "HTTP \($0)" } ?? "no HTTP response"
            return "Couldn't fetch Garmin's public consumer key (\(status)). Check your connection and try again."
        }
        return "Sign-in failed: \(error.localizedDescription)"
    }
}
