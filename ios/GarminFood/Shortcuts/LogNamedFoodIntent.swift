// LogNamedFoodIntent.swift
//
// The "log a named food" Siri/Spotlight shortcut (design.md D5, tasks.md
// 20.1's "log a specified food by name (parameterised)"). Runs entirely in
// the app's own process like `LogTopQuickPickIntent` (see that file's
// header for why that needs no `.foreground`/authentication-policy
// handling), so it can search Garmin's food database directly via
// `FoodCatalogSearch`/`GarminClient` -- the same confirmed-live
// `GET /nutrition-service/food/search` route the app's own catalog screen
// uses (FoodCatalogView.swift).
//
// Logs the FIRST search result's first serving at that serving's own
// declared quantity, since Siri has no natural way to additionally ask
// "which serving, and how much?" without turning a one-line voice command
// into a multi-turn conversation -- a reasonable, explicitly-scoped
// simplification for a voice shortcut, not an oversight. The entry is still
// fully editable afterwards from within the app like any other logged
// entry.

import AppIntents
import GarminKit
import FoodLogCore

struct LogNamedFoodIntent: AppIntent {
    static var title: LocalizedStringResource = "Log a Food by Name"
    static var description = IntentDescription("Searches Garmin's food database for a name and logs the closest match's default serving in GarminFood.")

    @Parameter(title: "Food name")
    var foodName: String

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$foodName) in GarminFood")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let client = GarminClient()
        let foodCache = FoodCacheStore()
        let search = FoodCatalogSearch(searcher: client, foodCache: foodCache)

        let results = try await search.search(term: foodName)
        guard let food = results.first, let serving = food.servings.first else {
            return .result(dialog: "Couldn't find \"\(foodName)\" in Garmin's food database.")
        }

        let usageHistory = UsageHistoryStore()
        let servingDefaults = ServingDefaultStore()
        let outbox = Outbox(processName: "app")
        let coordinator = LogEntryCoordinator(outbox: outbox, usageHistory: usageHistory, servingDefaults: servingDefaults)

        try await coordinator.confirm(
            food: food,
            serving: serving,
            numberOfUnits: serving.numberOfUnits,
            mealType: MealTypeDefaulting.defaultMealType(),
            date: NutritionDate.todayString()
        )
        _ = await outbox.drain(using: client)

        // Task 20.2: best-effort donation, same rationale as LogTopQuickPickIntent.
        try? await IntentDonationManager.shared.donate(intent: self)

        return .result(dialog: "Logged \(food.name).")
    }
}
