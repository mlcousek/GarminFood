// GarminFoodApp.swift
//
// The app's entry point. Task 6.1 (add-garmin-auth-and-sync) originally
// used this file only to prove `xcodebuild` could build something in CI at
// all; the real UI (food catalog, custom foods, confirm-and-log flow) now
// lives under GarminFood/{App,DesignSystem,Catalog,CustomFood,LogEntry}/,
// composed from `ContentView` -- see that file and `App/AppEnvironment.swift`.

import SwiftUI
import BackgroundTasks

@main
struct GarminFoodApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        // Delivers queued entries while the app is closed, when iOS grants
        // the time (add-garmin-auth-and-sync 9.5).
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) {
            await BackgroundRefresh.run()
        }
    }
}
