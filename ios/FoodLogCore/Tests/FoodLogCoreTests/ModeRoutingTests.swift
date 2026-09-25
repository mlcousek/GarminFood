// ModeRoutingTests.swift
//
// add-standalone-mode 2.5: the routers pick the local implementations while
// the effective data mode is standalone, re-read the mode on every call,
// and leave Garmin mode exactly as it was. Real Outbox / local store / usage
// stores on temp files; the Garmin side of the reads and the Garmin delete
// are small recording fakes (the real ones are the network), as in
// FoodLoggingTests.

import XCTest
@testable import FoodLogCore
import GarminKit

final class ModeRoutingTests: XCTestCase {
    /// A mode the test flips between calls, read by the routers' closure.
    fileprivate final class ModeSwitch: @unchecked Sendable {
        private let lock = NSLock()
        private var value: DataMode

        init(_ value: DataMode) { self.value = value }

        var mode: DataMode {
            get { lock.lock(); defer { lock.unlock() }; return value }
            set { lock.lock(); value = newValue; lock.unlock() }
        }
    }

    fileprivate actor RecordingGarminLog: FoodLogReconciling {
        private(set) var deletes: [String] = []

        func dailyFoodLog(date: String) async throws -> DailyFoodLog? { nil }

        @discardableResult
        func deleteFoodLogEntries(logIds: [String], date: String) async throws -> HTTPURLResponse {
            deletes.append(contentsOf: logIds)
            return HTTPURLResponse(url: URL(string: "https://example.invalid")!, statusCode: 204, httpVersion: nil, headerFields: nil)!
        }
    }

    /// Stands in for `GarminClient`'s reads: a recognisable day, and burned
    /// calories, so a test can tell which side answered.
    fileprivate struct GarminReads: NutritionLogReading {
        func dailyFoodLog(date: String) async throws -> DailyFoodLog? {
            DailyFoodLog(mealDate: "garmin-\(date)")
        }

        func mealsForDate(date: String) async throws -> MealsForDate {
            MealsForDate(meals: [Meal(mealId: 7, mealName: "BREAKFAST", startTime: "06:00:00", endTime: "10:00:00")])
        }

        func calorieSummaryDaily(startDate: String, endDate: String) async throws -> CalorieSummaryDailyResponse {
            CalorieSummaryDailyResponse(startDate: "garmin")
        }

        func dailyUserSummary(date: String) async throws -> DailyUserSummary {
            DailyUserSummary(calendarDate: date, activeKilocalories: 420)
        }
    }

    private let day = "2026-09-25"
    private let food = Food(id: "food-1", name: "Test food", source: .garmin, servings: [Serving(id: "serving-1", unit: "g", numberOfUnits: 100, calories: 100)])

    fileprivate struct Fixture {
        let router: ModeRoutingFoodLogging
        let reader: ModeRoutingNutritionReader
        let outbox: Outbox
        let localLog: LocalFoodLogStore
        let garminLog: RecordingGarminLog
        let modeSwitch: ModeSwitch
    }

    private func makeFixture(mode: DataMode) -> Fixture {
        let tmp = FileManager.default.temporaryDirectory
        let usage = UsageHistoryStore(fileURL: tmp.appendingPathComponent("routing-usage-\(UUID().uuidString).json"))
        let servings = ServingDefaultStore(fileURL: tmp.appendingPathComponent("routing-servings-\(UUID().uuidString).json"))
        let outbox = Outbox(processName: "routing-test-\(UUID().uuidString)")
        let localLog = LocalFoodLogStore(directoryURL: tmp.appendingPathComponent("routing-log-\(UUID().uuidString)"))
        let garminLog = RecordingGarminLog()
        let modeSwitch = ModeSwitch(mode)
        let current: @Sendable () -> DataMode = { modeSwitch.mode }
        return Fixture(
            router: ModeRoutingFoodLogging(
                garmin: LogEntryCoordinator(outbox: outbox, usageHistory: usage, servingDefaults: servings, garminLog: garminLog),
                local: LocalLogEntryCoordinator(store: localLog, usageHistory: usage, servingDefaults: servings),
                mode: current
            ),
            reader: ModeRoutingNutritionReader(garmin: GarminReads(), local: LocalNutritionReader(store: localLog), mode: current),
            outbox: outbox,
            localLog: localLog,
            garminLog: garminLog,
            modeSwitch: modeSwitch
        )
    }

    // MARK: Effective mode

    func testTheTestingToggleWinsAndAnUnclassifiedInstallIsGarmin() {
        XCTAssertEqual(DataMode.effective(stored: nil, forceStandalone: false), .garminConnected)
        XCTAssertEqual(DataMode.effective(stored: .garminConnected, forceStandalone: false), .garminConnected)
        XCTAssertEqual(DataMode.effective(stored: .standalone, forceStandalone: false), .standalone)
        XCTAssertEqual(DataMode.effective(stored: .garminConnected, forceStandalone: true), .standalone)
        XCTAssertEqual(DataMode.effective(stored: nil, forceStandalone: true), .standalone)
    }

    func testTheEffectiveModeIsReadFromTheStoredKeys() throws {
        let suite = "routing-defaults-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(DataMode.effective(in: defaults), .garminConnected, "nothing stored: Garmin, as before")
        defaults.set(DataMode.garminConnected.rawValue, forKey: DataMode.storageKey)
        XCTAssertEqual(DataMode.effective(in: defaults), .garminConnected)
        defaults.set(true, forKey: DataMode.forceStandaloneStorageKey)
        XCTAssertEqual(DataMode.effective(in: defaults), .standalone)
        defaults.set(false, forKey: DataMode.forceStandaloneStorageKey)
        defaults.set("somethingNewer", forKey: DataMode.storageKey)
        XCTAssertEqual(DataMode.effective(in: defaults), .garminConnected, "an unknown stored value is not standalone")
    }

    // MARK: Writes

    func testGarminModeStillWritesTheOutboxOnly() async throws {
        let fixture = makeFixture(mode: .garminConnected)

        let entry = try await fixture.router.confirm(food: food, serving: food.servings[0], numberOfUnits: 1, mealType: .lunch, date: day)

        let queued = await fixture.outbox.allEntries()
        XCTAssertEqual(queued.map(\.id), [entry.id])
        let local = try await fixture.localLog.entries(forDay: day)
        XCTAssertTrue(local.isEmpty)
    }

    func testStandaloneWritesTheLocalLogAndQueuesNothing() async throws {
        let fixture = makeFixture(mode: .standalone)

        let receipt = try await fixture.router.confirm(food: food, serving: food.servings[0], numberOfUnits: 1, mealType: .lunch, date: day)

        let local = try await fixture.localLog.entries(forDay: day)
        XCTAssertEqual(local.map(\.id), [receipt.id])
        let queued = await fixture.outbox.allEntries()
        XCTAssertTrue(queued.isEmpty, "no outbox, no sync in standalone mode")
    }

    func testTheModeIsReadOnEveryCall() async throws {
        let fixture = makeFixture(mode: .garminConnected)
        _ = try await fixture.router.confirm(food: food, serving: food.servings[0], numberOfUnits: 1, mealType: .lunch, date: day)

        fixture.modeSwitch.mode = .standalone
        _ = try await fixture.router.confirm(food: food, serving: food.servings[0], numberOfUnits: 2, mealType: .lunch, date: day)

        let queued = await fixture.outbox.allEntries()
        let local = try await fixture.localLog.entries(forDay: day)
        XCTAssertEqual(queued.map(\.numberOfUnits), [1])
        XCTAssertEqual(local.map(\.quantity), [2])
    }

    func testAStandaloneDeleteMakesNoGarminRequest() async throws {
        let fixture = makeFixture(mode: .standalone)
        let receipt = try await fixture.router.confirm(food: food, serving: food.servings[0], numberOfUnits: 1, mealType: .dinner, date: day)

        try await fixture.router.deleteCommitted(logId: receipt.id.uuidString, date: day)

        let local = try await fixture.localLog.entries(forDay: day)
        XCTAssertTrue(local.isEmpty)
        let garminDeletes = await fixture.garminLog.deletes
        XCTAssertTrue(garminDeletes.isEmpty)
    }

    func testGarminModeDeletesASyncedRowInGarminAsBefore() async throws {
        let fixture = makeFixture(mode: .garminConnected)

        try await fixture.router.deleteCommitted(logId: "garmin-log-1", date: day)

        let garminDeletes = await fixture.garminLog.deletes
        XCTAssertEqual(garminDeletes, ["garmin-log-1"])
    }

    func testAPendingRowIsCancelledInTheOutboxInEitherMode() async throws {
        let fixture = makeFixture(mode: .garminConnected)
        let queued = try await fixture.router.confirm(food: food, serving: food.servings[0], numberOfUnits: 1, mealType: .snacks, date: day)
        fixture.modeSwitch.mode = .standalone

        let outcome = try await fixture.router.deletePending(outboxId: queued.id)

        XCTAssertEqual(outcome, .removed)
        let remaining = await fixture.outbox.allEntries()
        XCTAssertTrue(remaining.isEmpty, "an entry queued before the switch can still be removed")
    }

    // MARK: Reads

    func testGarminModeReadsGarmin() async throws {
        let fixture = makeFixture(mode: .garminConnected)

        let log = try await fixture.reader.dailyFoodLog(date: day)
        let summary = try await fixture.reader.dailyUserSummary(date: day)
        let meals = try await fixture.reader.mealsForDate(date: day)
        let trend = try await fixture.reader.calorieSummaryDaily(startDate: day, endDate: day)

        XCTAssertEqual(log?.mealDate, "garmin-\(day)")
        XCTAssertEqual(summary.activeKilocalories, 420)
        XCTAssertEqual(meals.meals?.first?.startTime, "06:00:00")
        XCTAssertEqual(trend.startDate, "garmin")
    }

    func testStandaloneReadsTheLocalLog() async throws {
        let fixture = makeFixture(mode: .standalone)
        _ = try await fixture.router.confirm(food: food, serving: food.servings[0], numberOfUnits: 3, mealType: .breakfast, date: day)

        let log = try await fixture.reader.dailyFoodLog(date: day)
        let meals = try await fixture.reader.mealsForDate(date: day)

        XCTAssertEqual(log?.mealDate, day)
        XCTAssertEqual(log?.dailyNutritionContent?.calories, 300)
        XCTAssertNil(meals.meals?.first?.startTime)
        do {
            _ = try await fixture.reader.dailyUserSummary(date: day)
            XCTFail("expected a throw: no activity data without Garmin")
        } catch let error as LocalNutritionReaderError {
            XCTAssertEqual(error, .unavailable)
        }
    }
}
