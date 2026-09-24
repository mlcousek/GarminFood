// GarminModels+Inits.swift
//
// Additive public memberwise initialisers for the READ DTOs behind
// `NutritionLogReading` (add-standalone-mode D3), so a non-Garmin reader
// (FoodLogCore's `LocalNutritionReader`, wave 2) can build the exact same
// values the dashboard, copy-meal, Trends and gamification code already
// consume from Garmin. Decoding is untouched: every type keeps its
// synthesized `Decodable` init, and these live in an extension so the
// declarations in GarminModels.swift (and their field docs) stay as they
// are. Parameters follow each type's declaration order and all optional
// ones default to `nil`, matching an absent JSON key.
//
// Tests: GarminModelInitTests (each init equals the decoded fixture).

import Foundation

extension FoodMetaData {
    public init(
        foodId: String,
        foodName: String? = nil,
        foodType: String? = nil,
        brandName: String? = nil,
        source: String? = nil,
        regionCode: String? = nil,
        languageCode: String? = nil,
        customFoodType: String? = nil
    ) {
        self.foodId = foodId
        self.foodName = foodName
        self.foodType = foodType
        self.brandName = brandName
        self.source = source
        self.regionCode = regionCode
        self.languageCode = languageCode
        self.customFoodType = customFoodType
    }
}

extension DailyFoodLog {
    public init(
        mealDate: String? = nil,
        dayStartTime: String? = nil,
        dayEndTime: String? = nil,
        dailyViewType: String? = nil,
        dailyNutritionGoals: NutritionGoals? = nil,
        dailyNutritionContent: DailyNutritionContent? = nil,
        mealDetails: [MealDetail]? = nil,
        loggedFoodsWithServingSizes: [LoggedFood]? = nil
    ) {
        self.mealDate = mealDate
        self.dayStartTime = dayStartTime
        self.dayEndTime = dayEndTime
        self.dailyViewType = dailyViewType
        self.dailyNutritionGoals = dailyNutritionGoals
        self.dailyNutritionContent = dailyNutritionContent
        self.mealDetails = mealDetails
        self.loggedFoodsWithServingSizes = loggedFoodsWithServingSizes
    }
}

extension NutritionGoals {
    public init(
        calories: Double? = nil,
        adjustedCalories: Double? = nil,
        carbs: Double? = nil,
        adjustedCarbs: Double? = nil,
        fat: Double? = nil,
        adjustedFat: Double? = nil,
        protein: Double? = nil,
        adjustedProtein: Double? = nil
    ) {
        self.calories = calories
        self.adjustedCalories = adjustedCalories
        self.carbs = carbs
        self.adjustedCarbs = adjustedCarbs
        self.fat = fat
        self.adjustedFat = adjustedFat
        self.protein = protein
        self.adjustedProtein = adjustedProtein
    }
}

extension DailyNutritionContent {
    public init(
        calories: Double? = nil,
        carbs: Double? = nil,
        fat: Double? = nil,
        protein: Double? = nil,
        otherCalories: Double? = nil,
        caloriesPercentage: Double? = nil,
        fiber: Double? = nil,
        sugar: Double? = nil,
        saturatedFat: Double? = nil,
        monounsaturatedFat: Double? = nil,
        polyunsaturatedFat: Double? = nil,
        cholesterol: Double? = nil,
        sodium: Double? = nil,
        potassium: Double? = nil,
        vitaminA: Double? = nil,
        vitaminC: Double? = nil,
        calcium: Double? = nil,
        iron: Double? = nil
    ) {
        self.calories = calories
        self.carbs = carbs
        self.fat = fat
        self.protein = protein
        self.otherCalories = otherCalories
        self.caloriesPercentage = caloriesPercentage
        self.fiber = fiber
        self.sugar = sugar
        self.saturatedFat = saturatedFat
        self.monounsaturatedFat = monounsaturatedFat
        self.polyunsaturatedFat = polyunsaturatedFat
        self.cholesterol = cholesterol
        self.sodium = sodium
        self.potassium = potassium
        self.vitaminA = vitaminA
        self.vitaminC = vitaminC
        self.calcium = calcium
        self.iron = iron
    }
}

extension MealDetail {
    public init(
        meal: Meal? = nil,
        mealNutritionContent: DailyNutritionContent? = nil,
        mealNutritionGoals: NutritionGoals? = nil,
        loggedFoods: [LoggedFood]? = nil
    ) {
        self.meal = meal
        self.mealNutritionContent = mealNutritionContent
        self.mealNutritionGoals = mealNutritionGoals
        self.loggedFoods = loggedFoods
    }
}

extension Meal {
    public init(
        mealId: Int? = nil,
        mealIndex: Int? = nil,
        mealName: String? = nil,
        displayOrder: Int? = nil,
        startTime: String? = nil,
        endTime: String? = nil,
        goals: NutritionGoals? = nil,
        editable: Bool? = nil,
        translated: Bool? = nil
    ) {
        self.mealId = mealId
        self.mealIndex = mealIndex
        self.mealName = mealName
        self.displayOrder = displayOrder
        self.startTime = startTime
        self.endTime = endTime
        self.goals = goals
        self.editable = editable
        self.translated = translated
    }
}

extension LoggedFood {
    public init(
        id: String? = nil,
        logId: String? = nil,
        logTimestamp: String? = nil,
        logSource: String? = nil,
        logCategory: String? = nil,
        servingQty: Double? = nil,
        foodMetaData: FoodMetaData? = nil,
        nutritionContent: LoggedNutritionContent? = nil,
        isFavorite: Bool? = nil,
        mealId: Int? = nil,
        customMealId: Int? = nil,
        mealTime: String? = nil,
        foodInactive: Bool? = nil,
        type: String? = nil
    ) {
        self.id = id
        self.logId = logId
        self.logTimestamp = logTimestamp
        self.logSource = logSource
        self.logCategory = logCategory
        self.servingQty = servingQty
        self.foodMetaData = foodMetaData
        self.nutritionContent = nutritionContent
        self.isFavorite = isFavorite
        self.mealId = mealId
        self.customMealId = customMealId
        self.mealTime = mealTime
        self.foodInactive = foodInactive
        self.type = type
    }
}

extension LoggedNutritionContent {
    public init(
        servingId: String? = nil,
        servingUnit: String? = nil,
        numberOfUnits: Double? = nil,
        calories: Double? = nil,
        carbs: Double? = nil,
        protein: Double? = nil,
        fat: Double? = nil,
        fiber: Double? = nil,
        sugar: Double? = nil,
        saturatedFat: Double? = nil,
        sodium: Double? = nil,
        unitHasServing: Bool? = nil
    ) {
        self.servingId = servingId
        self.servingUnit = servingUnit
        self.numberOfUnits = numberOfUnits
        self.calories = calories
        self.carbs = carbs
        self.protein = protein
        self.fat = fat
        self.fiber = fiber
        self.sugar = sugar
        self.saturatedFat = saturatedFat
        self.sodium = sodium
        self.unitHasServing = unitHasServing
    }
}

extension MealsForDate {
    public init(
        meals: [Meal]? = nil,
        dailyTimelineStartTime: String? = nil,
        dailyTimelineEndTime: String? = nil
    ) {
        self.meals = meals
        self.dailyTimelineStartTime = dailyTimelineStartTime
        self.dailyTimelineEndTime = dailyTimelineEndTime
    }
}

extension CalorieSummaryDailyResponse {
    public init(
        startDate: String? = nil,
        endDate: String? = nil,
        caloriesBurned: Double? = nil,
        dailyNutritionContents: [CalorieSummaryDay]? = nil
    ) {
        self.startDate = startDate
        self.endDate = endDate
        self.caloriesBurned = caloriesBurned
        self.dailyNutritionContents = dailyNutritionContents
    }
}

extension CalorieSummaryDay {
    public init(
        mealDate: String? = nil,
        nutritionContent: DailyNutritionContent? = nil,
        nutritionGoals: NutritionGoals? = nil
    ) {
        self.mealDate = mealDate
        self.nutritionContent = nutritionContent
        self.nutritionGoals = nutritionGoals
    }
}
