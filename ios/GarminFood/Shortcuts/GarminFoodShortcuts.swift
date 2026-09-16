// GarminFoodShortcuts.swift
//
// Siri/Spotlight entry points (design.md D5, tasks.md 20.1): three
// shortcuts, comfortably under Apple's 10-shortcut compile-time cap and
// within its 2-5 recommendation (siri-and-shortcuts spec's "no more than 5"
// requirement). Every phrase includes `\(.applicationName)` per Apple's own
// requirement -- omitting it is a compile-time diagnostic on
// `AppShortcutsProvider`, not just a style guideline.
//
// `OpenBarcodeScannerIntent` is reused as-is from `Shared/` (the same type
// the barcode-scan Control uses) -- one intent, two entry points (Siri and
// the Control), matching openspec/config.yaml's "small, composable" spirit.

import AppIntents

struct GarminFoodShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogTopQuickPickIntent(),
            phrases: [
                "Log my usual food in \(.applicationName)",
                "Log the usual in \(.applicationName)"
            ],
            shortTitle: "Log Usual",
            systemImageName: "fork.knife"
        )
        AppShortcut(
            intent: LogNamedFoodIntent(),
            phrases: [
                "Log a food in \(.applicationName)",
                "Log a food by name in \(.applicationName)"
            ],
            shortTitle: "Log a Food",
            systemImageName: "text.magnifyingglass"
        )
        AppShortcut(
            intent: OpenBarcodeScannerIntent(),
            phrases: [
                "Scan a barcode in \(.applicationName)",
                "Open \(.applicationName) to scan a barcode"
            ],
            shortTitle: "Scan Barcode",
            systemImageName: "barcode.viewfinder"
        )
    }
}
