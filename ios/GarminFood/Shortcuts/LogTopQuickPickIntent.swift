// LogTopQuickPickIntent.swift
//
// The "log the top quick-pick food" Siri/Spotlight shortcut (design.md D5,
// tasks.md 20.1). Lives in the GarminFood app target (not `Shared`) because
// App Shortcuts/Siri intents are declared and executed via the app's own
// `AppShortcutsProvider` -- no widget extension involvement at all, unlike
// the Controls in GarminFoodWidget/Controls/. That means this intent
// doesn't need the `.foreground`/authentication-policy dance
// QuickPickLoggingIntents.swift's Control-facing intents need: an App
// Shortcut belonging to the app itself already runs in (or launches) the
// app's own process by default.
//
// Reuses `QuickPickControlAction.performLog(rankIndex:)`
// (Shared/QuickPickLoggingIntents.swift) rather than duplicating the
// ranking/lookup/log logic -- the same shared function the #1 quick-pick
// Control (GarminFoodWidget/Controls/QuickPickControls.swift) uses.

import AppIntents

struct LogTopQuickPickIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Usual Food"
    static var description = IntentDescription("Logs your #1 most-used food in GarminFood.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await QuickPickControlAction.performLog(rankIndex: 0)
        // Task 20.2: donate on a completed voice log so Siri
        // Suggestions/Spotlight improve with use. Best-effort -- a donation
        // failure must never surface as a failed food log.
        try? await IntentDonationManager.shared.donate(intent: LogTopQuickPickIntent())
        return .result(dialog: "Logged your usual.")
    }
}
