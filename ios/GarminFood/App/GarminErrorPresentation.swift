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
}
