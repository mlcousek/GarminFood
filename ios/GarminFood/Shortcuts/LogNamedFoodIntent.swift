// LogNamedFoodIntent.swift
//
// The "log a named food" Siri/Spotlight shortcut (design.md D5, tasks.md
// 20.1's "log a specified food by name (parameterised)"). Runs entirely in
// the app's own process like `LogTopQuickPickIntent` (see that file's
// header for why that needs no `.foreground`/authentication-policy
// handling).
//
// rebuild-food-search task 4.3: it searches through `FoodSearchEngine` --
// the same ranking the catalog uses, over the user's own logged foods and
// Garmin's database (`GET /nutrition-service/food/search`) -- instead of
// logging Garmin's raw first hit with no relevance check. It logs only when
// `SearchConfidence` says the top hit is a clear, full-name match (a food
// the user logs often earns that through the personal boost); otherwise it
// logs NOTHING and reads back up to three candidates, since guessing wrong
// by voice is worse than asking. Open Food Facts isn't asked (its products
// need the in-app Garmin match step), and custom foods are left to the app
// (they log through their backing food and need its serving choice).
//
// Quantity: the food's remembered serving and amount when there is one
// (ServingDefaults), else its first serving at that serving's own declared
// quantity -- Siri has no natural way to ask "which serving, how much?"
// without a multi-turn conversation. The entry stays editable in the app.

import AppIntents
import GarminKit
import FoodLogCore

struct LogNamedFoodIntent: AppIntent {
    static var title: LocalizedStringResource = "Log a Food by Name"
    static var description = IntentDescription("Searches your foods and Garmin's food database for a name and logs the clear best match in GarminFood.")

    @Parameter(title: "Food name")
    var foodName: String

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$foodName) in GarminFood")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // The same store instances the running app uses (AppServices.swift);
        // the engine itself is stateless apart from a term cache, so a
        // one-off instance for this invocation is fine.
        let services = AppServices.shared
        let engine = FoodSearchEngine.standard(
            garmin: services.garminClient,
            customFoods: services.customFoodStore,
            favorites: services.favoriteFoodStore,
            foodCache: services.foodCache,
            usageHistory: services.usageHistory
        )
        let snapshot = await engine.search(foodName, options: SearchOptions(origins: [.local, .garmin]))
        let loggable = snapshot.results.filter { result in
            result.origin.isDirectlyLoggable && result.customDraft == nil && result.food.source != .custom
        }

        let food: Food
        switch SearchConfidence.decide(loggable) {
        case .noMatch:
            if case .failed(let failure)? = snapshot.statuses[.garmin], failure.kind == .signedOut {
                return .result(dialog: "Couldn't search Garmin: sign in again in GarminFood first.")
            }
            return .result(dialog: "Couldn't find \"\(foodName)\" in your foods or Garmin's food database.")
        case .ambiguous(let candidates):
            let names = candidates.map { result in
                result.food.brandName.map { "\(result.food.name) (\($0))" } ?? result.food.name
            }
            return .result(dialog: "Nothing logged -- \"\(foodName)\" could be \(names.joined(separator: ", or ")). Say the full name to log one.")
        case .confident(let top):
            food = top.food
        }

        let remembered = await services.servingDefaults.defaultServing(forFoodId: food.id)
        let rememberedServing = ServingResolution.resolve(remembered, in: food)
        guard let serving = rememberedServing ?? food.servings.first else {
            return .result(dialog: "\(food.name) has no serving Garmin can log.")
        }
        let numberOfUnits = (rememberedServing != nil ? remembered?.numberOfUnits : nil) ?? serving.numberOfUnits

        let date = NutritionDate.todayString()
        try await services.logEntryCoordinator.confirm(
            food: food,
            serving: serving,
            numberOfUnits: numberOfUnits,
            mealType: MealTypeDefaulting.defaultMealType(),
            date: date
        )
        // Records the Siri donation (task 20.2) so deleting this entry in the
        // app can remove it again.
        await services.logObserver?.didLog(food: food, date: date)

        // Bounded wait (add-garmin-auth-and-sync 9.6), and the reply says
        // what actually happened instead of claiming success regardless.
        guard let result = await services.briefDelivery() else {
            return .result(dialog: "Saved \(food.name). It will sync to Garmin in a moment.")
        }
        if QuickPickControlAction.isSignedOut(result.authOutcome) {
            return .result(dialog: "Saved \(food.name), but it can't reach Garmin until you sign in again in GarminFood.")
        }
        if result.delivered.isEmpty {
            return .result(dialog: "Saved \(food.name). It will sync to Garmin when Garmin accepts it.")
        }
        return .result(dialog: "Logged \(food.name) to Garmin.")
    }
}
