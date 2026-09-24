// DaySignalsBuilderTests.swift
//
// add-gamification-signals 4.4-4.6: the pure `DaySignalsBuilder` from
// literal inputs -- digest-vs-local precedence, newer-local append, the
// +-120 s de-dup, the meal fallback order, the water max rule, fasting
// mapping, note tags, availability flags, the 42-day window, per-food tag
// memoisation, lifetime "first seen" facts, `ProfileSignals.firstName`, and
// the performance budget (design D5, D13). UTC calendar so the day keys
// and clock-based meal fallback do not depend on the CI runner's zone.

import XCTest
@testable import FoodLogCore
import GarminKit

final class DaySignalsBuilderTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func at(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    private let today = "2026-09-24"
    private var now: Date { at("2026-09-24T20:00:00Z") }

    private func food(_ id: String, _ name: String, brand: String? = nil, source: FoodSource = .garmin,
                      calories: Double? = 100, protein: Double? = 10, carbs: Double? = 10,
                      fat: Double? = 5, fiber: Double? = 2, sugar: Double? = 1) -> Food {
        Food(
            id: id,
            name: name,
            brandName: brand,
            source: source,
            servings: [Serving(id: "s", unit: "g", numberOfUnits: 100, calories: calories, carbs: carbs,
                               protein: protein, fat: fat, fiber: fiber, sugar: sugar)]
        )
    }

    private func event(_ foodId: String, _ iso: String, units: Double = 1, meal: MealType? = nil,
                       day: String? = nil) -> UsageEvent {
        UsageEvent(foodId: foodId, servingId: "s", numberOfUnits: units, timestamp: at(iso),
                   nutritionDay: day, mealType: meal)
    }

    private func build(_ input: SignalsInput, windowDays: Int = 42) -> SignalsSnapshot {
        DaySignalsBuilder.build(input: input, today: now, windowDays: windowDays, calendar: calendar)
    }

    // MARK: - Entry identity

    func testDigestWinsAndOnlyLocalEventsNewerThanTheFetchAreAppended() throws {
        let digest = DayLogDigest(
            day: today,
            fetchedAt: at("2026-09-24T12:00:00Z"),
            totals: MacroTotals(calories: 200, protein: 20, carbs: 5, fat: 10, fiber: 0, sugar: 0),
            goals: MacroGoals(calories: 2000, protein: 150, carbs: 200, fat: 60),
            entries: [DayLogDigest.Entry(foodId: "salmon", name: "Losos na grilu",
                                         timestamp: at("2026-09-24T08:00:00Z"), mealType: "BREAKFAST",
                                         calories: 200, protein: 20, carbs: 5, fat: 10, fiber: 0, sugar: 0)]
        )
        let input = SignalsInput(
            events: [
                event("salmon", "2026-09-24T08:01:00Z", day: today),   // same entry, matched
                event("apple", "2026-09-24T10:00:00Z", day: today),    // before fetch, not in digest: deleted
                event("carrot", "2026-09-24T13:00:00Z", day: today),   // after fetch: still in the outbox
            ],
            foods: ["apple": food("apple", "Jablko"), "carrot": food("carrot", "Mrkev")],
            digests: [digest]
        )
        let day = try XCTUnwrap(build(input).day(today))
        XCTAssertEqual(day.entries.map(\.foodId), ["salmon", "carrot"])
        XCTAssertEqual(day.entries.map(\.fromGarminLog), [true, false])
        XCTAssertTrue(day.entries[0].has(.fish))
        XCTAssertTrue(day.entries[1].has(.vegetable))
        XCTAssertEqual(day.goals?.calories, 2000)
        // Digest totals + the appended carrot (100 kcal serving).
        XCTAssertEqual(day.totals.calories, 300)
        XCTAssertEqual(day.totals.protein, 30)
        XCTAssertTrue(day.availability.hasGarminLog)
        XCTAssertTrue(day.availability.hasMacros)
    }

    func testNewerLocalEventWithin120SecondsOfADigestEntryIsNotCountedTwice() throws {
        let digest = DayLogDigest(
            day: today,
            fetchedAt: at("2026-09-24T12:00:00Z"),
            totals: MacroTotals(calories: 100, protein: 10, carbs: 10, fat: 5, fiber: 2, sugar: 1),
            goals: nil,
            entries: [DayLogDigest.Entry(foodId: "apple", name: "Jablko",
                                         timestamp: at("2026-09-24T12:01:00Z"), mealType: "SNACKS",
                                         calories: 100, protein: 10, carbs: 10, fat: 5, fiber: 2, sugar: 1)]
        )
        let input = SignalsInput(
            events: [
                event("apple", "2026-09-24T12:02:30Z", day: today),  // 90 s off: same entry
                event("apple", "2026-09-24T12:10:00Z", day: today),  // 9 min later: a second apple
            ],
            foods: ["apple": food("apple", "Jablko")],
            digests: [digest]
        )
        let day = try XCTUnwrap(build(input).day(today))
        XCTAssertEqual(day.entries.count, 2)
        XCTAssertEqual(day.entries.map(\.timestamp), [at("2026-09-24T12:01:00Z"), at("2026-09-24T12:10:00Z")])
        XCTAssertEqual(day.totals.calories, 200)
    }

    func testWithoutADigestLocalEventsAreSummedScaledByUnitsAndAnUnknownMacroIsNil() throws {
        let input = SignalsInput(
            events: [
                event("apple", "2026-09-24T09:00:00Z", units: 2, day: today),
                event("mystery", "2026-09-24T10:00:00Z", day: today),
            ],
            foods: [
                "apple": food("apple", "Jablko"),
                "mystery": food("mystery", "Tajemná věc", sugar: nil),
            ]
        )
        let day = try XCTUnwrap(build(input).day(today))
        XCTAssertEqual(day.entries.first?.calories, 200)
        XCTAssertEqual(day.totals.calories, 300)
        XCTAssertEqual(day.totals.protein, 30)
        XCTAssertNil(day.totals.sugar, "one unknown sugar value makes the day's sugar unknown")
        XCTAssertFalse(day.availability.hasGarminLog)
        XCTAssertTrue(day.availability.hasMacros)
    }

    func testAFoodMissingFromTheCacheHasUnknownMacros() throws {
        let input = SignalsInput(events: [event("gone", "2026-09-24T09:00:00Z", day: today)])
        let day = try XCTUnwrap(build(input).day(today))
        XCTAssertEqual(day.entries.count, 1)
        XCTAssertNil(day.entries[0].calories)
        XCTAssertNil(day.totals.calories)
        XCTAssertFalse(day.availability.hasMacros)
    }

    // MARK: - Meal fallback order

    func testMealComesFromTheEventThenTheDigestThenTheClock() throws {
        let digest = DayLogDigest(
            day: today,
            fetchedAt: at("2026-09-24T19:00:00Z"),
            totals: .zero,
            goals: nil,
            entries: [
                // Matched local event says snack: the event wins over "LUNCH".
                DayLogDigest.Entry(foodId: "a", timestamp: at("2026-09-24T12:00:00Z"), mealType: "LUNCH"),
                // No local event: the digest's meal.
                DayLogDigest.Entry(foodId: "b", timestamp: at("2026-09-24T08:00:00Z"), mealType: "DINNER"),
                // Neither: the clock (16:00 -> snack).
                DayLogDigest.Entry(foodId: "c", timestamp: at("2026-09-24T16:00:00Z"), mealType: nil),
            ]
        )
        let input = SignalsInput(
            events: [
                event("a", "2026-09-24T12:00:30Z", meal: .snacks, day: today),
                // Appended local event without a meal: the clock (19:30 -> dinner).
                event("d", "2026-09-24T19:30:00Z", day: today),
                // Appended local event with a meal: kept.
                event("e", "2026-09-24T19:40:00Z", meal: .breakfast, day: today),
            ],
            digests: [digest]
        )
        let day = try XCTUnwrap(build(input).day(today))
        let meals = Dictionary(uniqueKeysWithValues: day.entries.map { ($0.foodId, $0.meal) })
        XCTAssertEqual(meals["a"], .snack)
        XCTAssertEqual(meals["b"], .dinner)
        XCTAssertEqual(meals["c"], .snack)
        XCTAssertEqual(meals["d"], .dinner)
        XCTAssertEqual(meals["e"], .breakfast)
        XCTAssertEqual(day.entries(in: .snack).map(\.foodId), ["a", "c"])
    }

    // MARK: - Water, fasting, notes, activities

    func testWaterIsTheMaxOfLocalAndGarminAndTheGoalFallsBackToThePreference() throws {
        let input = SignalsInput(
            localWaterMLByDay: [today: 1500, "2026-09-23": 800],
            garminWaterByDay: [today: GarminWaterDay(totalML: 1200, goalML: 2500)],
            defaultWaterGoalML: 2000
        )
        let snapshot = build(input)
        let todaySignals = try XCTUnwrap(snapshot.day(today))
        XCTAssertEqual(todaySignals.waterML, 1500)
        XCTAssertEqual(todaySignals.waterGoalML, 2500)
        XCTAssertTrue(todaySignals.availability.hasWater)
        let yesterday = try XCTUnwrap(snapshot.day("2026-09-23"))
        XCTAssertEqual(yesterday.waterML, 800)
        XCTAssertEqual(yesterday.waterGoalML, 2000)
    }

    func testFastingKeptAndBrokenMapAndOpenWindowsAreNil() throws {
        let window = FastingWindow(start: at("2026-09-21T20:00:00Z"), end: at("2026-09-22T12:00:00Z"))
        let input = SignalsInput(
            events: [event("x", "2026-09-24T09:00:00Z", day: today)],
            fastingDays: [
                FastingDay(day: at("2026-09-22T00:00:00Z"), window: window, result: .kept),
                FastingDay(day: at("2026-09-23T00:00:00Z"), window: window, result: .broken(at: at("2026-09-23T07:00:00Z"))),
                FastingDay(day: at("2026-09-24T00:00:00Z"), window: window, result: .inProgress),
            ]
        )
        let snapshot = build(input)
        XCTAssertEqual(snapshot.day("2026-09-22")?.fasting, .kept)
        XCTAssertEqual(snapshot.day("2026-09-22")?.availability.hasFasting, true)
        XCTAssertEqual(snapshot.day("2026-09-23")?.fasting, .broken)
        let todaySignals = try XCTUnwrap(snapshot.day(today))
        XCTAssertNil(todaySignals.fasting)
        XCTAssertFalse(todaySignals.availability.hasFasting)
    }

    func testNoteTagsAreCarriedAndADayWithOnlyANoteExists() throws {
        let input = SignalsInput(notes: [
            DayNote(day: "2026-09-20", text: "Běh", tags: [.race, .travel]),
            DayNote(day: "2026-09-21", text: "nothing tagged", tags: []),
        ])
        let snapshot = build(input)
        XCTAssertEqual(snapshot.day("2026-09-20")?.noteTags, [.race, .travel])
        XCTAssertNil(snapshot.day("2026-09-21"), "an untagged note is not a signal")
    }

    func testActivitiesAreSortedAndAReadDayWithNoActivitiesStillCountsAsAvailable() throws {
        let run = ActivitySummary(id: "2", typeKey: "running", day: today, start: at("2026-09-24T17:00:00Z"), durationS: 1800)
        let walk = ActivitySummary(id: "1", typeKey: "walking", day: today, start: at("2026-09-24T07:00:00Z"), durationS: 900)
        let input = SignalsInput(activityDays: [
            DayActivity(day: today, activeKcal: 650, activities: [run, walk]),
            DayActivity(day: "2026-09-23", activeKcal: nil, activities: []),
            DayActivity(day: "2026-09-22", activeKcal: 300, activities: nil),
        ])
        let snapshot = build(input)
        let todaySignals = try XCTUnwrap(snapshot.day(today))
        XCTAssertEqual(todaySignals.activities.map(\.id), ["1", "2"])
        XCTAssertEqual(todaySignals.activeKcal, 650)
        XCTAssertTrue(todaySignals.availability.hasActivities)
        XCTAssertEqual(snapshot.day("2026-09-23")?.availability.hasActivities, true)
        XCTAssertEqual(snapshot.day("2026-09-22")?.availability.hasActivities, false)
        XCTAssertEqual(snapshot.day("2026-09-22")?.activeKcal, 300)
    }

    func testWeighInAndGoalStatusPassThrough() throws {
        let status = SignalGoalStatus(metCalorieGoal: true, metProteinGoal: false, metCarbGoal: true, metFatGoal: false)
        let input = SignalsInput(weighInKgByDay: [today: 81.4], goalStatusByDay: [today: status])
        let day = try XCTUnwrap(build(input).day(today))
        XCTAssertEqual(day.weighInKg, 81.4)
        XCTAssertTrue(day.availability.hasWeight)
        XCTAssertEqual(day.goalStatus, status)
    }

    // MARK: - Window

    func testWindowIs42DaysEndingTodayAndOnlyDaysWithDataAppear() {
        let input = SignalsInput(events: [
            event("a", "2026-08-14T09:00:00Z", day: "2026-08-14"),  // today - 41: inside
            event("b", "2026-08-13T09:00:00Z", day: "2026-08-13"),  // today - 42: outside
        ])
        let snapshot = build(input)
        XCTAssertEqual(snapshot.windowDays.count, 42)
        XCTAssertEqual(snapshot.windowDays.first, "2026-08-14")
        XCTAssertEqual(snapshot.windowDays.last, today)
        XCTAssertEqual(snapshot.today, today)
        XCTAssertEqual(Array(snapshot.days.keys), ["2026-08-14"])
        XCTAssertEqual(snapshot.recentDayKeys(2), ["2026-09-23", today])
        // Outside the window, still part of the lifetime history.
        XCTAssertEqual(snapshot.firstSeenDayByFood["b"], "2026-08-13")
    }

    func testEventDayIsItsNutritionDayNotItsTimestamp() {
        // Logged just after midnight for the previous day.
        let input = SignalsInput(events: [event("a", "2026-09-24T00:10:00Z", day: "2026-09-23")])
        let snapshot = build(input)
        XCTAssertNotNil(snapshot.day("2026-09-23"))
        XCTAssertNil(snapshot.day(today))
    }

    // MARK: - Tags, provenance, first-seen

    func testTagsAreMemoisedPerFoodId() throws {
        // The first resolution (the older digest's name) sticks for the id.
        let digest = DayLogDigest(
            day: "2026-09-20", fetchedAt: at("2026-09-20T20:00:00Z"), totals: .zero, goals: nil,
            entries: [DayLogDigest.Entry(foodId: "f", name: "Losos", timestamp: at("2026-09-20T12:00:00Z"))]
        )
        let input = SignalsInput(
            events: [event("f", "2026-09-24T12:00:00Z", day: today)],
            foods: ["f": food("f", "Jablko")],
            digests: [digest]
        )
        let snapshot = build(input)
        XCTAssertEqual(snapshot.day("2026-09-20")?.entries.first?.tags, snapshot.day(today)?.entries.first?.tags)
        XCTAssertEqual(snapshot.day(today)?.entries.first?.has(.fish), true)
    }

    func testBarcodeComesFromProvenanceOrAnOpenFoodFactsIdAndMakesACzechBrand() throws {
        let input = SignalsInput(
            events: [
                event("off-8594001234567", "2026-09-24T09:00:00Z", day: today),
                event("custom-1", "2026-09-24T10:00:00Z", day: today),
            ],
            foods: [
                "off-8594001234567": food("8594001234567", "Tvaroh", source: .openFoodFacts),
                "custom-1": food("custom-1", "Domácí tvaroh", source: .custom),
            ],
            provenance: ["custom-1": FoodProvenance(foodId: "custom-1", barcode: "8591234567890", brand: nil)]
        )
        let day = try XCTUnwrap(build(input).day(today))
        XCTAssertEqual(day.entries[0].barcode, "8594001234567")
        XCTAssertEqual(day.entries[1].barcode, "8591234567890")
        XCTAssertTrue(day.entries[1].has(.czechBrand))
    }

    func testFirstSeenFoodAndCzechBrandAreTheEarliestDayAcrossEventsAndDigests() {
        let digest = DayLogDigest(
            day: "2026-09-10", fetchedAt: at("2026-09-10T20:00:00Z"), totals: .zero, goals: nil,
            entries: [DayLogDigest.Entry(foodId: "kofola", name: "Kofola Original", brand: "Kofola",
                                         timestamp: at("2026-09-10T12:00:00Z"))]
        )
        let input = SignalsInput(
            events: [
                event("kofola", "2026-09-20T12:00:00Z", day: "2026-09-20"),
                event("apple", "2026-09-22T12:00:00Z", day: "2026-09-22"),
            ],
            foods: ["apple": food("apple", "Jablko")],
            digests: [digest]
        )
        let snapshot = build(input)
        XCTAssertEqual(snapshot.firstSeenDayByFood["kofola"], "2026-09-10")
        XCTAssertEqual(snapshot.firstSeenDayByFood["apple"], "2026-09-22")
        XCTAssertEqual(snapshot.firstSeenDayByCzechBrand[SearchText.foldedPhrase("Kofola")], "2026-09-10")
    }

    // MARK: - Profile

    func testFirstNameIsTheFirstTokenOfTheFullName() {
        XCTAssertEqual(ProfileSignals.firstName(fromFullName: "Jiří Mlčoušek"), "Jiří")
        XCTAssertEqual(ProfileSignals.firstName(fromFullName: "  Jiří  "), "Jiří")
        XCTAssertNil(ProfileSignals.firstName(fromFullName: "   "))
        XCTAssertNil(ProfileSignals.firstName(fromFullName: nil))
    }

    func testProfilePassesThrough() {
        let profile = ProfileSignals(firstName: "Jiří", weightGoal: WeightGoalSignal(startKg: 90, targetKg: 80))
        XCTAssertEqual(build(SignalsInput(profile: profile)).profile, profile)
    }

    // MARK: - Performance (4.6)

    func testBuilds42DaysOf1000EntriesWithinBudget() {
        var events: [UsageEvent] = []
        var foods: [String: Food] = [:]
        let names = ["Jablko", "Mrkev", "Losos na grilu", "Kysané zelí", "Kofola", "Rohlík", "Tvaroh", "Čaj"]
        for index in 0..<1000 {
            let dayOffset = index % 42
            let date = calendar.date(byAdding: .minute, value: (index % 600) + 360,
                                     to: calendar.date(byAdding: .day, value: -dayOffset,
                                                       to: calendar.startOfDay(for: now))!)!
            let id = "food-\(index % 150)"
            foods[id] = food(id, names[index % names.count] + " \(index % 150)")
            events.append(UsageEvent(foodId: id, servingId: "s", numberOfUnits: 1, timestamp: date,
                                     nutritionDay: NutritionDate.string(from: date, calendar: calendar)))
        }
        let input = SignalsInput(events: events, foods: foods)
        let started = Date()
        let snapshot = build(input)
        let elapsed = Date().timeIntervalSince(started)
        XCTAssertEqual(snapshot.days.count, 42)
        XCTAssertEqual(snapshot.days.values.reduce(0) { $0 + $1.entries.count }, 1000)
        #if DEBUG
        // Unoptimised CI builds are several times slower; this still catches
        // an accidental O(n^2)/per-call-formatter regression.
        XCTAssertLessThan(elapsed, 1.0)
        #else
        XCTAssertLessThan(elapsed, 0.05)
        #endif
    }
}
