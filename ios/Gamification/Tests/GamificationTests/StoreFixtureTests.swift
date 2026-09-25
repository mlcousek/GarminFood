// StoreFixtureTests.swift
//
// add-data-safety D2 (see docs/data-compatibility.md): every JSON file a
// Gamification store persists on the owner's phone has a committed fixture
// under Fixtures/Stores/, written exactly as the CURRENT code encodes it (same
// JSONEncoder date strategy -- default seconds-since-2001 Doubles for
// XPStore/ChallengeStore/LifetimeStatsStore, `.iso8601` for
// AchievementStore/ChallengeHistoryStore/RewardLedger/CollectionsStore/
// FeatureStateFile -- same key names, Optional-nil keys omitted,
// String-keyed dictionaries as JSON objects). Each test copies its fixture
// into a fresh temp directory under the store's real file name and reads it
// back THROUGH THE REAL STORE -- not a bare `JSONDecoder` -- because the
// failure this guards against is silent: `GamificationStorage.loadPersistedJSON`
// quarantines an undecodable file (renames it to
// `<name>.unreadable-<stamp>.json`) and the store simply reads as EMPTY. So
// every test asserts specific non-empty decoded values AND that no
// `.unreadable-` file appeared anywhere under the temp directory.
//
// THE RULE: never edit or delete an existing fixture. A fixture is a frozen
// sample of a file that already exists on a real device. When a store's
// format changes, ADD a new fixture next to the old one (e.g. `bingo.v2.json`)
// with its own test, and keep the old one decoding -- if an old fixture stops
// decoding, the change is what's wrong, not the fixture.
//
// `testEveryPersistedFileHasAFixture` keeps this list honest: it scans
// Sources/Gamification for literal `"<name>.json"` file names and fails if a
// store file has no fixture, or if a fixture file isn't covered by a test here.
//
// Depends only on Gamification's stores via `@testable import` (internal
// snapshot fields such as `LifetimeStatsStore.Snapshot.recentDayCalories`).
// The fixture directory is excluded from the test target in Package.swift and
// located on disk via `#filePath`, not bundled as a resource.

import XCTest
@testable import Gamification

final class StoreFixtureTests: XCTestCase {
    // MARK: - Fixture registry

    /// `Fixtures/Stores/`, next to this file.
    private static let fixturesDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/Stores", isDirectory: true)

    /// `ios/Gamification/Sources/Gamification`, derived from this file's
    /// location (`ios/Gamification/Tests/GamificationTests/StoreFixtureTests.swift`).
    private static let sourcesDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // GamificationTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // Gamification (package root)
        .appendingPathComponent("Sources/Gamification", isDirectory: true)

    /// Every fixture a test below loads. A `.json` file in Fixtures/Stores
    /// that is not listed here is an orphan and fails
    /// `testEveryPersistedFileHasAFixture`.
    private static let allFixtures: [String] = [
        "xp-ledger.json",
        "achievements.json",
        "challenge-state.json",
        "challenge-history.json",
        "daily-challenges.json",
        "goal-status.json",
        "lifetime-stats.json",
        "reward-ledger.json",
        "bingo.json",
        "seasonal.json",
        "collections.json",
        "journeys.json",
        "records.json",
        "sport.json",
        "boss.json",
        "streak-freezes.json",
    ]

    /// Literal `"<name>.json"` strings in Sources/Gamification that are NOT a
    /// persisted store file (name -> reason). Empty today: every literal
    /// match is a store file with a fixture above.
    private static let exempt: [String: String] = [:]

    // MARK: - Helpers

    /// Copies `name` from Fixtures/Stores into a fresh, unique temp
    /// directory under the same file name and returns the copy's URL (its
    /// parent directory is what the `init(directory:)` stores take).
    private func copyFixture(_ name: String) throws -> URL {
        let source = Self.fixturesDirectory.appendingPathComponent(name)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gamification-fixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(name)
        try FileManager.default.copyItem(at: source, to: destination)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return destination
    }

    /// Fails if the loader quarantined anything anywhere under `fileURL`'s
    /// directory, or if the fixture copy itself is no longer there.
    private func assertNotQuarantined(_ fileURL: URL, file: StaticString = #filePath, line: UInt = #line) {
        let directory = fileURL.deletingLastPathComponent()
        var quarantined: [String] = []
        if let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) {
            for case let url as URL in enumerator where url.lastPathComponent.contains(".unreadable-") {
                quarantined.append(url.lastPathComponent)
            }
        } else {
            XCTFail("couldn't enumerate \(directory.path)", file: file, line: line)
        }
        XCTAssertTrue(quarantined.isEmpty, "the store could not decode its fixture and quarantined it: \(quarantined)", file: file, line: line)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path), "fixture copy \(fileURL.lastPathComponent) is gone", file: file, line: line)
    }

    /// `.iso8601` JSONEncoder/Decoder use internet date-time, no fractional
    /// seconds -- the same default options as `ISO8601DateFormatter()`.
    private func iso(_ string: String) -> Date {
        ISO8601DateFormatter().date(from: string)!
    }

    // MARK: - xp-ledger.json (XPStore.Snapshot, default JSONEncoder)

    func testXPLedgerFixtureDecodesThroughTheRealStore() async throws {
        let url = try copyFixture("xp-ledger.json")
        let store = XPStore(fileURL: url)

        let total = await store.currentTotal()
        let peak = await store.peakLevel()
        let progress = await store.currentProgress()

        assertNotQuarantined(url)
        XCTAssertEqual(total, 4210)
        // Present in the file, so it is used verbatim (not re-seeded from the curve).
        XCTAssertEqual(peak, 12)
        XCTAssertGreaterThanOrEqual(progress.level, 12, "the displayed level never drops below the stored peak")
        XCTAssertEqual(progress.totalXP, 4210)

        // `lastStreakBonusDay` decoded ("2026-09-20" -> no second streak
        // bonus that day); `lastGoalBonusDay` is absent -> the goal bonus pays.
        let award = try await store.recordLog(nutritionDay: "2026-09-20", streakExtendedToday: true, goalMetToday: true)
        XCTAssertFalse(award.streakBonusAwarded)
        XCTAssertTrue(award.goalBonusAwarded)
        XCTAssertEqual(award.totalXPBefore, 4210)
        XCTAssertEqual(award.peakLevelBefore, 12)
        assertNotQuarantined(url)
    }

    // MARK: - achievements.json (AchievementStore.Snapshot, .iso8601)

    func testAchievementsFixtureDecodesThroughTheRealStore() async throws {
        let url = try copyFixture("achievements.json")
        let store = AchievementStore(fileURL: url)

        let ids = await store.unlockedIds()
        let streakDate = await store.unlockDate(for: "achv-streak-3")
        let challengesDate = await store.unlockDate(for: "achv-challenges-5")
        let all = await store.all()

        assertNotQuarantined(url)
        XCTAssertEqual(ids, ["achv-streak-3", "achv-logs-10", "achv-challenges-5"])
        XCTAssertEqual(streakDate, iso("2026-03-16T07:05:42Z"))
        XCTAssertEqual(challengesDate, iso("2026-09-21T19:02:11Z"))
        XCTAssertEqual(all["achv-logs-10"], iso("2026-03-15T12:40:00Z"))
        XCTAssertEqual(all.count, 3)
    }

    // MARK: - challenge-state.json (ChallengeStore.Snapshot, default JSONEncoder)

    func testChallengeStateFixtureDecodesThroughTheRealStore() async throws {
        let url = try copyFixture("challenge-state.json")
        let store = ChallengeStore(fileURL: url)

        let active = await store.current()

        assertNotQuarantined(url)
        XCTAssertEqual(
            active,
            ActiveChallenge(
                templateId: "protein-push",
                startedAt: Date(timeIntervalSinceReferenceDate: 811579500.25),
                baselineStreakLength: 12
            )
        )
    }

    // MARK: - challenge-history.json ([CompletedChallenge], .iso8601)

    func testChallengeHistoryFixtureDecodesThroughTheRealStore() async throws {
        let url = try copyFixture("challenge-history.json")
        let store = ChallengeHistoryStore(fileURL: url)

        let records = await store.all()

        assertNotQuarantined(url)
        XCTAssertEqual(records.count, 3)
        guard records.count == 3 else { return }

        // `all()` is newest first.
        XCTAssertEqual(records.map(\.templateId), ["carb-cutback", "goal-getter", "perfect-week"])
        XCTAssertEqual(records.map(\.xpAwarded), [75, 50, 50])

        let newest = records[0]
        XCTAssertEqual(newest.id, UUID(uuidString: "3F2A1B0C-9D8E-4F70-8A6B-5C4D3E2F1A03"))
        XCTAssertEqual(newest.completedAt, iso("2026-09-19T21:10:05Z"))

        let oldest = records[2]
        XCTAssertEqual(oldest.id, UUID(uuidString: "3F2A1B0C-9D8E-4F70-8A6B-5C4D3E2F1A01"))
        XCTAssertEqual(oldest.completedAt, iso("2026-09-06T18:20:00Z"))
    }

    // MARK: - daily-challenges.json (DailyChallengeStore.Snapshot, default JSONEncoder)

    func testDailyChallengesFixtureDecodesThroughTheRealStore() async throws {
        let url = try copyFixture("daily-challenges.json")
        let store = DailyChallengeStore(fileURL: url)

        let total = await store.totalCompletedEver()
        let done19 = await store.completedTemplateIds(day: "2026-09-19")
        let done20 = await store.completedTemplateIds(day: "2026-09-20")
        let done21 = await store.completedTemplateIds(day: "2026-09-21")

        assertNotQuarantined(url)
        XCTAssertEqual(total, 37)
        XCTAssertEqual(done19, ["daily-log-3-0", "daily-calorie-goal-1"])
        XCTAssertEqual(done20, ["daily-distinct-5-0"])
        XCTAssertEqual(done21, [])

        // The day's assigned `templateIds` decoded too: a template assigned
        // on 2026-09-21 can be completed once, one never assigned can't, and
        // an already-completed one isn't counted twice.
        let first = try await store.markCompleted(templateId: "daily-log-5-1", day: "2026-09-21")
        let notAssigned = try await store.markCompleted(templateId: "daily-log-3-0", day: "2026-09-21")
        let alreadyDone = try await store.markCompleted(templateId: "daily-log-3-0", day: "2026-09-19")
        XCTAssertTrue(first)
        XCTAssertFalse(notAssigned)
        XCTAssertFalse(alreadyDone)
        let totalAfter = await store.totalCompletedEver()
        XCTAssertEqual(totalAfter, 38)
        assertNotQuarantined(url)
    }

    // MARK: - goal-status.json ([DailyGoalStatus], default JSONEncoder)

    func testGoalStatusFixtureDecodesThroughTheRealStore() async throws {
        let url = try copyFixture("goal-status.json")
        let store = GoalStatusStore(fileURL: url)

        let statuses = await store.all()

        assertNotQuarantined(url)
        XCTAssertEqual(statuses.count, 3)
        guard statuses.count == 3 else { return }

        XCTAssertEqual(statuses.map(\.date), ["2026-09-18", "2026-09-19", "2026-09-20"])
        XCTAssertEqual(
            statuses[0],
            DailyGoalStatus(date: "2026-09-18", metCalorieGoal: true, metProteinGoal: false, metCarbGoal: false, metFatGoal: true)
        )
        XCTAssertFalse(statuses[1].anyGoalMet)
        XCTAssertEqual(
            statuses[2],
            DailyGoalStatus(date: "2026-09-20", metCalorieGoal: true, metProteinGoal: true, metCarbGoal: true, metFatGoal: false)
        )
    }

    // MARK: - lifetime-stats.json (LifetimeStatsStore.Snapshot, default JSONEncoder)

    func testLifetimeStatsFixtureDecodesThroughTheRealStore() async throws {
        let url = try copyFixture("lifetime-stats.json")
        let store = LifetimeStatsStore(fileURL: url)

        let snapshot = await store.current()
        let proteinDays = await store.goalHitDays(.protein)
        let carbDays = await store.goalHitDays(.carbs)

        assertNotQuarantined(url)
        XCTAssertEqual(snapshot.totalLogsEver, 1287)
        XCTAssertEqual(snapshot.totalCaloriesEver, 412356.5)
        XCTAssertEqual(snapshot.maxSingleDayCalories, 4120.25)
        XCTAssertEqual(snapshot.firstLogDate, Date(timeIntervalSinceReferenceDate: 795166330.5))
        XCTAssertEqual(snapshot.goalHitDaysEver, ["calories": 88, "protein": 61, "fat": 40])
        XCTAssertEqual(snapshot.lastCountedGoalDay["fat"], "2026-09-18")
        XCTAssertEqual(snapshot.recentDayCalories, ["2026-09-19": 2210, "2026-09-20": 1985.5])
        XCTAssertEqual(snapshot.recentDayOrder, ["2026-09-19", "2026-09-20"])
        XCTAssertEqual(proteinDays, 61)
        XCTAssertEqual(carbDays, 0)
    }

    // MARK: - reward-ledger.json (RewardLedger.Snapshot, .iso8601)

    func testRewardLedgerFixtureDecodesThroughTheRealStore() async throws {
        let url = try copyFixture("reward-ledger.json")
        let ledger = RewardLedger(fileURL: url)

        let entries = await ledger.all()
        let hasLine = await ledger.contains("bingo.line.2026-W38.row0")
        let hasMinimal = await ledger.contains("journeys.protein.snezka")
        let freezes = await ledger.freezeGrants()

        assertNotQuarantined(url)
        XCTAssertEqual(entries.count, 3)
        guard entries.count == 3 else { return }

        XCTAssertEqual(
            entries[0],
            RewardLedger.Entry(key: "bingo.line.2026-W38.row0", kind: "xp", xp: 40, day: "2026-09-16", appliedAt: iso("2026-09-16T17:30:00Z"))
        )
        XCTAssertEqual(
            entries[1],
            RewardLedger.Entry(key: "boss.freeze.2026-W38", kind: "streakFreeze", xp: nil, day: "2026-09-21", appliedAt: iso("2026-09-21T08:00:12Z"))
        )
        // Only `key` is required; every other field is optional.
        XCTAssertEqual(
            entries[2],
            RewardLedger.Entry(key: "journeys.protein.snezka", kind: nil, xp: nil, day: nil, appliedAt: nil)
        )
        XCTAssertTrue(hasLine)
        XCTAssertTrue(hasMinimal)
        XCTAssertEqual(freezes.map(\.key), ["boss.freeze.2026-W38"])
        XCTAssertEqual(freezes.map(\.day), ["2026-09-21"])
    }

    // MARK: - bingo.json (BingoStore.Snapshot, default JSONEncoder)

    func testBingoFixtureDecodesThroughTheRealStore() async throws {
        let url = try copyFixture("bingo.json")
        let store = BingoStore(directory: url.deletingLastPathComponent())

        let cards = await store.allCards()
        let w38 = await store.card(week: WeekKey(yearForWeek: 2026, week: 38))
        let w37 = await store.card(week: WeekKey(yearForWeek: 2026, week: 37))
        let w39 = await store.card(week: WeekKey(yearForWeek: 2026, week: 39))
        let totalLines = await store.totalLines()
        let fullCards = await store.fullCards()

        assertNotQuarantined(url)
        XCTAssertEqual(cards.map { $0.week.rawValue }, ["2026-W39", "2026-W38", "2026-W37"])
        XCTAssertEqual(totalLines, 9)
        XCTAssertEqual(fullCards, 1)

        // Partly done card.
        XCTAssertEqual(w38?.taskIds.count, 9)
        XCTAssertEqual(w38?.taskIds[4], "free")
        XCTAssertEqual(w38?.completedByIndex, [0: "2026-09-14", 1: "2026-09-15", 2: "2026-09-15", 4: "2026-09-14"])
        XCTAssertEqual(w38?.linesDone, ["row0"])
        XCTAssertNil(w38?.full)
        XCTAssertEqual(w38?.isFull, false)

        // Full card.
        XCTAssertEqual(w37?.isFull, true)
        XCTAssertEqual(w37?.completedByIndex.count, 9)
        XCTAssertEqual(w37?.linesDone?.count, 8)

        // Fresh card: only `taskIds`.
        XCTAssertEqual(w39?.taskIds.first, "e-nuts")
        XCTAssertNil(w39?.completed)
        XCTAssertNil(w39?.linesDone)
        XCTAssertEqual(w39?.completedByIndex, [:])
    }

    // MARK: - seasonal.json (SeasonalStore.Snapshot, default JSONEncoder)

    func testSeasonalFixtureDecodesThroughTheRealStore() async throws {
        let url = try copyFixture("seasonal.json")
        let store = SeasonalStore(directory: url.deletingLastPathComponent())

        let masopust = await store.completedYears(eventId: "masopust")
        let allYears = await store.completedYears()
        let grill = await store.marks(eventId: "grill", year: 2026)
        let strawberries = await store.marks(eventId: "strawberries", year: 2026)
        let grillLastYear = await store.marks(eventId: "grill", year: 2025)
        let name = await store.ownerFirstName()

        assertNotQuarantined(url)
        XCTAssertEqual(masopust, [2025, 2026])
        XCTAssertEqual(allYears["easter"], [2026])
        XCTAssertEqual(allYears.count, 2)
        XCTAssertEqual(grill, ["four-days": ["2026-06-20", "2026-07-04", "2026-08-15"]])
        XCTAssertEqual(strawberries["five-days"]?.count, 2)
        XCTAssertTrue(grillLastYear.isEmpty)
        XCTAssertEqual(name, "Jiří")
    }

    // MARK: - collections.json (CollectionsState, .iso8601)

    func testCollectionsFixtureDecodesThroughTheRealStore() async throws {
        let url = try copyFixture("collections.json")
        // FoodCollectionsFeature builds `<dir>/collections.json`; the store
        // itself takes the file URL.
        let store = CollectionsStore(fileURL: url)

        let loaded = await store.load()

        assertNotQuarantined(url)
        let state = try XCTUnwrap(loaded, "a readable file must not load as nil")
        XCTAssertEqual(state.discovered?.count, 3)
        XCTAssertEqual(state.discovered?["smazeny-syr"], CollectionDiscovery(day: "2026-08-01", foodName: "Smažený sýr s hranolky"))
        XCTAssertEqual(state.discovered?["kysane-zeli"], CollectionDiscovery(day: "2026-09-10", foodName: nil))
        XCTAssertEqual(state.discovered?["pad-thai"], CollectionDiscovery(day: nil, foodName: nil))
        XCTAssertEqual(state.mysteryCzechBarcodes, ["8591234567890", "8590000123456"])
        XCTAssertEqual(state.rainbowDayKeys, ["2026-08-14", "2026-09-03"])
        XCTAssertEqual(state.backfilledAt, iso("2026-08-02T10:12:45Z"))
    }

    // MARK: - journeys.json (JourneysState via FeatureStateFile, .iso8601)

    func testJourneysFixtureDecodesThroughTheRealStore() async throws {
        let url = try copyFixture("journeys.json")
        let store = JourneysStore(directory: url.deletingLastPathComponent())

        let (state, isReadable) = await store.load()

        assertNotQuarantined(url)
        XCTAssertTrue(isReadable)
        XCTAssertFalse(state.isFirstRun)
        XCTAssertEqual(state.startedOn, "2026-08-10")

        // Protein: sealed total + two open days.
        XCTAssertEqual(state.protein?.sealedTotal, 1850.25)
        XCTAssertEqual(state.protein?.ledger?.sealedThrough, "2026-09-18")
        XCTAssertEqual(state.protein?.ledger?.openDays, ["2026-09-19": 142.5, "2026-09-20": 118])
        XCTAssertEqual(state.total(.protein), 1850.25 + 142.5 + 118)
        XCTAssertEqual(state.reachedMilestones(.protein), ["petrin", "lysa-hora", "snezka"])

        // Road trip: ledger without open days, plus the carried weight.
        XCTAssertEqual(state.road?.lastKnownWeightKg, 82.4)
        XCTAssertNil(state.road?.ledger?.openDays)
        XCTAssertNil(state.road?.reachedMilestones)
        XCTAssertEqual(state.total(.road), 212.5)

        // Water never started (absent); passport by distinct food ids.
        XCTAssertNil(state.water)
        XCTAssertEqual(state.total(.water), 0)
        XCTAssertEqual(state.passport?.foodIds, ["5638212", "5712904", "6120033"])
        XCTAssertEqual(state.total(.passport), 3)
        XCTAssertEqual(state.reachedMilestones(.passport), [])
    }

    // MARK: - records.json (RecordsState via FeatureStateFile, .iso8601)

    func testRecordsFixtureDecodesThroughTheRealStore() async throws {
        let url = try copyFixture("records.json")
        let store = RecordsStore(directory: url.deletingLastPathComponent())

        let (state, isReadable) = await store.load()

        assertNotQuarantined(url)
        XCTAssertTrue(isReadable)
        XCTAssertFalse(state.isFirstRun)
        XCTAssertEqual(state.startedOn, "2026-08-10")
        XCTAssertEqual(state.records?.count, 2)
        XCTAssertEqual(state.totalPRs, 3)

        let protein = state.record(.proteinDay)
        XCTAssertEqual(protein.current, RecordMark(value: 188, day: "2026-09-14"))
        XCTAssertEqual(protein.previous, RecordMark(value: 172.5, day: "2026-08-22"))
        XCTAssertEqual(protein.ledger?.sealedThrough, "2026-09-18")
        XCTAssertEqual(protein.ledger?.openDays, ["2026-09-19": 151, "2026-09-20": 96.5])
        XCTAssertEqual(protein.sealedQualifyingDays, 35)
        XCTAssertEqual(protein.qualifyingDays, 37)
        XCTAssertEqual(protein.prCount, 2)

        let distinct = state.record(.distinctFoodsDay)
        XCTAssertEqual(distinct.current, RecordMark(value: 14, day: "2026-08-30"))
        XCTAssertNil(distinct.previous)
        XCTAssertNil(distinct.ledger)
        XCTAssertEqual(distinct.qualifyingDays, 30)

        // Never-set record: empty default, not a decode failure.
        XCTAssertNil(state.record(.waterDay).current)

        XCTAssertEqual(
            state.history,
            [
                PersonalRecordEvent(recordId: "distinct-foods-day", day: "2026-08-30", value: 14, previousValue: nil),
                PersonalRecordEvent(recordId: "protein-day", day: "2026-09-14", value: 188, previousValue: 172.5),
            ]
        )
        XCTAssertEqual(state.waterStreakCarry, WaterStreakCarry(day: "2026-09-18", length: 6))
    }

    // MARK: - sport.json (SportBodyStore.Snapshot, default JSONEncoder)

    func testSportFixtureDecodesThroughTheRealStore() async throws {
        let url = try copyFixture("sport.json")
        let store = SportBodyStore(directory: url.deletingLastPathComponent())

        let fuelled = await store.fuelledActivityIds()
        let recovered = await store.recoveredActivityIds()
        let earned = await store.earnedDays()
        let races = await store.raceDays()
        let day = await store.activityDay(for: "20488003411")
        let september = await store.counts(monthPrefix: "2026-09")

        assertNotQuarantined(url)
        XCTAssertEqual(fuelled, ["20488003411", "20410558312", "20455120987"])
        XCTAssertEqual(recovered, ["20410558312"])
        XCTAssertEqual(earned, ["2026-08-30", "2026-09-06", "2026-09-13"])
        XCTAssertEqual(races, ["2026-09-13"])
        XCTAssertEqual(day, "2026-08-30")
        XCTAssertEqual(september.fuelled, 2)
        XCTAssertEqual(september.recovered, 1)
    }

    // MARK: - boss.json (BossState via FeatureStateFile, .iso8601)

    func testBossFixtureDecodesThroughTheRealStore() async throws {
        let url = try copyFixture("boss.json")
        let store = BossStore(directory: url.deletingLastPathComponent())

        let (state, isReadable) = await store.load()

        assertNotQuarantined(url)
        XCTAssertTrue(isReadable)
        XCTAssertEqual(state.defeatCount, 4)
        XCTAssertEqual(state.defeatedIds, ["breakfast-goblin", "desert-dragon", "soda-lich"])
        XCTAssertEqual(state.perfectDefeat, true)
        XCTAssertEqual(state.weeks?.count, 3)

        let defeated = try XCTUnwrap(state.weeks?["2026-W38"])
        XCTAssertEqual(defeated.kind, .sodaLich)
        XCTAssertEqual(defeated.resolvedOutcome, .defeated)
        XCTAssertEqual(defeated.target, 5)
        XCTAssertEqual(defeated.adherence ?? -1, 15.0 / 28.0, accuracy: 1e-12)
        XCTAssertEqual(defeated.goodDays, 15)
        XCTAssertEqual(defeated.consideredDays, 28)
        XCTAssertEqual(defeated.hitCount, 5)
        XCTAssertEqual(defeated.defeatedOn, "2026-09-18")

        // Still running: no `outcome` key -> active.
        let running = try XCTUnwrap(state.weeks?["2026-W39"])
        XCTAssertEqual(running.kind, .breakfastGoblin)
        XCTAssertNil(running.outcome)
        XCTAssertEqual(running.resolvedOutcome, .active)
        XCTAssertEqual(running.hits, ["2026-09-21"])
        XCTAssertNil(running.defeatedOn)

        // Minimal record: only the required `bossId` plus an outcome.
        let escaped = try XCTUnwrap(state.weeks?["2026-W37"])
        XCTAssertEqual(escaped.kind, .desertDragon)
        XCTAssertEqual(escaped.resolvedOutcome, .escaped)
        XCTAssertNil(escaped.target)
        XCTAssertEqual(escaped.resolvedTarget, 3)
        XCTAssertEqual(escaped.hitCount, 0)
    }

    // MARK: - streak-freezes.json (StreakFreezeStore.Snapshot, default JSONEncoder)

    func testStreakFreezesFixtureDecodesThroughTheRealStore() async throws {
        let url = try copyFixture("streak-freezes.json")
        let store = StreakFreezeStore(directory: url.deletingLastPathComponent())

        let (consumptions, isReadable) = await store.load()
        let frozen = await store.frozenDayKeys()

        assertNotQuarantined(url)
        XCTAssertTrue(isReadable)
        XCTAssertEqual(
            consumptions,
            [
                StreakFreezeStore.Consumption(frozenDay: "2026-09-09", consumedOn: "2026-09-10", protectedLength: 104),
                StreakFreezeStore.Consumption(frozenDay: "2026-09-21", consumedOn: "2026-09-22", protectedLength: nil),
                StreakFreezeStore.Consumption(frozenDay: "2026-08-30", consumedOn: nil, protectedLength: nil),
            ]
        )
        XCTAssertEqual(frozen, ["2026-09-09", "2026-09-21", "2026-08-30"])
    }

    // MARK: - Coverage of the fixture set itself

    func testEveryPersistedFileHasAFixture() throws {
        let fileManager = FileManager.default

        // 1. The fixtures on disk are exactly the ones the tests above use.
        let onDisk = try fileManager.contentsOfDirectory(atPath: Self.fixturesDirectory.path)
            .filter { $0.hasSuffix(".json") }
        XCTAssertEqual(
            Set(onDisk), Set(Self.allFixtures),
            "Fixtures/Stores and StoreFixtureTests.allFixtures disagree -- add a test for a new fixture, never delete an old one"
        )
        XCTAssertEqual(Self.allFixtures.count, Set(Self.allFixtures).count, "allFixtures lists a name twice")

        // 2. Collect every .swift file under Sources/Gamification (recursively:
        //    the feature stores live in Features/<Feature>/ and StreakFreeze/).
        guard let enumerator = fileManager.enumerator(at: Self.sourcesDirectory, includingPropertiesForKeys: nil) else {
            return XCTFail("couldn't enumerate \(Self.sourcesDirectory.path)")
        }
        var sourceFiles: [URL] = []
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
            sourceFiles.append(fileURL)
        }
        XCTAssertFalse(sourceFiles.isEmpty, "found no Swift sources at \(Self.sourcesDirectory.path)")

        // `"<name>.json"` -- a literal file name.
        let literalName = try NSRegularExpression(pattern: "\"([A-Za-z0-9_-]+)\\.json\"")

        var literalFileNames = Set<String>()
        for fileURL in sourceFiles {
            let text = try String(contentsOf: fileURL, encoding: .utf8)
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            for match in literalName.matches(in: text, range: range) {
                if let captured = Range(match.range(at: 1), in: text) {
                    literalFileNames.insert(String(text[captured]) + ".json")
                }
            }
        }

        // Sanity: the scan actually sees stores we know about (top-level and
        // nested feature directories), so a broken path or regex can't make
        // this test pass vacuously.
        XCTAssertTrue(literalFileNames.contains("xp-ledger.json"), "scan found: \(literalFileNames)")
        XCTAssertTrue(literalFileNames.contains("boss.json"), "scan found: \(literalFileNames)")
        XCTAssertTrue(literalFileNames.contains("streak-freezes.json"), "scan found: \(literalFileNames)")

        // 3. Every literal store file name has a fixture (or a stated reason not to).
        let fixtures = Set(Self.allFixtures)
        for name in literalFileNames.sorted() where Self.exempt[name] == nil {
            XCTAssertTrue(
                fixtures.contains(name),
                "\(name) is persisted by Sources/Gamification but has no fixture -- add Fixtures/Stores/\(name) (see docs/data-compatibility.md) and a test here, or an entry in `exempt`"
            )
        }

        // 4. An exemption for a name no longer in the sources is stale.
        for name in Self.exempt.keys.sorted() {
            XCTAssertTrue(literalFileNames.contains(name), "`exempt` lists \(name), which Sources/Gamification no longer mentions")
        }
    }
}
