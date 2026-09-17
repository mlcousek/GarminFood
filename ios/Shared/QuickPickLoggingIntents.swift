// QuickPickLoggingIntents.swift
//
// The logging Controls' actions (design.md D1, REVISED 2026-09-14; tasks.md
// 17.1). One shared implementation (`QuickPickControlAction.performLog`)
// plus four thin `AppIntent` wrapper types below it -- one per Control,
// since each Control placed in Control Center/the Lock Screen/the Action
// Button needs its own distinct, statically-declared `kind`
// (GarminFoodWidget/Controls/QuickPickControls.swift) -- so the real logic
// lives in exactly one place, reused identically by the Siri shortcut
// (GarminFood/Shortcuts/LogTopQuickPickIntent.swift) that also wants to log
// the #1 quick pick.
//
// =====================================================================
// WHY THIS MUST RUN IN THE APP'S OWN PROCESS -- design.md D1's correction
// =====================================================================
// Per openspec/config.yaml's Hard Constraints and design.md D1/D2 (both
// REVISED 2026-09-14): there is no App Group and no Keychain Sharing on this
// account (`errSecMissingEntitlement`/-34018, confirmed live). A Control's
// extension process therefore has NO Garmin credential and NO access to this
// app's local FoodLogCore data (UsageHistoryStore/FoodCacheStore are files
// in the APP's own sandboxed container, not a shared one). The ORIGINAL plan
// gave each Control's intent `supportedModes = [.background]`, running
// `perform()` inside the extension's own process -- that cannot work at all,
// because there is nothing there to log against or authenticate with.
//
// The fix (design.md D1): `openAppWhenRun = true` below makes the system
// foreground the app BEFORE calling `perform()`, so the intent genuinely
// executes as the app itself, with the app's own Keychain-stored Garmin
// token and the app's own on-disk FoodLogCore stores available.
//
// CI CORRECTION, 2026-09-15: this file originally used
// `supportedModes: IntentModes = .foreground` (design.md D1's other named
// option). CI's first real compile of this code rejected it outright --
// `IntentModes` requires iOS 26.0, but this project's deployment target is
// iOS 17.0 (openspec/config.yaml). Switched to `openAppWhenRun = true`
// instead: older API (available since iOS 16), achieves the identical
// "foreground the app before running this intent" behavior, and is only
// deprecated (not removed) on iOS 26 -- a compiler warning there, not an
// error here. `ForegroundContinuableIntent`'s more elaborate escalation
// machinery was deliberately avoided for the same reason design.md
// originally gave: its exact call shape couldn't be verified without a
// local Xcode/Swift toolchain, and a second guessed API was too much risk
// to stack on top of the first one CI already caught.
//
// GENUINELY UNCONFIRMED (flagged per this project's own convention -- see
// GarminAuthSession.swift's header -- rather than asserted as fact):
//   1. Whether `authenticationPolicy = .alwaysAllowed` actually avoids a
//      Face ID/passcode prompt once the system must ALSO foreground the app
//      to run `perform()` -- design.md D1's own Risks section names this as
//      untested. Showing app content on a locked device is normally exactly
//      what triggers the unlock prompt in the first place. This can only be
//      settled on a real device.
//
// Task 17.3 also asks for `controlWidgetStatus` feedback (e.g. "Logged 250
// kcal"). That modifier is real (confirmed via platform documentation), but
// every confirmed example of it shown in available research sets a small,
// fixed enum-like status, not an arbitrary per-tap string -- so it is
// deliberately NOT invoked here with a guessed signature that might not
// compile. `.controlWidgetActionHint(_:)` (confirmed real, applied in
// GarminFoodWidget/Controls/QuickPickControls.swift) covers the
// accessibility-facing half of that task; the system's own built-in
// momentary success/failure indication after a Control's action
// completes/throws covers the rest until this is verified in Xcode.

import AppIntents
import GarminKit
import FoodLogCore

/// Not itself gated to iOS 18 -- only the four Control-facing intent types
/// below (and the Controls that use them) are, since Controls are the iOS
/// 18+ surface. This plain logic function is reused by
/// `GarminFood/Shortcuts/LogTopQuickPickIntent.swift` too, which targets
/// this app's iOS 17 deployment baseline like everything else non-Control.
enum QuickPickControlAction {
    enum ActionError: Error, CustomLocalizedStringResourceConvertible {
        case nothingRankedYet
        case foodNotCachedLocally
        /// The entry IS saved and queued; it just can't reach Garmin until
        /// the user signs in again. Thrown so the Control shows a failure
        /// instead of a success it hasn't earned (add-glanceable-surfaces
        /// 21.2: an expired sign-in must fail loudly).
        case savedButSignedOut

        var localizedStringResource: LocalizedStringResource {
            switch self {
            case .nothingRankedYet:
                return "Nothing logged yet to quick-pick from -- log a food from the app first."
            case .foodNotCachedLocally:
                return "That food's details aren't saved locally yet -- open the app and log it once from there."
            case .savedButSignedOut:
                return "Saved in GarminFood, but not sent: sign in to Garmin again in the app."
            }
        }
    }

    /// Ranks quick-pick foods (FoodLogCore.QuickPick, the same ranking the
    /// app's own `FoodCatalogView` shelf uses) and logs the one at
    /// `rankIndex` (0-based -- rank 0 is the #1 quick pick).
    ///
    /// Uses the process-wide `AppServices` stores, the same instances the
    /// running app uses, so a Control log can't be lost to a second
    /// in-memory copy of the same files (add-app-shell-and-meal-dashboard
    /// 1.1). This only ever runs in the APP's process (see this file's
    /// header).
    @MainActor
    static func performLog(rankIndex: Int) async throws {
        let services = AppServices.shared

        let ranked = QuickPick.rank(events: await services.usageHistory.all())
        guard ranked.indices.contains(rankIndex) else {
            throw ActionError.nothingRankedYet
        }
        let pick = ranked[rankIndex]

        let cache = await services.foodCache.all()
        guard let food = cache[pick.foodId],
              let serving = food.servings.first(where: { $0.id == pick.servingId }) else {
            throw ActionError.foodNotCachedLocally
        }

        let date = NutritionDate.todayString()
        try await services.logEntryCoordinator.confirm(
            food: food,
            serving: serving,
            numberOfUnits: pick.numberOfUnits,
            mealType: MealTypeDefaulting.defaultMealType(),
            date: date
        )
        await services.logObserver?.didLog(food: food, date: date)

        // The durable local commit above is what must never wait on the
        // network. Delivery after it is waited for, but only briefly
        // (add-garmin-auth-and-sync 9.6): past ~2 s the Control reports
        // success and the drain finishes on its own.
        if let result = await services.briefDelivery(), isSignedOut(result.authOutcome) {
            throw ActionError.savedButSignedOut
        }
    }

    /// A switch rather than `!= .none`: `DrainAuthOutcome` has a case named
    /// `none`, and a comparison against `.none` can resolve to
    /// `Optional.none`, which would always be "not equal".
    static func isSignedOut(_ outcome: DrainAuthOutcome) -> Bool {
        switch outcome {
        case .none:
            return false
        case .longLivedTokenExpired, .notSignedIn:
            return true
        }
    }
}

@available(iOS 18.0, *)
struct LogQuickPick1Intent: AppIntent {
    static var title: LocalizedStringResource = "Log Quick Pick #1"
    static var description = IntentDescription("Logs your #1 most-used food in GarminFood.")
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    static var openAppWhenRun: Bool = true

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        try await QuickPickControlAction.performLog(rankIndex: 0)
        return .result()
    }
}

@available(iOS 18.0, *)
struct LogQuickPick2Intent: AppIntent {
    static var title: LocalizedStringResource = "Log Quick Pick #2"
    static var description = IntentDescription("Logs your #2 most-used food in GarminFood.")
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    static var openAppWhenRun: Bool = true

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        try await QuickPickControlAction.performLog(rankIndex: 1)
        return .result()
    }
}

@available(iOS 18.0, *)
struct LogQuickPick3Intent: AppIntent {
    static var title: LocalizedStringResource = "Log Quick Pick #3"
    static var description = IntentDescription("Logs your #3 most-used food in GarminFood.")
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    static var openAppWhenRun: Bool = true

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        try await QuickPickControlAction.performLog(rankIndex: 2)
        return .result()
    }
}

@available(iOS 18.0, *)
struct LogQuickPick4Intent: AppIntent {
    static var title: LocalizedStringResource = "Log Quick Pick #4"
    static var description = IntentDescription("Logs your #4 most-used food in GarminFood.")
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    static var openAppWhenRun: Bool = true

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        try await QuickPickControlAction.performLog(rankIndex: 3)
        return .result()
    }
}
