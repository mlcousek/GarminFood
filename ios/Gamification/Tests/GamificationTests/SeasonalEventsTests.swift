// SeasonalEventsTests.swift
//
// add-seasonal-events design D5-D7: window boundaries and phases, quest
// evaluation (Štědrý den carp-or-řízek, Easter eggs-AND-ham, St Martin's
// on-the-day bonus), sticky progress across runs, yearly idempotency of
// grants/moments/badges, the name-day-absent path, and collector counts.
// Real `SeasonalStore` files in a unique temp directory per test (never
// mocked), real `FoodTagger` tags on entries -- the same pipeline the app
// runs.

import XCTest
import FoodLogCore
@testable import Gamification

final class SeasonalEventsTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SeasonalEventsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Helpers

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Prague") ?? .current
        return calendar
    }()

    private func date(_ key: String) -> SeasonalDate {
        SeasonalDate(dayKey: key) ?? SeasonalDate(year: 1970, month: 1, day: 1)
    }

    private func noon(_ key: String) -> Date {
        let day = date(key)
        return Self.calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 12)) ?? Date()
    }

    /// Day key -> food names logged that day.
    private func snapshot(_ foods: [String: [String]], today: String, firstName: String? = nil) -> SignalsSnapshot {
        var days: [String: DaySignals] = [:]
        for (key, names) in foods {
            let entries = names.map { name in
                SignalEntry(
                    foodId: name,
                    name: name,
                    tags: FoodTagger.tags(name: name, brand: nil, barcode: nil),
                    timestamp: noon(key),
                    meal: .lunch
                )
            }
            days[key] = DaySignals(day: key, date: noon(key), entries: entries)
        }
        return SignalsSnapshot(
            days: days,
            today: today,
            windowDays: days.keys.sorted(),
            profile: ProfileSignals(firstName: firstName)
        )
    }

    private func context(_ snapshot: SignalsSnapshot, unlocked: Set<String> = []) -> FeatureContext {
        FeatureContext(
            snapshot: snapshot,
            now: noon(snapshot.today),
            calendar: Self.calendar,
            streak: StreakEngine.Status(length: 0, hasLoggedToday: false, isAtRiskToday: false, lastLoggedDay: nil),
            level: 1,
            unlockedBadgeIds: unlocked,
            isConfirmPath: false
        )
    }

    private func event(_ id: String) throws -> SeasonalEvent {
        try XCTUnwrap(SeasonalEventCatalog.event(id: id), id)
    }

    private func completes(_ eventId: String, year: Int, _ foods: [String: [String]]) throws -> Bool {
        let event = try event(eventId)
        let window = try XCTUnwrap(event.window(year: year, nameDay: nil))
        let marks = SeasonalEvaluator.mergedMarks(
            event: event,
            year: year,
            window: window,
            snapshot: snapshot(foods, today: window.upperBound.dayKey),
            stored: [:]
        )
        return SeasonalEvaluator.isCompleted(event: event, marks: marks)
    }

    // MARK: - Catalog

    func testCatalogHasTwelveEventsWithLimitedBadges() {
        XCTAssertEqual(SeasonalEventCatalog.all.count, 12)
        XCTAssertEqual(Set(SeasonalEventCatalog.all.map(\.id)).count, 12)
        XCTAssertEqual(SeasonalEventCatalog.eventBadges.count, 12)
        for badge in SeasonalEventCatalog.eventBadges {
            XCTAssertTrue(badge.id.hasPrefix("event."), badge.id)
            XCTAssertNotNil(badge.limitedEditionEventId, badge.id)
            XCTAssertEqual(badge.condition, .featureEvaluated)
            XCTAssertEqual(badge.featureId, SeasonalEventsFeature.id)
        }
        XCTAssertEqual(SeasonalEventCatalog.badges.count, 15)
        XCTAssertEqual(Set(SeasonalEventCatalog.badges.map(\.id)).count, 15)
        let feature = SeasonalEventsFeature(directory: directory)
        XCTAssertEqual(feature.badges.count, 15)
        for event in SeasonalEventCatalog.all {
            XCTAssertFalse(event.requiredQuests.isEmpty, event.id)
        }
    }

    func testFixedWindowsNeverCrossAYear() {
        for year in [2026, 2027, 2028] {
            for event in SeasonalEventCatalog.all {
                guard let window = event.window(year: year, nameDay: .init(month: 4, day: 24)) else {
                    XCTFail("\(event.id) \(year) has no window")
                    continue
                }
                XCTAssertEqual(window.lowerBound.year, year, event.id)
                XCTAssertEqual(window.upperBound.year, year, event.id)
            }
        }
        XCTAssertEqual(try event("masopust").window(year: 2026, nameDay: nil), date("2026-02-12")...date("2026-02-17"))
        XCTAssertEqual(try event("easter").window(year: 2027, nameDay: nil), date("2027-03-25")...date("2027-03-29"))
        XCTAssertEqual(try event("masopust").window(year: 2027, nameDay: nil), date("2027-02-04")...date("2027-02-09"))
        XCTAssertEqual(try event("grill").window(year: 2026, nameDay: nil), date("2026-06-21")...date("2026-08-31"))
    }

    func testGrantKeysStayInTheFeatureNamespace() {
        XCTAssertEqual(SeasonalEventsFeature.completionGrantKey(eventId: "easter", year: 2026), "seasonal.event.easter.2026")
        XCTAssertEqual(
            SeasonalEventsFeature.bonusGrantKey(eventId: "st-martin", year: 2026, questId: "rohlicek"),
            "seasonal.event.st-martin.2026.bonus.rohlicek"
        )
    }

    // MARK: - Windows and phases (D5)

    func testPhaseAtWindowBoundaries() throws {
        let window = try XCTUnwrap(try event("st-martin").window(year: 2026, nameDay: nil))
        XCTAssertEqual(window, date("2026-11-08")...date("2026-11-16"))
        XCTAssertEqual(SeasonalEvaluator.phase(today: date("2026-11-04"), window: window), .later)
        XCTAssertEqual(SeasonalEvaluator.phase(today: date("2026-11-05"), window: window), .upcoming)
        XCTAssertEqual(SeasonalEvaluator.phase(today: date("2026-11-07"), window: window), .upcoming)
        XCTAssertEqual(SeasonalEvaluator.phase(today: date("2026-11-08"), window: window), .active)
        XCTAssertEqual(SeasonalEvaluator.phase(today: date("2026-11-16"), window: window), .active)
        XCTAssertEqual(SeasonalEvaluator.phase(today: date("2026-11-17"), window: window), .ended)
    }

    func testTeaserShowsStartInThreeDays() async throws {
        let feature = SeasonalEventsFeature(directory: directory)
        let upcoming = await feature.upcomingEvents(now: noon("2026-11-05"), calendar: Self.calendar)
        let martin = try XCTUnwrap(upcoming.first { $0.eventId == "st-martin" })
        XCTAssertEqual(martin.phase, .upcoming)
        XCTAssertEqual(martin.daysUntilStart, 3)
        let banner = await feature.bannerEvent(now: noon("2026-11-05"), calendar: Self.calendar)
        XCTAssertEqual(banner?.eventId, "st-martin")
        // New Year's Day is teased from 29 December of the year before.
        let newYear = await feature.upcomingEvents(now: noon("2026-12-29"), calendar: Self.calendar)
        XCTAssertTrue(newYear.contains { $0.eventId == "novy-rok" && $0.year == 2027 })
    }

    func testGooseAfterTheWindowDoesNotProgress() throws {
        let martin = try event("st-martin")
        let window = try XCTUnwrap(martin.window(year: 2026, nameDay: nil))
        let marks = SeasonalEvaluator.mergedMarks(
            event: martin, year: 2026, window: window,
            snapshot: snapshot(["2026-11-20": ["Pečená husa"]], today: "2026-11-20"), stored: [:]
        )
        XCTAssertTrue(marks.values.allSatisfy(\.isEmpty))
    }

    func testEntriesOutsideTheWindowDoNotCount() throws {
        XCTAssertFalse(try completes("mushrooms", year: 2026, ["2026-08-31": ["Houbová polévka"], "2026-11-01": ["Smaženice"]]))
        XCTAssertTrue(try completes("mushrooms", year: 2026, [
            "2026-09-01": ["Houbová polévka"], "2026-09-15": ["Smaženice"], "2026-10-31": ["Kulajda"]
        ]))
    }

    // MARK: - Quest rules (D7)

    func testStedryDenAcceptsCarpOrRizekWithPotatoSalad() throws {
        XCTAssertTrue(try completes("stedry-den", year: 2026, ["2026-12-24": ["Vepřový řízek", "Bramborový salát"]]))
        XCTAssertTrue(try completes("stedry-den", year: 2026, ["2026-12-24": ["Smažený kapr", "Bramborový salát s majonézou"]]))
        XCTAssertFalse(try completes("stedry-den", year: 2026, ["2026-12-24": ["Bramborový salát"]]))
        XCTAssertFalse(try completes("stedry-den", year: 2026, ["2026-12-24": ["Kapary", "Bramborový salát"]]))
        XCTAssertFalse(try completes("stedry-den", year: 2026, [
            "2026-12-23": ["Smažený kapr"], "2026-12-24": ["Bramborový salát"]
        ]))
    }

    func testEasterNeedsBothEggsAndHam() throws {
        XCTAssertFalse(try completes("easter", year: 2026, ["2026-04-05": ["Vejce natvrdo"]]))
        XCTAssertFalse(try completes("easter", year: 2026, ["2026-04-05": ["Šunka od kosti"]]))
        XCTAssertTrue(try completes("easter", year: 2026, [
            "2026-04-02": ["Vejce natvrdo"], "2026-04-06": ["Šunka od kosti"]
        ]))
        XCTAssertFalse(try completes("easter", year: 2026, [
            "2026-03-31": ["Šunka od kosti"], "2026-04-05": ["Vejce natvrdo"]
        ]))
    }

    func testStMartinBonusOnlyOnTheEleventh() throws {
        let martin = try event("st-martin")
        let window = try XCTUnwrap(martin.window(year: 2026, nameDay: nil))
        let bonus = try XCTUnwrap(martin.bonusQuests.first { $0.id == "goose-on-the-day" })

        let tenth = SeasonalEvaluator.mergedMarks(
            event: martin, year: 2026, window: window,
            snapshot: snapshot(["2026-11-10": ["Pečená husa"]], today: "2026-11-10"), stored: [:]
        )
        XCTAssertTrue(SeasonalEvaluator.isCompleted(event: martin, marks: tenth))
        XCTAssertEqual(tenth[bonus.id]?.count ?? 0, 0)

        let eleventh = SeasonalEvaluator.mergedMarks(
            event: martin, year: 2026, window: window,
            snapshot: snapshot(["2026-11-11": ["Husí stehno se zelím"]], today: "2026-11-11"), stored: [:]
        )
        XCTAssertEqual(eleventh[bonus.id], ["2026-11-11"])
    }

    // MARK: - Feature runs (D6)

    func testMushroomSeasonIsActiveOnTheOwnersTestDay() async throws {
        let feature = SeasonalEventsFeature(directory: directory)
        let update = await feature.update(context(snapshot(["2026-09-24": ["Houbová polévka"]], today: "2026-09-24")))
        XCTAssertTrue(update.grants.isEmpty)
        XCTAssertEqual(update.summary?.title, try event("mushrooms").title)

        let banner = await feature.bannerEvent(now: noon("2026-09-24"), calendar: Self.calendar)
        XCTAssertEqual(banner?.eventId, "mushrooms")
        XCTAssertEqual(banner?.phase, .active)
        XCTAssertEqual(banner?.requiredQuests.first?.progress, 1)
        XCTAssertEqual(banner?.requiredQuests.first?.target, 3)
        XCTAssertEqual(banner?.daysLeft, 38)
    }

    func testProgressIsStickyAcrossRunsBeyondTheSignalsWindow() async throws {
        let feature = SeasonalEventsFeature(directory: directory)
        _ = await feature.update(context(snapshot([
            "2026-06-22": ["Špekáček"], "2026-06-28": ["Grilovaná klobása"]
        ], today: "2026-06-28")))
        let later = await feature.update(context(snapshot([
            "2026-08-20": ["Hovězí steak"], "2026-08-21": ["Čevapčiči"]
        ], today: "2026-08-21")))
        XCTAssertTrue(later.grants.contains(RewardGrant(key: "seasonal.event.grill.2026", kind: .xp(50))))
        XCTAssertTrue(later.unlockBadgeIds.contains("event.grill"))

        // A fresh instance reading the same file sees the stored progress.
        let reopened = SeasonalEventsFeature(directory: directory)
        let overview = await reopened.yearOverview(now: noon("2026-08-21"), calendar: Self.calendar)
        let grill = try XCTUnwrap(overview.first { $0.eventId == "grill" })
        XCTAssertTrue(grill.isCompleted)
        XCTAssertEqual(grill.completedYears, [2026])
    }

    func testCompletionIsIdempotentWithinAYearAndRepeatsNextYear() async throws {
        let feature = SeasonalEventsFeature(directory: directory)
        let first = await feature.update(context(snapshot(["2026-01-01": ["Čočka na kyselo"]], today: "2026-01-01")))
        let key2026 = "seasonal.event.novy-rok.2026"
        XCTAssertEqual(first.grants.filter { $0.key == key2026 }, [RewardGrant(key: key2026, kind: .xp(50))])
        XCTAssertEqual(first.unlockBadgeIds, ["event.novy-rok"])
        XCTAssertEqual(first.moments.filter { $0.style == .event }.count, 1)

        let again = await feature.update(context(
            snapshot(["2026-01-01": ["Čočka na kyselo"]], today: "2026-01-01"),
            unlocked: ["event.novy-rok"]
        ))
        XCTAssertEqual(again.grants.filter { $0.key == key2026 }.count, 1, "re-sent; RewardLedger dedups by key")
        XCTAssertTrue(again.moments.isEmpty)
        XCTAssertTrue(again.unlockBadgeIds.isEmpty)

        let nextYear = await feature.update(context(
            snapshot(["2027-01-01": ["Čočková polévka"]], today: "2027-01-01"),
            unlocked: ["event.novy-rok"]
        ))
        XCTAssertTrue(nextYear.grants.contains(RewardGrant(key: "seasonal.event.novy-rok.2027", kind: .xp(50))))
        XCTAssertFalse(nextYear.unlockBadgeIds.contains("event.novy-rok"))
        XCTAssertEqual(nextYear.moments.count, 1)
        let years = await SeasonalStore(directory: directory).completedYears(eventId: "novy-rok")
        XCTAssertEqual(years, [2026, 2027])
    }

    func testBonusQuestGrantsOncePerYear() async throws {
        let feature = SeasonalEventsFeature(directory: directory)
        let run = await feature.update(context(snapshot(["2026-12-31": ["Chlebíček se šunkou", "Jednohubky"]], today: "2026-12-31")))
        XCTAssertTrue(run.grants.contains(RewardGrant(key: "seasonal.event.silvestr.2026", kind: .xp(50))))
        XCTAssertTrue(run.grants.contains(RewardGrant(key: "seasonal.event.silvestr.2026.bonus.jednohubky", kind: .xp(25))))
        XCTAssertEqual(run.moments.count, 2)
        let rerun = await feature.update(context(snapshot(["2026-12-31": ["Jednohubky"]], today: "2026-12-31")))
        XCTAssertTrue(rerun.moments.isEmpty)
    }

    // MARK: - Name day (D4)

    func testNameDayEventUsesTheProfileName() async throws {
        let feature = SeasonalEventsFeature(directory: directory)
        let update = await feature.update(context(snapshot(["2026-04-24": ["Rohlík"]], today: "2026-04-24", firstName: "Jiří")))
        XCTAssertTrue(update.grants.contains(RewardGrant(key: "seasonal.event.name-day.2026", kind: .xp(50))))
        XCTAssertTrue(update.unlockBadgeIds.contains("event.name-day"))
        XCTAssertEqual(update.moments.first?.title.contains("Jiří"), true)
    }

    func testUnknownNameMeansNoNameDayEvent() async throws {
        XCTAssertEqual(SeasonalEventCatalog.events(inYear: 2026, nameDay: nil).count, 11)
        XCTAssertEqual(SeasonalEventCatalog.events(inYear: 2026, nameDay: .init(month: 4, day: 24)).count, 12)
        let feature = SeasonalEventsFeature(directory: directory)
        let update = await feature.update(context(snapshot(["2026-04-24": ["Rohlík"]], today: "2026-04-24", firstName: "Xyzzy")))
        XCTAssertFalse(update.grants.contains { $0.key.contains("name-day") })
        let overview = await feature.yearOverview(now: noon("2026-04-24"), calendar: Self.calendar)
        XCTAssertFalse(overview.contains { $0.eventId == SeasonalEventCatalog.nameDayEventId })
        XCTAssertEqual(overview.count, 11)
    }

    // MARK: - Collector badges (D6)

    func testCollectorCounts() {
        let fixed = SeasonalEventCatalog.all.map(\.id).filter { $0 != SeasonalEventCatalog.nameDayEventId }
        func years(_ ids: [String], _ year: Int = 2026) -> [String: [Int]] {
            Dictionary(uniqueKeysWithValues: ids.map { ($0, [year]) })
        }
        XCTAssertEqual(SeasonalEvaluator.collectorBadgeIds(completedYears: years(Array(fixed.prefix(3))), nameDay: nil), [])
        XCTAssertEqual(
            SeasonalEvaluator.collectorBadgeIds(completedYears: years(Array(fixed.prefix(4))), nameDay: nil),
            [SeasonalEventCatalog.collector4BadgeId]
        )
        XCTAssertEqual(
            SeasonalEvaluator.collectorBadgeIds(completedYears: years(Array(fixed.prefix(8))), nameDay: nil),
            [SeasonalEventCatalog.collector4BadgeId, SeasonalEventCatalog.collector8BadgeId]
        )
        // Name unknown: the 11 fixed events are the whole year.
        XCTAssertTrue(SeasonalEvaluator.collectorBadgeIds(completedYears: years(fixed), nameDay: nil)
            .contains(SeasonalEventCatalog.fullYearBadgeId))
        // Name known: the name day is part of the full year.
        let jiri = SeasonalCalendar.MonthDay(month: 4, day: 24)
        XCTAssertFalse(SeasonalEvaluator.collectorBadgeIds(completedYears: years(fixed), nameDay: jiri)
            .contains(SeasonalEventCatalog.fullYearBadgeId))
        XCTAssertTrue(SeasonalEvaluator.collectorBadgeIds(
            completedYears: years(fixed + [SeasonalEventCatalog.nameDayEventId]),
            nameDay: jiri
        ).contains(SeasonalEventCatalog.fullYearBadgeId))
        // Spread over two years is not a full year.
        var split = years(Array(fixed.prefix(6)), 2026)
        for id in fixed.dropFirst(6) { split[id] = [2027] }
        XCTAssertFalse(SeasonalEvaluator.collectorBadgeIds(completedYears: split, nameDay: nil)
            .contains(SeasonalEventCatalog.fullYearBadgeId))
    }

    // MARK: - Store

    func testStoreQuarantinesAnUndecodableFile() async throws {
        let url = directory.appendingPathComponent("seasonal.json")
        try Data("not json".utf8).write(to: url)
        let store = SeasonalStore(directory: directory)
        let years = await store.completedYears()
        XCTAssertTrue(years.isEmpty)
        await store.recordCompletion(eventId: "easter", year: 2026)
        try await store.save()
        let reopened = await SeasonalStore(directory: directory).completedYears(eventId: "easter")
        XCTAssertEqual(reopened, [2026])
    }

    func testStorePrunesOldProgressButKeepsHistory() async throws {
        let store = SeasonalStore(directory: directory)
        await store.setMarks(["treat": ["2024-02-08"]], eventId: "masopust", year: 2024)
        await store.setMarks(["treat": ["2026-02-12"]], eventId: "masopust", year: 2026)
        await store.recordCompletion(eventId: "masopust", year: 2024)
        await store.pruneMarks(keepingFrom: 2025)
        let old = await store.marks(eventId: "masopust", year: 2024)
        let current = await store.marks(eventId: "masopust", year: 2026)
        let history = await store.completedYears(eventId: "masopust")
        XCTAssertTrue(old.isEmpty)
        XCTAssertEqual(current["treat"], ["2026-02-12"])
        XCTAssertEqual(history, [2024])
    }
}
