// ChallengeTemplates+Signals.swift
//
// Design D11: the 24 creative, real-world long-running challenges ("fish on
// 2 days", "all six colours this week"), evaluated from `DaySignals` via
// `ChallengeKind.signalDays`/`.signalWeek`. Appended to
// `ChallengeCatalog.all`; `ChallengeRotationPolicy` gives each weight 3 so
// they make up most picks, and filters out the ones whose data the owner
// doesn't have (no water data -> no Hydration Station).
//
// Ids are persisted (`ChallengeStore`, `ChallengeHistoryStore`) -- never
// rename one. Titles/subtitles are localized from this package's
// Resources/<lang>.lproj (fixed numbers in the text, so no plurals needed).
//
// Depends on: ChallengeTemplate/ChallengeKind, DayPredicate, WeekPredicate,
// FoodLogCore (FoodTag). Depended on by: ChallengeCatalog.all,
// ChallengeRotationPolicy.

import Foundation
import FoodLogCore

extension ChallengeCatalog {
    static let signalTemplates: [ChallengeTemplate] = [
        ChallengeTemplate(
            id: "sig-something-fishy",
            title: String(localized: "Something Fishy", bundle: .module, comment: "Challenge title: eat fish on 2 days."),
            subtitle: String(localized: "Log fish on 2 different days.", bundle: .module, comment: "Challenge description."),
            category: .varietySeeking, windowDays: 7, xpReward: 80,
            kind: .signalDays(.hasTag(.fish), minDays: 2)
        ),
        ChallengeTemplate(
            id: "sig-five-a-day",
            title: String(localized: "Five-a-Day Week", bundle: .module, comment: "Challenge title: 5 portions of fruit/veg a day."),
            subtitle: String(localized: "Log 5 portions of fruit or vegetables on 4 days.", bundle: .module, comment: "Challenge description."),
            category: .varietySeeking, windowDays: 7, xpReward: 120,
            kind: .signalDays(.anyTagCountAtLeast([.fruit, .vegetable], 5), minDays: 4)
        ),
        ChallengeTemplate(
            id: "sig-rainbow-week",
            title: String(localized: "Rainbow Week", bundle: .module, comment: "Challenge title: all six produce colours in a week."),
            subtitle: String(localized: "Eat all 6 colours of fruit and vegetables.", bundle: .module, comment: "Challenge description."),
            category: .varietySeeking, windowDays: 7, xpReward: 120,
            kind: .signalWeek(.distinctTagsAcrossWeek(prefix: FoodTag.colourPrefix, atLeast: 6))
        ),
        ChallengeTemplate(
            id: "sig-czech-safari",
            title: String(localized: "Czech Supermarket Safari", bundle: .module, comment: "Challenge title: foods from 3 Czech brands."),
            subtitle: String(localized: "Log foods from 3 different Czech brands.", bundle: .module, comment: "Challenge description."),
            category: .varietySeeking, windowDays: 7, xpReward: 80,
            kind: .signalWeek(.distinctCzechBrandsAtLeast(3))
        ),
        ChallengeTemplate(
            id: "sig-fermentation-station",
            title: String(localized: "Fermentation Station", bundle: .module, comment: "Challenge title: fermented food on 4 days."),
            subtitle: String(localized: "Eat something fermented on 4 days.", bundle: .module, comment: "Challenge description."),
            category: .varietySeeking, windowDays: 7, xpReward: 100,
            kind: .signalDays(.hasTag(.fermented), minDays: 4)
        ),
        ChallengeTemplate(
            id: "sig-pulse-check",
            title: String(localized: "Pulse Check", bundle: .module, comment: "Challenge title (pun: pulses = legumes)."),
            subtitle: String(localized: "Eat legumes on 3 days.", bundle: .module, comment: "Challenge description."),
            category: .varietySeeking, windowDays: 10, xpReward: 90,
            kind: .signalDays(.hasTag(.legume), minDays: 3)
        ),
        ChallengeTemplate(
            id: "sig-hydration-station",
            title: String(localized: "Hydration Station", bundle: .module, comment: "Challenge title: water goal on 5 days."),
            subtitle: String(localized: "Reach your water goal on 5 days.", bundle: .module, comment: "Challenge description."),
            category: .goalHitting, windowDays: 7, xpReward: 110,
            kind: .signalDays(.waterGoalMet, minDays: 5)
        ),
        ChallengeTemplate(
            id: "sig-early-bird",
            title: String(localized: "Early Bird Week", bundle: .module, comment: "Challenge title: first log before 9:00."),
            subtitle: String(localized: "Log your first food before 9:00 on 5 days.", bundle: .module, comment: "Challenge description."),
            category: .streakExtension, windowDays: 7, xpReward: 100,
            kind: .signalDays(.firstLogBefore(hour: 9, minute: 0), minDays: 5)
        ),
        ChallengeTemplate(
            id: "sig-kitchen-curfew",
            title: String(localized: "Kitchen Curfew", bundle: .module, comment: "Challenge title: last log before 20:00."),
            subtitle: String(localized: "Log your last food before 20:00 on 5 days.", bundle: .module, comment: "Challenge description."),
            category: .streakExtension, windowDays: 7, xpReward: 110,
            kind: .signalDays(.lastLogBefore(hour: 20, minute: 0), minDays: 5)
        ),
        ChallengeTemplate(
            id: "sig-green-breakfast",
            title: String(localized: "Green Breakfast Club", bundle: .module, comment: "Challenge title: vegetables at breakfast."),
            subtitle: String(localized: "Have vegetables at breakfast on 3 days.", bundle: .module, comment: "Challenge description."),
            category: .varietySeeking, windowDays: 7, xpReward: 90,
            kind: .signalDays(.tagInMeal(.vegetable, .breakfast), minDays: 3)
        ),
        ChallengeTemplate(
            id: "sig-fibre-fanatic",
            title: String(localized: "Fibre Fanatic", bundle: .module, comment: "Challenge title: 30 g fibre a day."),
            subtitle: String(localized: "Eat at least 30 g of fibre on 4 days.", bundle: .module, comment: "Challenge description."),
            category: .goalHitting, windowDays: 7, xpReward: 120,
            kind: .signalDays(.macroAtLeast(.fiber, grams: 30), minDays: 4)
        ),
        ChallengeTemplate(
            id: "sig-sugar-detective",
            title: String(localized: "Sugar Detective", bundle: .module, comment: "Challenge title: little sugar."),
            subtitle: String(localized: "Keep sugar at 40 g or less on 4 days with at least 3 entries.", bundle: .module, comment: "Challenge description."),
            category: .goalHitting, windowDays: 7, xpReward: 120,
            kind: .signalDays(.macroAtMost(.sugar, grams: 40, minEntries: 3), minDays: 4)
        ),
        ChallengeTemplate(
            id: "sig-fuel-and-recover",
            title: String(localized: "Fuel & Recover", bundle: .module, comment: "Challenge title: protein after a workout."),
            subtitle: String(localized: "Log 20 g of protein within an hour after an activity, on 3 days.", bundle: .module, comment: "Challenge description."),
            category: .goalHitting, windowDays: 10, xpReward: 130,
            kind: .signalDays(.proteinAfterActivity(grams: 20, withinMinutes: 60), minDays: 3)
        ),
        ChallengeTemplate(
            id: "sig-active-on-target",
            title: String(localized: "Active and On Target", bundle: .module, comment: "Challenge title: activity + calorie goal on one day."),
            subtitle: String(localized: "Do a 30-minute activity and hit your calorie goal on the same day, on 3 days.", bundle: .module, comment: "Challenge description."),
            category: .goalHitting, windowDays: 7, xpReward: 110,
            kind: .signalDays(.all([.hasActivity(minMinutes: 30), .goalMet(.calories)]), minDays: 3)
        ),
        ChallengeTemplate(
            id: "sig-nut-job",
            title: String(localized: "Nut Job", bundle: .module, comment: "Challenge title (playful): nuts on 4 days."),
            subtitle: String(localized: "Eat nuts on 4 days.", bundle: .module, comment: "Challenge description."),
            category: .varietySeeking, windowDays: 7, xpReward: 70,
            kind: .signalDays(.hasTag(.nuts), minDays: 4)
        ),
        ChallengeTemplate(
            id: "sig-global-kitchen",
            title: String(localized: "Global Kitchen", bundle: .module, comment: "Challenge title: 4 different cuisines."),
            subtitle: String(localized: "Eat dishes from 4 different cuisines.", bundle: .module, comment: "Challenge description."),
            category: .varietySeeking, windowDays: 7, xpReward: 90,
            kind: .signalWeek(.distinctTagsAcrossWeek(prefix: FoodTag.cuisinePrefix, atLeast: 4))
        ),
        ChallengeTemplate(
            id: "sig-tea-time",
            title: String(localized: "Tea Time", bundle: .module, comment: "Challenge title: tea on 5 days."),
            subtitle: String(localized: "Drink tea on 5 days.", bundle: .module, comment: "Challenge description."),
            category: .varietySeeking, windowDays: 7, xpReward: 70,
            kind: .signalDays(.hasTag(.tea), minDays: 5)
        ),
        ChallengeTemplate(
            id: "sig-soup-season",
            title: String(localized: "Soup Season", bundle: .module, comment: "Challenge title: a soup on 4 days (Czech: Polévková sezóna)."),
            subtitle: String(localized: "Have a soup on 4 days.", bundle: .module, comment: "Challenge description."),
            category: .varietySeeking, windowDays: 7, xpReward: 80,
            kind: .signalDays(.hasTag(.soup), minDays: 4)
        ),
        ChallengeTemplate(
            id: "sig-whole-grain-hero",
            title: String(localized: "Whole Grain Hero", bundle: .module, comment: "Challenge title: whole grains on 5 days."),
            subtitle: String(localized: "Eat whole grains on 5 days.", bundle: .module, comment: "Challenge description."),
            category: .varietySeeking, windowDays: 7, xpReward: 90,
            kind: .signalDays(.hasTag(.wholeGrain), minDays: 5)
        ),
        ChallengeTemplate(
            id: "sig-egg-cellent",
            title: String(localized: "Egg-cellent Week", bundle: .module, comment: "Challenge title (pun on excellent): eggs on 3 days."),
            subtitle: String(localized: "Eat eggs on 3 days.", bundle: .module, comment: "Challenge description."),
            category: .varietySeeking, windowDays: 7, xpReward: 60,
            kind: .signalDays(.hasTag(.egg), minDays: 3)
        ),
        ChallengeTemplate(
            id: "sig-no-soda",
            title: String(localized: "Soda-Free Week", bundle: .module, comment: "Challenge title: no sugary drinks."),
            subtitle: String(localized: "Skip sugary drinks on 6 days with at least 2 entries.", bundle: .module, comment: "Challenge description."),
            category: .goalHitting, windowDays: 7, xpReward: 120,
            kind: .signalDays(.noTag(.sugaryDrink, minEntries: 2), minDays: 6)
        ),
        ChallengeTemplate(
            id: "sig-colour-day",
            title: String(localized: "Paint the Plate", bundle: .module, comment: "Challenge title: 4 produce colours in one day."),
            subtitle: String(localized: "Eat 4 colours of fruit and vegetables in one day, on 2 days.", bundle: .module, comment: "Challenge description."),
            category: .varietySeeking, windowDays: 7, xpReward: 90,
            kind: .signalDays(.distinctTagsAtLeast(prefix: FoodTag.colourPrefix, 4), minDays: 2)
        ),
        ChallengeTemplate(
            id: "sig-new-horizons",
            title: String(localized: "New Horizons", bundle: .module, comment: "Challenge title: 5 never-logged foods."),
            subtitle: String(localized: "Log 5 foods you have never logged before.", bundle: .module, comment: "Challenge description."),
            category: .varietySeeking, windowDays: 7, xpReward: 90,
            kind: .signalWeek(.newFoodsAtLeast(5))
        ),
        ChallengeTemplate(
            id: "sig-protein-breakfast",
            title: String(localized: "Protein Breakfast", bundle: .module, comment: "Challenge title: 20 g protein at breakfast."),
            subtitle: String(localized: "Eat at least 20 g of protein at breakfast on 4 days.", bundle: .module, comment: "Challenge description."),
            category: .goalHitting, windowDays: 7, xpReward: 110,
            kind: .signalDays(.mealMacroAtLeast(.breakfast, .protein, grams: 20), minDays: 4)
        ),
    ]
}
