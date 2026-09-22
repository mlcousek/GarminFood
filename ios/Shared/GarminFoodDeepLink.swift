// GarminFoodDeepLink.swift
//
// Deep links this app's STATIC widgets use (design.md D2, REVISED
// 2026-09-14; sharpened 2026-09-22). Kept as its own tiny Shared type
// (compiled directly into both the GarminFood app target and the
// GarminFoodWidgetExtension target, per project.yml's `sources: [...,
// Shared]` on both) so the scheme string and each action's URL live in
// exactly one place instead of being duplicated as string literals in each
// widget file.
//
// Reuses the app's existing "garminfood" custom scheme, the same one
// registered in `ios/project.yml`'s `CFBundleURLTypes`, rather than adding
// a second one. Garmin sign-in no longer uses this scheme for anything
// (see GarminAuthSession.swift's 2026-09-16 real-device finding: it
// switched to a `WKWebView`-based ticket capture that doesn't depend on a
// custom-scheme redirect at all), so any "garminfood://" open -- including
// these, tapped from a widget -- falls through to the app's normal
// `onOpenURL(perform:)` handling like any other registered custom URL
// scheme. The extension itself never needs to receive an open, only to
// construct the URL the system routes elsewhere.
//
// 2026-09-22: both existing widgets are labeled "Log Food" and their whole
// point is getting the user logging as fast as possible -- but their link
// used to just switch to the Today tab and stop, leaving the user to tap
// "Log a food" again themselves. `Action.logFood` now names that intent
// explicitly and `AppRouter.handle(url:)` drives the user straight into the
// catalog screen (reusing the same `catalogRequested` mechanism the
// barcode-scan Control already relies on -- see AppRouter.swift), removing
// that redundant second tap. `Action` exists (rather than one bare URL) so
// a future widget with a genuinely different destination (e.g. Progress)
// has somewhere to add its own case instead of overloading this one.

import Foundation

enum GarminFoodDeepLink {
    static let scheme = "garminfood"

    enum Action: String {
        /// The one real intent every widget in this app has today: open
        /// straight into the food-logging screen, not just the app.
        case logFood
    }

    static let logFoodURL = url(for: .logFood)

    static func url(for action: Action) -> URL {
        URL(string: "\(scheme)://\(action.rawValue)")!
    }

    /// `nil` for a URL with the wrong scheme, or a host this enum doesn't
    /// (yet) recognise -- callers should just ignore it rather than guess.
    static func action(from url: URL) -> Action? {
        guard url.scheme == scheme, let host = url.host else { return nil }
        return Action(rawValue: host)
    }
}
