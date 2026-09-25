// BingoTaskCatalog.swift
//
// add-weekly-bingo design D2 + D6: the 35-task pool bingo cards are drawn
// from (10 easy, 14 medium, 11 hard) and the seven bingo badges. Pure data;
// `BingoCardGenerator` picks from it, `BingoEvaluator` judges it.
//
// Adding a task later is one row here. Ids are persisted in cards and are
// never removed or reused (a card whose id vanished treats that square as
// FREE -- `BingoEvaluator`). Display text is localized at first use, like
// `AchievementCatalog`; nothing persisted contains it.
//
// Rules the shared vocabulary has no single case for are composed from
// existing cases (`.all`/`.any`) -- DayPredicate must not grow in wave 2.
//
// Depends on: BingoTask, DayPredicate, WeekPredicate, FoodLogCore.FoodTag,
// AchievementDefinition. Depended on by: BingoCardGenerator,
// BingoEvaluator, WeeklyBingoFeature, BingoTaskCatalogTests.

import Foundation
import FoodLogCore

public enum BingoTaskCatalog {
    /// The centre square's id (and what an unknown id is treated as).
    public static let freeId = "free"

    // MARK: - Shared rule pieces

    static let fishOrSeafood: DayPredicate = .any([.hasTag(.fish), .hasTag(.seafood)])

    static let nonCzechCuisines: [FoodTag] = [
        .cuisineItalian, .cuisineJapanese, .cuisineChinese, .cuisineIndian, .cuisineMexican,
        .cuisineThai, .cuisineVietnamese, .cuisineGreek, .cuisineTurkish, .cuisineSpanish,
        .cuisineFrench, .cuisineAmerican, .cuisineKorean, .cuisineMiddleEastern,
    ]

    // MARK: - Tasks

    public static let all: [BingoTask] = easy + medium + hard

    public static func task(id: String) -> BingoTask? {
        byId[id]
    }

    private static let byId: [String: BingoTask] = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

    static let easy: [BingoTask] = [
        BingoTask(
            id: "e-early-log",
            title: String(localized: "Rise & Log", bundle: .module, comment: "Bingo task title: first log of the day before 9:00."),
            detail: String(localized: "Log your first food before 9:00.", bundle: .module, comment: "Bingo task rule."),
            difficulty: .easy, family: "time",
            scope: .day(.firstLogBefore(hour: 9, minute: 0)),
            symbol: "sunrise.fill"
        ),
        BingoTask(
            id: "e-fruit",
            title: String(localized: "An Apple a Day", bundle: .module, comment: "Bingo task title: log any fruit."),
            detail: String(localized: "Log any fruit.", bundle: .module, comment: "Bingo task rule."),
            difficulty: .easy, family: "fruit",
            scope: .day(.hasTag(.fruit)),
            symbol: "leaf.fill"
        ),
        BingoTask(
            id: "e-veg-lunch",
            title: String(localized: "Green Lunch", bundle: .module, comment: "Bingo task title: a vegetable at lunch."),
            detail: String(localized: "Have a vegetable with lunch.", bundle: .module, comment: "Bingo task rule."),
            difficulty: .easy, family: "vegmeal",
            scope: .day(.tagInMeal(.vegetable, .lunch)),
            symbol: "carrot.fill"
        ),
        BingoTask(
            id: "e-three-meals",
            title: String(localized: "Square Meals", bundle: .module, comment: "Bingo task title: breakfast, lunch and dinner on one day."),
            detail: String(localized: "Log breakfast, lunch and dinner on the same day.", bundle: .module, comment: "Bingo task rule."),
            difficulty: .easy, family: "meals",
            scope: .day(.all([.mealLogged(.breakfast), .mealLogged(.lunch), .mealLogged(.dinner)])),
            symbol: "fork.knife"
        ),
        BingoTask(
            id: "e-new-food",
            title: String(localized: "Something New", bundle: .module, comment: "Bingo task title: a food never logged before."),
            detail: String(localized: "Log a food you have never logged before.", bundle: .module, comment: "Bingo task rule."),
            difficulty: .easy, family: "novelty",
            scope: .day(.newFood),
            symbol: "sparkles"
        ),
        BingoTask(
            id: "e-soup",
            title: String(localized: "Polévka Day", bundle: .module, comment: "Bingo task title: a soup. 'Polévka' is Czech for soup; keep it as is in English."),
            detail: String(localized: "Have a soup.", bundle: .module, comment: "Bingo task rule."),
            difficulty: .easy, family: "soup",
            scope: .day(.hasTag(.soup)),
            symbol: "takeoutbag.and.cup.and.straw.fill"
        ),
        BingoTask(
            id: "e-tea",
            title: String(localized: "Tea Break", bundle: .module, comment: "Bingo task title: drink tea."),
            detail: String(localized: "Log a tea.", bundle: .module, comment: "Bingo task rule."),
            difficulty: .easy, family: "drinks",
            scope: .day(.hasTag(.tea)),
            symbol: "mug.fill"
        ),
        BingoTask(
            id: "e-fermented",
            title: String(localized: "Friendly Bacteria", bundle: .module, comment: "Bingo task title: a fermented food."),
            detail: String(localized: "Have a fermented food, like yogurt, kefir or sauerkraut.", bundle: .module, comment: "Bingo task rule."),
            difficulty: .easy, family: "fermented",
            scope: .day(.hasTag(.fermented)),
            symbol: "testtube.2"
        ),
        BingoTask(
            id: "e-nuts",
            title: String(localized: "Go Nuts", bundle: .module, comment: "Bingo task title: eat nuts."),
            detail: String(localized: "Have some nuts.", bundle: .module, comment: "Bingo task rule."),
            difficulty: .easy, family: "nuts",
            scope: .day(.hasTag(.nuts)),
            symbol: "circle.grid.2x2.fill"
        ),
        BingoTask(
            id: "e-egg",
            title: String(localized: "Egg Day", bundle: .module, comment: "Bingo task title: eat eggs."),
            detail: String(localized: "Have eggs.", bundle: .module, comment: "Bingo task rule."),
            difficulty: .easy, family: "egg",
            scope: .day(.hasTag(.egg)),
            symbol: "oval.portrait.fill"
        ),
    ]

    static let medium: [BingoTask] = [
        BingoTask(
            id: "m-fish",
            title: String(localized: "Something Fishy", bundle: .module, comment: "Bingo task title: fish or seafood."),
            detail: String(localized: "Have fish or seafood.", bundle: .module, comment: "Bingo task rule."),
            difficulty: .medium, family: "fish",
            scope: .day(fishOrSeafood),
            symbol: "fish.fill"
        ),
        BingoTask(
            id: "m-three-fruits",
            title: String(localized: "Fruit Salad", bundle: .module, comment: "Bingo task title: 3 fruit entries in one day."),
            detail: String(localized: "Log fruit 3 times in one day.", bundle: .module, comment: "Bingo task rule."),
            difficulty: .medium, family: "fruit",
            scope: .day(.tagCountAtLeast(.fruit, 3)),
            symbol: "basket.fill"
        ),
        BingoTask(
            id: "m-water-goal",
            title: String(localized: "Hydrated", bundle: .module, comment: "Bingo task title: water goal met."),
            detail: String(localized: "Reach your water goal.", bundle: .module, comment: "Bingo task rule."),
            difficulty: .medium, family: "water",
            scope: .day(.waterGoalMet),
            symbol: "drop.fill"
        ),
        BingoTask(
            id: "m-czech-brand",
            title: String(localized: "Local Hero", bundle: .module, comment: "Bingo task title: a Czech brand not logged before."),
            detail: String(localized: "Log a Czech brand you have never logged before.", bundle: .module, comment: "Bingo task rule."),
            difficulty: .medium, family: "brands",
            scope: .day(.newCzechBrand),
            symbol: "flag.fill"
        ),
        BingoTask(
            id: "m-no-soda",
            title: String(localized: "Soda-Free Day", bundle: .module, comment: "Bingo task title: a day without sugary drinks."),
            detail: String(localized: "Log at least 3 entries in a day and no sugary drink.", bundle: .module, comment: "Bingo task rule."),
            difficulty: .medium, family: "drinks",
            scope: .day(.noTag(.sugaryDrink, minEntries: 3)),
            symbol: "nosign"
        ),
        BingoTask(
            id: "m-protein-2",
            title: String(localized: "Protein Double", bundle: .module, comment: "Bingo task title: protein goal on 2 days this week."),
            detail: String(localized: "Reach your protein goal on 2 days this week.", bundle: .module, comment: "Bingo task rule."),
            difficulty: .medium, family: "goal",
            scope: .week(.daysSatisfying(.goalMet(.protein), atLeast: 2)),
            symbol: "bolt.fill"
        ),
        BingoTask(
            id: "m-veg-breakfast",
            title: String(localized: "Veggie Sunrise", bundle: .module, comment: "Bingo task title: a vegetable at breakfast."),
            detail: String(localized: "Have a vegetable with breakfast.", bundle: .module, comment: "Bingo task rule."),
            difficulty: .medium, family: "vegmeal",
            scope: .day(.tagInMeal(.vegetable, .breakfast)),
            symbol: "sun.horizon.fill"
        ),
        BingoTask(
            id: "m-legume",
            title: String(localized: "Pulse Day", bundle: .module, comment: "Bingo task title: legumes (beans, lentils, peas)."),
            detail: String(localized: "Have legumes: beans, lentils, peas or chickpeas.", bundle: .module, comment: "Bingo task rule."),
            difficulty: .medium, family: "legume",
            scope: .day(.hasTag(.legume)),
            symbol: "circle.hexagongrid.fill"
        ),
        BingoTask(
            id: "m-colours-4",
            title: String(localized: "Painted Plate", bundle: .module, comment: "Bingo task title: 4 food colours in one day."),
            detail: String(localized: "Eat 4 different food colours in one day.", bundle: .module, comment: "Bingo task rule."),
            difficulty: .medium, family: "colours",
            scope: .day(.distinctTagsAtLeast(prefix: FoodTag.colourPrefix, 4)),
            symbol: "paintpalette.fill"
        ),
        BingoTask(
            id: "m-cuisine",
            title: String(localized: "Passport Stamp", bundle: .module, comment: "Bingo task title: any non-Czech cuisine."),
            detail: String(localized: "Have a dish from any cuisine other than Czech.", bundle: .module, comment: "Bingo task rule."),
            difficulty: .medium, family: "cuisine",
            scope: .day(.any(nonCzechCuisines.map { DayPredicate.hasTag($0) })),
            symbol: "globe.europe.africa.fill"
        ),
        BingoTask(
            id: "m-early-dinner",
            title: String(localized: "Early Dinner", bundle: .module, comment: "Bingo task title: dinner logged and nothing logged after 19:30."),
            detail: String(localized: "Log dinner and finish logging before 19:30.", bundle: .module, comment: "Bingo task rule."),
            difficulty: .medium, family: "time",
            scope: .day(.all([.mealLogged(.dinner), .lastLogBefore(hour: 19, minute: 30)])),
            symbol: "moon.fill"
        ),
        BingoTask(
            id: "m-whole-grain",
            title: String(localized: "Whole Grain", bundle: .module, comment: "Bingo task title: a whole-grain food."),
            detail: String(localized: "Have a whole-grain food.", bundle: .module, comment: "Bingo task rule."),
            difficulty: .medium, family: "grain",
            scope: .day(.hasTag(.wholeGrain)),
            symbol: "laurel.leading"
        ),
        BingoTask(
            id: "m-refuel",
            title: String(localized: "Refuel", bundle: .module, comment: "Bingo task title: protein soon after a workout."),
            detail: String(localized: "Log at least 20 g of protein within 60 minutes after an activity.", bundle: .module, comment: "Bingo task rule."),
            difficulty: .medium, family: "sport",
            scope: .day(.proteinAfterActivity(grams: 20, withinMinutes: 60)),
            symbol: "figure.run"
        ),
        BingoTask(
            id: "m-calories-2",
            title: String(localized: "On Target Twice", bundle: .module, comment: "Bingo task title: calorie goal on 2 days this week."),
            detail: String(localized: "Reach your calorie goal on 2 days this week.", bundle: .module, comment: "Bingo task rule."),
            difficulty: .medium, family: "goal",
            scope: .week(.daysSatisfying(.goalMet(.calories), atLeast: 2)),
            symbol: "target"
        ),
    ]

    static let hard: [BingoTask] = [
        BingoTask(
            id: "h-fish-2",
            title: String(localized: "Fish Twice", bundle: .module, comment: "Bingo task title: fish on 2 days this week."),
            detail: String(localized: "Have fish or seafood on 2 days this week.", bundle: .module, comment: "Bingo task rule."),
            difficulty: .hard, family: "fish",
            scope: .week(.daysSatisfying(fishOrSeafood, atLeast: 2)),
            symbol: "fish.circle.fill"
        ),
        BingoTask(
            id: "h-protein-3",
            title: String(localized: "Protein Hat-Trick", bundle: .module, comment: "Bingo task title: protein goal on 3 days this week."),
            detail: String(localized: "Reach your protein goal on 3 days this week.", bundle: .module, comment: "Bingo task rule."),
            difficulty: .hard, family: "goal",
            scope: .week(.daysSatisfying(.goalMet(.protein), atLeast: 3)),
            symbol: "bolt.circle.fill"
        ),
        BingoTask(
            id: "h-water-4",
            title: String(localized: "Water Works", bundle: .module, comment: "Bingo task title: water goal on 4 days this week."),
            detail: String(localized: "Reach your water goal on 4 days this week.", bundle: .module, comment: "Bingo task rule."),
            difficulty: .hard, family: "water",
            scope: .week(.daysSatisfying(.waterGoalMet, atLeast: 4)),
            symbol: "drop.circle.fill"
        ),
        BingoTask(
            id: "h-ten-foods",
            title: String(localized: "Variety Show", bundle: .module, comment: "Bingo task title: 10 different foods in one day."),
            detail: String(localized: "Log 10 different foods in one day.", bundle: .module, comment: "Bingo task rule."),
            difficulty: .hard, family: "novelty",
            scope: .day(.distinctFoodsAtLeast(10)),
            symbol: "square.grid.3x3.fill"
        ),
        BingoTask(
            id: "h-meatless",
            title: String(localized: "Meat-Free Day", bundle: .module, comment: "Bingo task title: a day without meat, poultry or fish."),
            detail: String(localized: "Log at least 3 entries in a day with no meat, poultry or fish.", bundle: .module, comment: "Bingo task rule."),
            difficulty: .hard, family: "meat",
            scope: .day(.all([
                .noTag(.meat, minEntries: 3),
                .noTag(.redMeat, minEntries: 3),
                .noTag(.poultry, minEntries: 3),
                .noTag(.fish, minEntries: 3),
                .noTag(.seafood, minEntries: 3),
            ])),
            symbol: "leaf.circle.fill"
        ),
        BingoTask(
            id: "h-fibre-30",
            title: String(localized: "Fibre Day", bundle: .module, comment: "Bingo task title: at least 30 g of fibre in one day."),
            detail: String(localized: "Eat at least 30 g of fibre in one day.", bundle: .module, comment: "Bingo task rule."),
            difficulty: .hard, family: "macros",
            scope: .day(.macroAtLeast(.fiber, grams: 30)),
            symbol: "chart.bar.fill"
        ),
        BingoTask(
            id: "h-sugar-low",
            title: String(localized: "Sugar Low", bundle: .module, comment: "Bingo task title: at most 25 g of sugar in a day."),
            detail: String(localized: "Keep sugar at 25 g or less on a day with at least 3 entries.", bundle: .module, comment: "Bingo task rule."),
            difficulty: .hard, family: "macros",
            scope: .day(.macroAtMost(.sugar, grams: 25, minEntries: 3)),
            symbol: "cube.fill"
        ),
        BingoTask(
            id: "h-five-a-day",
            title: String(localized: "Five a Day", bundle: .module, comment: "Bingo task title: 5 fruit or vegetable entries in one day."),
            detail: String(localized: "Log fruit or vegetables 5 times in one day.", bundle: .module, comment: "Bingo task rule."),
            difficulty: .hard, family: "fruit",
            scope: .day(.anyTagCountAtLeast([.fruit, .vegetable], 5)),
            symbol: "hand.raised.fill"
        ),
        BingoTask(
            id: "h-rainbow",
            title: String(localized: "Full Rainbow", bundle: .module, comment: "Bingo task title: all 6 food colours across the week."),
            detail: String(localized: "Eat all 6 food colours across this week.", bundle: .module, comment: "Bingo task rule."),
            difficulty: .hard, family: "colours",
            scope: .week(.distinctTagsAcrossWeek(prefix: FoodTag.colourPrefix, atLeast: 6)),
            symbol: "rainbow"
        ),
        BingoTask(
            id: "h-earned-it",
            title: String(localized: "Earned the Meal", bundle: .module, comment: "Bingo task title: a 30-minute activity and the calorie goal on the same day."),
            detail: String(localized: "Do an activity of at least 30 minutes and reach your calorie goal the same day.", bundle: .module, comment: "Bingo task rule."),
            difficulty: .hard, family: "sport",
            scope: .day(.all([.hasActivity(minMinutes: 30), .goalMet(.calories)])),
            symbol: "medal.fill"
        ),
        BingoTask(
            id: "h-clean-sweep",
            title: String(localized: "Clean Sweep", bundle: .module, comment: "Bingo task title: all four goals met in one day."),
            detail: String(localized: "Reach all four goals (calories, protein, carbs, fat) in one day.", bundle: .module, comment: "Bingo task rule."),
            difficulty: .hard, family: "goal",
            scope: .day(.all([.goalMet(.calories), .goalMet(.protein), .goalMet(.carbs), .goalMet(.fat)])),
            symbol: "checkmark.seal.fill"
        ),
    ]

    // MARK: - Badges (design D6)

    public static let firstLineBadgeId = "bingo.first-line"
    public static let fourCornersBadgeId = "bingo.four-corners"
    public static let xMarksBadgeId = "bingo.x-marks"
    public static let lines50BadgeId = "bingo.lines-50"
    public static let blackout1BadgeId = "bingo.blackout-1"
    public static let blackout4BadgeId = "bingo.blackout-4"
    public static let blackout12BadgeId = "bingo.blackout-12"

    public static let badges: [AchievementDefinition] = [
        badge(
            id: firstLineBadgeId,
            title: String(localized: "Bingo!", bundle: .module, comment: "Badge title: first bingo line ever."),
            subtitle: String(localized: "Complete your first bingo line.", bundle: .module, comment: "Badge description."),
            symbol: "line.diagonal",
            rarity: .common
        ),
        badge(
            id: fourCornersBadgeId,
            title: String(localized: "Four Corners", bundle: .module, comment: "Badge title: all four corner squares in one week."),
            subtitle: String(localized: "Complete all four corner squares of one card.", bundle: .module, comment: "Badge description."),
            symbol: "square.dashed",
            rarity: .uncommon
        ),
        badge(
            id: xMarksBadgeId,
            title: String(localized: "X Marks the Spot", bundle: .module, comment: "Badge title: both diagonals in one week."),
            subtitle: String(localized: "Complete both diagonals of one card.", bundle: .module, comment: "Badge description."),
            symbol: "xmark",
            rarity: .uncommon
        ),
        badge(
            id: lines50BadgeId,
            title: String(localized: "Line Dancer", bundle: .module, comment: "Badge title: 50 bingo lines in total."),
            subtitle: String(localized: "Complete 50 bingo lines in total.", bundle: .module, comment: "Badge description."),
            symbol: "figure.dance",
            rarity: .rare
        ),
        badge(
            id: blackout1BadgeId,
            title: String(localized: "Blackout", bundle: .module, comment: "Badge title: first full bingo card."),
            subtitle: String(localized: "Complete a whole bingo card.", bundle: .module, comment: "Badge description."),
            symbol: "square.grid.3x3.fill",
            rarity: .rare
        ),
        badge(
            id: blackout4BadgeId,
            title: String(localized: "Card Shark", bundle: .module, comment: "Badge title: 4 full bingo cards."),
            subtitle: String(localized: "Complete 4 whole bingo cards.", bundle: .module, comment: "Badge description."),
            symbol: "suit.spade.fill",
            rarity: .epic
        ),
        badge(
            id: blackout12BadgeId,
            title: String(localized: "Bingo Hall Legend", bundle: .module, comment: "Badge title: 12 full bingo cards."),
            subtitle: String(localized: "Complete 12 whole bingo cards.", bundle: .module, comment: "Badge description."),
            symbol: "crown.fill",
            rarity: .legendary
        ),
    ]

    private static func badge(id: String, title: String, subtitle: String, symbol: String, rarity: AchievementRarity) -> AchievementDefinition {
        AchievementDefinition(
            id: id,
            title: title,
            subtitle: subtitle,
            category: .challenges,
            badgeSymbol: symbol,
            condition: .featureEvaluated,
            rarityOverride: rarity,
            featureId: WeeklyBingoFeature.id
        )
    }
}
