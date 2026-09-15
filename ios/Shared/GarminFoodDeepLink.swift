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
// Reuses GarminKit's existing "garminfood" custom scheme
// (`GarminSSOEndpoints.callbackURLScheme`) rather than registering a second
// one. This is safe: `ASWebAuthenticationSession` only intercepts a
// "garminfood://" open while ITS OWN in-flight sign-in session is waiting
// for a callback; any other "garminfood://" open (like this one, tapped
// from a widget with no sign-in session active) falls through to the app's
// normal `onOpenURL(perform:)` handling exactly like any other registered
// custom URL scheme. `ios/project.yml` registers this scheme in the
// GarminFood app target's `CFBundleURLTypes` -- the extension itself never
// needs to receive an open, only to construct the URL the system routes
// elsewhere.

import Foundation

enum GarminFoodDeepLink {
    static let scheme = "garminfood"

    /// The single destination every static widget in this app points at:
    /// just open the app. There is nothing more specific to deep-link to,
    /// since the app's root screen already is the logging screen.
    static let openAppURL = URL(string: "\(scheme)://open")!
}
