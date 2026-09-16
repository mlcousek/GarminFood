// GarminFoodDeepLink.swift
//
// The one deep link this app's STATIC widgets need (design.md D2, REVISED
// 2026-09-14): every widget is a data-free "tap to open the app" shortcut,
// so there is exactly one destination worth naming -- the app's own root
// screen, which already IS the food-logging screen (see ContentView.swift).
// Kept as its own tiny Shared type (compiled directly into both the
// GarminFood app target and the GarminFoodWidgetExtension target, per
// project.yml's `sources: [..., Shared]` on both) purely so the scheme
// string lives in exactly one place instead of being duplicated as a
// string literal in each target.
//
// Reuses the app's existing "garminfood" custom scheme, the same one
// registered in `ios/project.yml`'s `CFBundleURLTypes`, rather than adding
// a second one. Garmin sign-in no longer uses this scheme for anything
// (see GarminAuthSession.swift's 2026-09-16 real-device finding: it
// switched to a `WKWebView`-based ticket capture that doesn't depend on a
// custom-scheme redirect at all), so any "garminfood://" open -- including
// this one, tapped from a widget -- falls through to the app's normal
// `onOpenURL(perform:)` handling like any other registered custom URL
// scheme. The extension itself never needs to receive an open, only to
// construct the URL the system routes elsewhere.

import Foundation

enum GarminFoodDeepLink {
    static let scheme = "garminfood"

    /// The single destination every static widget in this app points at:
    /// just open the app. There is nothing more specific to deep-link to,
    /// since the app's root screen already is the logging screen.
    static let openAppURL = URL(string: "\(scheme)://open")!
}
