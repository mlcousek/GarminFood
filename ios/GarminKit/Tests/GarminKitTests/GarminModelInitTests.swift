// GarminModelInitTests.swift
//
// add-standalone-mode D3/D13: the additive public inits on the read DTOs
// (declared in the type bodies in GarminModels.swift) must build values EQUAL to what the decoder
// produces from Garmin's JSON, field for field -- a local reader (wave 2)
// builds these by hand and the dashboard/Trends/gamification code must not
// be able to tell the difference. Fixtures follow the shapes recorded in
// docs/garmin-routes.json (daily food log, meals, calorie summary).

import XCTest
@testable import GarminKit

final class GarminModelInitTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    func testDailyFoodLogInitEqualsDecodedFixture() throws {
        let json = """
        {
          "mealDate": "2026-09-22",
          "dayStartTime": "04:00:00",
          "dayEndTime": "03:59:59",
          "dailyViewType": "DAILY",
          "dailyNutritionGoals": {
            "calories": 2300, "adjustedCalories": 3128,
            "carbs": 316, "adjustedCarbs": 430,
            "fat": 64, "adjustedFat": 87,
            "protein": 115, "adjustedProtein": 156
          },
          "dailyNutritionContent": { "calories": 540, "carbs": 60.5, "fat": 20, "protein": 30, "otherCalories": 0 },
          "mealDetails": [
            {
              "meal": {
                "mealId": 111, "mealIndex": 0, "mealName": "BREAKFAST", "displayOrder": 1,
                "startTime": "05:00:00", "endTime": "10:00:00",
                "goals": { "calories": 575 }, "editable": true, "translated": false
              },
              "mealNutritionContent": {
                "calories": 540, "carbs": 60.5, "fat": 20, "protein": 30,
                "caloriesPercentage": 94, "fiber": 4, "sugar": 12, "saturatedFat": 6,
                "monounsaturatedFat": 5, "polyunsaturatedFat": 3, "cholesterol": 40,
                "sodium": 300, "potassium": 250, "vitaminA": 1, "vitaminC": 2,
                "calcium": 3, "iron": 4
              },
              "mealNutritionGoals": { "calories": 575, "carbs": 79, "fat": 16, "protein": 29 },
              "loggedFoods": [
                {
                  "id": "123", "logId": "abc123def", "logTimestamp": "2026-09-22T07:15:00.0",
                  "logSource": "GCW", "logCategory": "REGULAR_LOG", "servingQty": 1.5,
                  "foodMetaData": {
                    "foodId": "123", "foodName": "Ovesné vločky", "foodType": "GENERIC",
                    "brandName": "Emco", "source": "GARMIN", "regionCode": "CZ",
                    "languageCode": "cs", "customFoodType": "PERSONAL"
                  },
                  "nutritionContent": {
                    "servingId": "s1", "servingUnit": "g", "numberOfUnits": 100,
                    "calories": 540, "carbs": 60.5, "protein": 30, "fat": 20,
                    "fiber": 4, "sugar": 12, "saturatedFat": 6, "sodium": 300,
                    "unitHasServing": true
                  },
                  "isFavorite": false, "mealId": 111, "customMealId": 7,
                  "mealTime": "07:15:00", "foodInactive": false, "type": "FOOD"
                }
              ]
            },
            { "meal": { "mealId": 114, "mealName": "SNACKS" }, "mealNutritionContent": {} }
          ]
        }
        """
        let decoded = try decode(DailyFoodLog.self, json)

        let logged = LoggedFood(
            id: "123",
            logId: "abc123def",
            logTimestamp: "2026-09-22T07:15:00.0",
            logSource: "GCW",
            logCategory: "REGULAR_LOG",
            servingQty: 1.5,
            foodMetaData: FoodMetaData(
                foodId: "123",
                foodName: "Ovesné vločky",
                foodType: "GENERIC",
                brandName: "Emco",
                source: "GARMIN",
                regionCode: "CZ",
                languageCode: "cs",
                customFoodType: "PERSONAL"
            ),
            nutritionContent: LoggedNutritionContent(
                servingId: "s1",
                servingUnit: "g",
                numberOfUnits: 100,
                calories: 540,
                carbs: 60.5,
                protein: 30,
                fat: 20,
                fiber: 4,
                sugar: 12,
                saturatedFat: 6,
                sodium: 300,
                unitHasServing: true
            ),
            isFavorite: false,
            mealId: 111,
            customMealId: 7,
            mealTime: "07:15:00",
            foodInactive: false,
            type: "FOOD"
        )
        let built = DailyFoodLog(
            mealDate: "2026-09-22",
            dayStartTime: "04:00:00",
            dayEndTime: "03:59:59",
            dailyViewType: "DAILY",
            dailyNutritionGoals: NutritionGoals(
                calories: 2300, adjustedCalories: 3128,
                carbs: 316, adjustedCarbs: 430,
                fat: 64, adjustedFat: 87,
                protein: 115, adjustedProtein: 156
            ),
            dailyNutritionContent: DailyNutritionContent(calories: 540, carbs: 60.5, fat: 20, protein: 30, otherCalories: 0),
            mealDetails: [
                MealDetail(
                    meal: Meal(
                        mealId: 111, mealIndex: 0, mealName: "BREAKFAST", displayOrder: 1,
                        startTime: "05:00:00", endTime: "10:00:00",
                        goals: NutritionGoals(calories: 575), editable: true, translated: false
                    ),
                    mealNutritionContent: DailyNutritionContent(
                        calories: 540, carbs: 60.5, fat: 20, protein: 30,
                        caloriesPercentage: 94, fiber: 4, sugar: 12, saturatedFat: 6,
                        monounsaturatedFat: 5, polyunsaturatedFat: 3, cholesterol: 40,
                        sodium: 300, potassium: 250, vitaminA: 1, vitaminC: 2,
                        calcium: 3, iron: 4
                    ),
                    mealNutritionGoals: NutritionGoals(calories: 575, carbs: 79, fat: 16, protein: 29),
                    loggedFoods: [logged]
                ),
                // An empty meal: Garmin sends `{}` for its content, which
                // decodes to an all-nil value, not to `nil`.
                MealDetail(meal: Meal(mealId: 114, mealName: "SNACKS"), mealNutritionContent: DailyNutritionContent())
            ]
        )

        XCTAssertEqual(built, decoded)
        // Behaviour hanging off the built value matches too.
        XCTAssertEqual(built.mealDetails?.first?.loggedFoods?.first?.foodId, "123")
        XCTAssertEqual(built.mealDetails?.first?.loggedFoods?.first?.isFromThisApp, true)
    }

    func testEmptyDailyFoodLogInitEqualsEmptyObject() throws {
        XCTAssertEqual(DailyFoodLog(), try decode(DailyFoodLog.self, "{}"))
        XCTAssertEqual(LoggedFood(), try decode(LoggedFood.self, "{}"))
    }

    func testMealsForDateInitEqualsDecodedFixture() throws {
        let json = """
        {
          "meals": [
            { "mealId": 111, "mealName": "BREAKFAST", "startTime": "05:00:00", "endTime": "10:00:00" },
            { "mealId": 114, "mealName": "SNACKS" }
          ],
          "dailyTimelineStartTime": "04:00:00",
          "dailyTimelineEndTime": "03:59:59"
        }
        """
        let built = MealsForDate(
            meals: [
                Meal(mealId: 111, mealName: "BREAKFAST", startTime: "05:00:00", endTime: "10:00:00"),
                Meal(mealId: 114, mealName: "SNACKS")
            ],
            dailyTimelineStartTime: "04:00:00",
            dailyTimelineEndTime: "03:59:59"
        )

        XCTAssertEqual(built, try decode(MealsForDate.self, json))
    }

    func testCalorieSummaryInitEqualsDecodedFixture() throws {
        // A day with nothing logged is a bare `{ mealDate }` (the route's
        // confirmed gotcha): both optionals stay nil.
        let json = """
        {
          "startDate": "2026-09-21",
          "endDate": "2026-09-22",
          "caloriesBurned": 3283,
          "dailyNutritionContents": [
            { "mealDate": "2026-09-21" },
            {
              "mealDate": "2026-09-22",
              "nutritionContent": { "calories": 1800, "carbs": 200, "fat": 60, "protein": 110 },
              "nutritionGoals": { "calories": 2300, "adjustedCalories": 3128 }
            }
          ]
        }
        """
        let built = CalorieSummaryDailyResponse(
            startDate: "2026-09-21",
            endDate: "2026-09-22",
            caloriesBurned: 3283,
            dailyNutritionContents: [
                CalorieSummaryDay(mealDate: "2026-09-21"),
                CalorieSummaryDay(
                    mealDate: "2026-09-22",
                    nutritionContent: DailyNutritionContent(calories: 1800, carbs: 200, fat: 60, protein: 110),
                    nutritionGoals: NutritionGoals(calories: 2300, adjustedCalories: 3128)
                )
            ]
        )

        XCTAssertEqual(built, try decode(CalorieSummaryDailyResponse.self, json))
    }

    func testDailyUserSummaryInitEqualsDecodedFixture() throws {
        let json = """
        { "calendarDate": "2026-09-22", "activeKilocalories": 1031, "bmrKilocalories": 2252, "totalKilocalories": 3283 }
        """
        let built = DailyUserSummary(
            calendarDate: "2026-09-22",
            activeKilocalories: 1031,
            bmrKilocalories: 2252,
            totalKilocalories: 3283
        )

        XCTAssertEqual(built, try decode(DailyUserSummary.self, json))
    }

    func testGarminClientIsANutritionLogReader() {
        // Compile-time pin of the conformance the consumers rely on.
        func requireReader<T: NutritionLogReading>(_ type: T.Type) -> Bool { true }
        XCTAssertTrue(requireReader(GarminClient.self))
    }
}
