// GarminFoodApp.swift
//
// The app's entry point. Task 6.1 (add-garmin-auth-and-sync) originally
// used this file only to prove `xcodebuild` could build something in CI at
// all; the real UI (food catalog, custom foods, confirm-and-log flow) now
// lives under GarminFood/{App,DesignSystem,Catalog,CustomFood,LogEntry}/,
// composed from `ContentView` -- see that file and `App/AppEnvironment.swift`.

import SwiftUI
import BackgroundTasks
import UserNotifications

@main
struct GarminFoodApp: App {
    init() {
        // add-data-safety D4: a restore staged from Settings → Data is
        // applied here, before `ContentView` (and so `AppServices.shared`)
        // loads any store. Must stay the first thing the app does.
        DataSafetyLaunch.applyPendingRestoreIfNeeded()
        // add-supplements D5: handles a supplement reminder's "Taken" button,
        // even when that action launched the app in the background -- so it
        // is set here, before launch finishes. (Touches no store until an
        // action arrives, so it doesn't break the rule above.)
        UNUserNotificationCenter.current().delegate = SupplementNotificationHandler.shared
    }

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
