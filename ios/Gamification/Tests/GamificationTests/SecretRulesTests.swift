// SecretRulesTests.swift
//
// add-secret-achievements tasks 1.3 / design D5: one positive and at least
// one negative case per secret rule, with literal `DaySignals` (see
// SecretTestSupport), plus the catalog's shape (ids unique, all hidden
// except the keeper, Czech text present). Pure functions only -- no stores.

import XCTest
import FoodLogCore
@testable import Gamification

final class SecretRulesTests: XCTestCase {
    private typealias F = SecretFixtures

    /// Thursday 2026-09-24 (ISO week 2026-W39).
    private let today = SecretFixtures.date(2026, 9, 24)

    private func holds(
        _ id: SecretAchievementId,
        _ days: [DaySignals],
        today: Date? = nil,
        windowLength: Int = 42
    ) -> Bool {
        let snapshot = F.snapshot(days, today: today ?? self.today, windowLength: windowLength)
        return SecretRules.holds(id, in: snapshot, calendar: F.calendar)
    }

    // MARK: - Midnight Fridge Raid

    func testFridgeRaidSameDayAfterMidnight() {
        let at = F.date(2026, 9, 20, hour: 1, minute: 30)
        XCTAssertTrue(holds(.fridgeRaid, [F.day(at, entries: [F.entry("yoghurt", at: at)])]))
    }

    func testFridgeRaidBackfilledYesterdayDoesNotCount() {
        // Logged at 01:30 on the 21st, but FOR the 20th.
        let at = F.date(2026, 9, 21, hour: 1, minute: 30)
        let day = F.day(F.date(2026, 9, 20), entries: [F.entry("goulash", at: at)])
        XCTAssertFalse(holds(.fridgeRaid, [day]))
    }

    func testFridgeRaidMidnightBoundary() {
        let midnight = F.date(2026, 9, 20, hour: 0, minute: 0)
        let lastMinute = F.date(2026, 9, 20, hour: 3, minute: 59)
        let fourAM = F.date(2026, 9, 20, hour: 4, minute: 0)
        let lateEvening = F.date(2026, 9, 20, hour: 23, minute: 59)
        XCTAssertTrue(holds(.fridgeRaid, [F.day(midnight, entries: [F.entry("a", at: midnight)])]))
        XCTAssertTrue(holds(.fridgeRaid, [F.day(lastMinute, entries: [F.entry("a", at: lastMinute)])]))
        XCTAssertFalse(holds(.fridgeRaid, [F.day(fourAM, entries: [F.entry("a", at: fourAM)])]))
        XCTAssertFalse(holds(.fridgeRaid, [F.day(lateEvening, entries: [F.entry("a", at: lateEvening)])]))
    }

    // MARK: - Barista Mode

    func testBaristaFiveCoffeesOneDay() {
        let day = F.date(2026, 9, 22)
        XCTAssertTrue(holds(.barista, [F.day(day, entries: F.entries(5, "espresso", tags: [.coffee], on: day))]))
    }

    func testBaristaFourCoffeesOrSplitAcrossDaysDoesNot() {
        let monday = F.date(2026, 9, 21)
        let tuesday = F.date(2026, 9, 22)
        XCTAssertFalse(holds(.barista, [F.day(monday, entries: F.entries(4, "espresso", tags: [.coffee], on: monday))]))
        XCTAssertFalse(holds(.barista, [
            F.day(monday, entries: F.entries(3, "espresso", tags: [.coffee], on: monday)),
            F.day(tuesday, entries: F.entries(2, "espresso", tags: [.coffee], on: tuesday)),
        ]))
        // Five entries, but not coffee.
        XCTAssertFalse(holds(.barista, [F.day(monday, entries: F.entries(5, "tea", tags: [.tea], on: monday))]))
    }

    // MARK: - Pizza Friday

    private func pizzaDays(_ dates: [Date]) -> [DaySignals] {
        dates.map { F.day($0, entries: [F.entry("pizza", tags: [.pizza], at: $0)]) }
    }

    func testPizzaFridayFourConsecutiveFridays() {
        let fridays = [F.date(2026, 8, 28), F.date(2026, 9, 4), F.date(2026, 9, 11), F.date(2026, 9, 18)]
        XCTAssertTrue(holds(.pizzaFriday, pizzaDays(fridays)))
    }

    func testPizzaFridayWithAGapFridayDoesNot() {
        // Three Fridays, not the fourth, then the fifth.
        let fridays = [F.date(2026, 8, 21), F.date(2026, 8, 28), F.date(2026, 9, 4), F.date(2026, 9, 18)]
        XCTAssertFalse(holds(.pizzaFriday, pizzaDays(fridays)))
    }

    func testPizzaOnFourConsecutiveDaysIsNotPizzaFriday() {
        let days = (0..<4).map { F.date(F.date(2026, 9, 17), plusDays: $0) }
        XCTAssertFalse(holds(.pizzaFriday, pizzaDays(days)))
    }

    // MARK: - Bullseye

    private func bullseyeDay(_ date: Date, total: Double, entries count: Int = 3, goal: Double? = 2000) -> DaySignals {
        F.day(date, entries: F.entries(count, "meal", on: date, calories: total / Double(count)), calorieGoal: goal)
    }

    func testBullseyeRoundsToTheGoal() {
        XCTAssertTrue(holds(.bullseye, [bullseyeDay(F.date(2026, 9, 23), total: 1999.6)]))
    }

    func testBullseyeRoundingMiss() {
        XCTAssertFalse(holds(.bullseye, [bullseyeDay(F.date(2026, 9, 23), total: 1998.4)]))
    }

    func testBullseyeNeedsCompletedDayThreeEntriesAndAGoal() {
        XCTAssertFalse(holds(.bullseye, [bullseyeDay(today, total: 2000)]), "today is not completed")
        XCTAssertFalse(holds(.bullseye, [bullseyeDay(F.date(2026, 9, 23), total: 2000, entries: 2)]))
        XCTAssertFalse(holds(.bullseye, [bullseyeDay(F.date(2026, 9, 23), total: 2000, goal: nil)]))
    }

    // MARK: - Palindrome Day

    private func totalDay(_ date: Date, total: Double, entries count: Int = 4) -> DaySignals {
        F.day(date, entries: F.entries(count, "meal", on: date, calories: total / Double(count)))
    }

    func testPalindromeYesterday1221() {
        XCTAssertTrue(holds(.palindrome, [totalDay(F.date(2026, 9, 23), total: 1221)]))
        XCTAssertTrue(holds(.palindrome, [totalDay(F.date(2026, 9, 23), total: 2002)]))
    }

    func testPalindromeNegatives() {
        XCTAssertFalse(holds(.palindrome, [totalDay(F.date(2026, 9, 23), total: 999)]), "under 1000")
        XCTAssertFalse(holds(.palindrome, [totalDay(F.date(2026, 9, 23), total: 1231)]))
        XCTAssertFalse(holds(.palindrome, [totalDay(F.date(2026, 9, 23), total: 1221, entries: 2)]), "needs 3 entries")
    }

    func testPalindromeTodayIsNotYetCompleted() {
        XCTAssertFalse(holds(.palindrome, [totalDay(today, total: 1221)]))
    }

    func testPalindromeNumberCheck() {
        XCTAssertTrue(SecretRules.isPalindrome(1221))
        XCTAssertTrue(SecretRules.isPalindrome(12321))
        XCTAssertFalse(SecretRules.isPalindrome(999))
        XCTAssertFalse(SecretRules.isPalindrome(1231))
    }

    // MARK: - Groundhog Breakfast

    /// Oats for breakfast on each of the given offsets from 2026-08-15.
    private func breakfastDays(_ offsets: [Int], meal: SignalMeal = .breakfast) -> [DaySignals] {
        let start = F.date(2026, 8, 15, hour: 7)
        return offsets.map { offset in
            let at = F.date(start, plusDays: offset)
            return F.day(at, entries: [F.entry("oats", at: at, meal: meal)])
        }
    }

    func testGroundhogThirtyOfThirtyFive() {
        XCTAssertTrue(holds(.groundhogBreakfast, breakfastDays(Array(0..<30))))
        // Scattered: 30 of the 35 days 0...34.
        XCTAssertTrue(holds(.groundhogBreakfast, breakfastDays(Array(0..<35).filter { $0 % 7 != 3 })))
    }

    func testGroundhogTwentyNineIsNotEnough() {
        XCTAssertFalse(holds(.groundhogBreakfast, breakfastDays(Array(0..<29))))
        // 30 days in total, but spread over 36 days: no 35-day span has 30.
        XCTAssertFalse(holds(.groundhogBreakfast, breakfastDays(Array(0..<29) + [35])))
    }

    func testGroundhogOnlyCountsBreakfast() {
        XCTAssertFalse(holds(.groundhogBreakfast, breakfastDays(Array(0..<35), meal: .lunch)))
    }

    // MARK: - Friday the 13th

    func testFriday13th() {
        let friday13 = F.date(2026, 11, 13)
        XCTAssertTrue(holds(.friday13, [F.day(friday13, entries: [F.entry("a", at: friday13)])], today: F.date(2026, 11, 20)))
    }

    func testFriday13thNegatives() {
        let saturday14 = F.date(2026, 3, 14)
        XCTAssertFalse(holds(.friday13, [F.day(saturday14, entries: [F.entry("a", at: saturday14)])], today: F.date(2026, 3, 20)))
        // Friday the 13th with water only, no food entry.
        let friday13 = F.date(2026, 11, 13)
        XCTAssertFalse(holds(.friday13, [F.day(friday13, waterML: 2000, waterGoalML: 2000)], today: F.date(2026, 11, 20)))
        // Sunday 2026-09-13.
        let sunday13 = F.date(2026, 9, 13)
        XCTAssertFalse(holds(.friday13, [F.day(sunday13, entries: [F.entry("a", at: sunday13)])]))
    }

    // MARK: - World Tour Week

    private let sevenCuisines: [FoodTag] = [
        .cuisineCzech, .cuisineItalian, .cuisineJapanese, .cuisineChinese,
        .cuisineIndian, .cuisineMexican, .cuisineThai,
    ]

    /// One dish per cuisine, day `i` of the week starting `monday`.
    private func cuisineDays(_ cuisines: [FoodTag], from monday: Date) -> [DaySignals] {
        cuisines.enumerated().map { index, tag in
            let at = F.date(monday, plusDays: index)
            return F.day(at, entries: [F.entry("dish-\(tag.rawValue)", tags: [tag], at: at)])
        }
    }

    func testWorldTourSevenCuisinesInOneIsoWeek() {
        XCTAssertTrue(holds(.worldTour, cuisineDays(sevenCuisines, from: F.date(2026, 9, 14))))
    }

    func testWorldTourSixCuisinesOrSplitWeeksDoesNot() {
        XCTAssertFalse(holds(.worldTour, cuisineDays(Array(sevenCuisines.prefix(6)), from: F.date(2026, 9, 14))))
        // Seven consecutive days Thursday..Wednesday span W37 and W38.
        XCTAssertFalse(holds(.worldTour, cuisineDays(sevenCuisines, from: F.date(2026, 9, 10))))
        // Seven dishes, one cuisine.
        XCTAssertFalse(holds(.worldTour, cuisineDays(Array(repeating: .cuisineItalian, count: 7), from: F.date(2026, 9, 14))))
    }

    // MARK: - Pi Day

    func testPiDay() {
        let piDay = F.date(2026, 3, 14)
        XCTAssertTrue(holds(.piDay, [F.day(piDay, entries: [F.entry("strudel", tags: [.pie], at: piDay)])], today: F.date(2026, 3, 20)))
    }

    func testPiDayNegatives() {
        let piDay = F.date(2026, 3, 14)
        let nextDay = F.date(2026, 3, 15)
        XCTAssertFalse(holds(.piDay, [F.day(piDay, entries: [F.entry("pizza", tags: [.pizza], at: piDay)])], today: F.date(2026, 3, 20)))
        XCTAssertFalse(holds(.piDay, [F.day(nextDay, entries: [F.entry("strudel", tags: [.pie], at: nextDay)])], today: F.date(2026, 3, 20)))
    }

    // MARK: - Déjà Vu

    private func foodsDay(_ date: Date, _ foods: [String]) -> DaySignals {
        F.day(date, entries: foods.enumerated().map { index, food in
            F.entry(food, at: date.addingTimeInterval(Double(index) * 600))
        })
    }

    func testDejaVuSameFoodsTwoCompletedDays() {
        XCTAssertTrue(holds(.dejaVu, [
            foodsDay(F.date(2026, 9, 21), ["oats", "chicken", "rice"]),
            foodsDay(F.date(2026, 9, 22), ["rice", "oats", "chicken", "oats"]),
        ]))
    }

    func testDejaVuNegatives() {
        // Only two distinct foods.
        XCTAssertFalse(holds(.dejaVu, [
            foodsDay(F.date(2026, 9, 21), ["oats", "rice"]),
            foodsDay(F.date(2026, 9, 22), ["oats", "rice"]),
        ]))
        // The second day is today (not completed).
        XCTAssertFalse(holds(.dejaVu, [
            foodsDay(F.date(2026, 9, 23), ["oats", "chicken", "rice"]),
            foodsDay(today, ["oats", "chicken", "rice"]),
        ]))
        // Not consecutive.
        XCTAssertFalse(holds(.dejaVu, [
            foodsDay(F.date(2026, 9, 20), ["oats", "chicken", "rice"]),
            foodsDay(F.date(2026, 9, 22), ["oats", "chicken", "rice"]),
        ]))
        // One food differs.
        XCTAssertFalse(holds(.dejaVu, [
            foodsDay(F.date(2026, 9, 21), ["oats", "chicken", "rice"]),
            foodsDay(F.date(2026, 9, 22), ["oats", "chicken", "potatoes"]),
        ]))
    }

    // MARK: - Knedlík Marathon / Gone Fishing

    private func taggedDays(_ tag: FoodTag, _ dates: [Date]) -> [DaySignals] {
        dates.map { F.day($0, entries: [F.entry("dish", tags: [tag], at: $0)]) }
    }

    func testKnedlikThreeDaysInARowAcrossMonthEnd() {
        let days = [F.date(2026, 8, 30), F.date(2026, 8, 31), F.date(2026, 9, 1)]
        XCTAssertTrue(holds(.knedlikMarathon, taggedDays(.knedlik, days)))
    }

    func testKnedlikWithAGapDoesNot() {
        let days = [F.date(2026, 9, 1), F.date(2026, 9, 2), F.date(2026, 9, 4)]
        XCTAssertFalse(holds(.knedlikMarathon, taggedDays(.knedlik, days)))
        // Three days in a row, but fish.
        XCTAssertFalse(holds(.knedlikMarathon, taggedDays(.fish, [F.date(2026, 9, 1), F.date(2026, 9, 2), F.date(2026, 9, 3)])))
    }

    func testGoneFishing() {
        let consecutive = [F.date(2026, 9, 1), F.date(2026, 9, 2), F.date(2026, 9, 3)]
        XCTAssertTrue(holds(.goneFishing, taggedDays(.fish, consecutive)))
        XCTAssertFalse(holds(.goneFishing, taggedDays(.fish, Array(consecutive.prefix(2)))))
        XCTAssertFalse(holds(.goneFishing, taggedDays(.seafood, consecutive)))
    }

    // MARK: - Vodník's Apprentice

    func testVodnikOneAndAHalfTimesTheWaterGoal() {
        XCTAssertTrue(holds(.vodnik, [F.day(F.date(2026, 9, 22), waterML: 3000, waterGoalML: 2000)]))
    }

    func testVodnikNegatives() {
        XCTAssertFalse(holds(.vodnik, [F.day(F.date(2026, 9, 22), waterML: 2999, waterGoalML: 2000)]))
        XCTAssertFalse(holds(.vodnik, [F.day(F.date(2026, 9, 22), waterML: nil, waterGoalML: 2000)]), "no water data")
        XCTAssertFalse(holds(.vodnik, [F.day(F.date(2026, 9, 22), waterML: 5000, waterGoalML: nil)]), "no goal")
    }

    // MARK: - Dawn Patrol

    private func dawnDay(activityStart: Date, durationS: Double = 3600, entryAt: Date) -> DaySignals {
        let activity = ActivitySummary(
            id: "run-1",
            typeKey: "running",
            day: F.key(activityStart),
            start: activityStart,
            durationS: durationS
        )
        return F.day(activityStart, entries: [F.entry("banana", at: entryAt)], activities: [activity])
    }

    func testDawnPatrol() {
        // 05:30-06:30 run, breakfast at 07:00.
        XCTAssertTrue(holds(.dawnPatrol, [dawnDay(
            activityStart: F.date(2026, 9, 22, hour: 5, minute: 30),
            entryAt: F.date(2026, 9, 22, hour: 7, minute: 0)
        )]))
    }

    func testDawnPatrolNegatives() {
        // Entry 61 minutes after the end.
        XCTAssertFalse(holds(.dawnPatrol, [dawnDay(
            activityStart: F.date(2026, 9, 22, hour: 5, minute: 30),
            entryAt: F.date(2026, 9, 22, hour: 7, minute: 31)
        )]))
        // Activity starting at 06:00 exactly.
        XCTAssertFalse(holds(.dawnPatrol, [dawnDay(
            activityStart: F.date(2026, 9, 22, hour: 6, minute: 0),
            entryAt: F.date(2026, 9, 22, hour: 7, minute: 10)
        )]))
        // Entry before the activity ended.
        XCTAssertFalse(holds(.dawnPatrol, [dawnDay(
            activityStart: F.date(2026, 9, 22, hour: 5, minute: 30),
            entryAt: F.date(2026, 9, 22, hour: 6, minute: 0)
        )]))
        // No activities at all.
        let at = F.date(2026, 9, 22, hour: 6, minute: 30)
        XCTAssertFalse(holds(.dawnPatrol, [F.day(at, entries: [F.entry("banana", at: at)])]))
    }

    // MARK: - The Answer

    /// `perDay` entries on each of the seven days from `monday`.
    private func weekDays(from monday: Date, perDay: [Int]) -> [DaySignals] {
        perDay.enumerated().map { index, count in
            let date = F.date(monday, plusDays: index)
            return F.day(date, entries: F.entries(count, "food", on: date))
        }
    }

    func testAnswer42InACompletedWeek() {
        // Mon 2026-09-14 .. Sun 09-20 (W38), today is in W39.
        XCTAssertTrue(holds(.answer42, weekDays(from: F.date(2026, 9, 14), perDay: [6, 6, 6, 6, 6, 6, 6])))
    }

    func testAnswer42Negatives() {
        XCTAssertFalse(holds(.answer42, weekDays(from: F.date(2026, 9, 14), perDay: [6, 6, 6, 6, 6, 6, 5])), "41")
        XCTAssertFalse(holds(.answer42, weekDays(from: F.date(2026, 9, 14), perDay: [6, 6, 6, 6, 6, 6, 7])), "43")
        // 42 entries in the CURRENT week (Mon 09-21 .. today Thu 09-24).
        XCTAssertFalse(holds(.answer42, weekDays(from: F.date(2026, 9, 21), perDay: [10, 10, 11, 11])))
        // A week cut off by the window's start (window begins Wed 09-16).
        XCTAssertFalse(holds(
            .answer42,
            weekDays(from: F.date(2026, 9, 14), perDay: [6, 6, 6, 6, 6, 6, 6]),
            windowLength: 9
        ))
    }

    // MARK: - Nothing on an empty snapshot

    func testEmptySnapshotSatisfiesNothing() {
        XCTAssertTrue(SecretRules.satisfied(in: .empty, calendar: F.calendar).isEmpty)
        XCTAssertTrue(SecretRules.satisfied(in: F.snapshot([], today: today), calendar: F.calendar).isEmpty)
    }

    // MARK: - Day math

    func testDayMath() {
        XCTAssertEqual(SecretDayMath.dayNumber("1970-01-01"), 0)
        XCTAssertEqual(SecretDayMath.weekday(dayNumber: 0), 4, "1970-01-01 was a Thursday")
        XCTAssertEqual(SecretDayMath.dayNumber("2026-11-13").map(SecretDayMath.weekday(dayNumber:)), SecretDayMath.friday)
        XCTAssertEqual(SecretDayMath.dayNumber("2027-08-13").map(SecretDayMath.weekday(dayNumber:)), SecretDayMath.friday)
        XCTAssertEqual(SecretDayMath.dayNumber("2026-03-14").map(SecretDayMath.weekday(dayNumber:)), 6, "Saturday")
        XCTAssertEqual(SecretDayMath.dayNumber("2028-03-01")! - SecretDayMath.dayNumber("2028-02-29")!, 1)
        XCTAssertEqual(SecretDayMath.dayNumber("2027-01-01")! - SecretDayMath.dayNumber("2026-12-31")!, 1)
        XCTAssertNil(SecretDayMath.dayNumber("2026-13-01"))
        XCTAssertNil(SecretDayMath.dayNumber(""))
    }

    // MARK: - Catalog

    func testCatalogIdsUniqueAndAllSecretExceptKeeper() {
        let all = SecretCatalog.all
        XCTAssertEqual(SecretCatalog.secrets.count, 15)
        XCTAssertEqual(all.count, 16)
        XCTAssertEqual(Set(all.map(\.id)).count, all.count)
        XCTAssertTrue(SecretCatalog.secrets.allSatisfy(\.isSecret))
        XCTAssertFalse(SecretCatalog.keeper.isSecret)
        XCTAssertEqual(SecretCatalog.keeper.rarity, .legendary)
        for definition in all {
            XCTAssertTrue(definition.id.hasPrefix("secret."), definition.id)
            XCTAssertEqual(definition.condition, .featureEvaluated, definition.id)
            XCTAssertEqual(definition.featureId, SecretAchievementsFeature.id, definition.id)
            XCTAssertFalse(definition.isCoreCatalogBadge, definition.id)
        }
    }

    func testCatalogRaritiesMatchDesign() {
        XCTAssertEqual(SecretCatalog.rarity(for: .barista), .uncommon)
        XCTAssertEqual(SecretCatalog.rarity(for: .pizzaFriday), .rare)
        XCTAssertEqual(SecretCatalog.rarity(for: .bullseye), .epic)
        XCTAssertEqual(SecretCatalog.rarity(for: .worldTour), .epic)
    }

    func testEverySecretHasCzechText() throws {
        let path = try XCTUnwrap(Bundle.module.path(forResource: "cs", ofType: "lproj"))
        let czech = try XCTUnwrap(Bundle(path: path))
        let missing = "__missing__"
        // The test process runs in English, where every value equals its key.
        for definition in SecretCatalog.all {
            for key in [definition.title, definition.subtitle] {
                let translated = czech.localizedString(forKey: key, value: missing, table: nil)
                XCTAssertNotEqual(translated, missing, "no Czech text for '\(key)'")
            }
        }
        for key in ["Secret revealed!", "Secrets revealed!", "Secrets", "Found: %lld of %lld"] {
            XCTAssertNotEqual(czech.localizedString(forKey: key, value: missing, table: nil), missing, key)
        }
        XCTAssertEqual(czech.localizedString(forKey: "Barista Mode", value: missing, table: nil), "Režim baristy")
    }
}
