// DailyCheckInTests.swift
//
// add-daily-checkin-and-pain-mode, on the vault's two contract fixtures
// (re-mirrored for its daily check-in context) and small mutations of the
// example:
//
//   - the contract: top-level `days` (day skeletons), `athlete.painMode`
//     and the full `day.fuel` on every day decode, tolerantly; the golden
//     check of the example's fuel days that
//     add-winter-arc-nutrition-and-rewards task 5.3 waited for;
//   - every day works: a date is found in a written week, else among the
//     skeletons -- the check-in row, habit ticks, fuel targets, reward
//     facts and reminders work outside the written weeks and with no plan
//     at all (the minimal fixture);
//   - pain mode: the vault's word, or this phone's own unread pain answer;
//     outside it the check-in is the light with a "Something hurts?" link,
//     no pain line and no pain tags;
//   - the reminders: a check-in reminder every day, short outside pain
//     mode, at the owner's times.
//
// The example's season is synthetic (2030/31): 2030-W41...W44 are written,
// 2030-11-04...17 are skeletons, pain mode is on. The minimal fixture has
// no plan, 42 skeletons (2030-10-07...11-17) and pain mode off.

import XCTest
@testable import TrainingCore

final class DailyCheckInTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_918_951_651)
    private let prague = TimeZone(identifier: "Europe/Prague")!
    /// 2030-10-23 00:00 in Prague.
    private let midnight = Date(timeIntervalSince1970: 1_918_936_800)
    /// A skeleton day of the example (Tue of the unwritten W45).
    private let skeleton = D.date("2030-11-05")

    // MARK: - Helpers

    private func logged(_ payload: HubEventPayload, seq: Int, device: String = "ios-0000beef", segment: UUID? = nil) -> LoggedEvent {
        LoggedEvent(
            event: HubEvent(id: "id-\(seq)", deviceId: device, seq: seq, at: "t", payload: payload),
            recordedAt: t0.addingTimeInterval(Double(seq)),
            segmentID: segment
        )
    }

    private func checkIn(_ date: LocalDate, _ light: MorningLight = .amberLight, pains: [PainEntry]? = nil) -> HubEventPayload {
        .morningCheckIn(MorningCheckInPayload(date: date, light: light, sessionId: nil, pains: pains))
    }

    private func projection(_ data: Data) throws -> Projection {
        guard case .success(let decoded) = ProjectionDecoder.decode(data) else {
            XCTFail("fixture did not decode")
            throw ProjectionRejection.invalid(reason: "test")
        }
        return decoded.projection
    }

    private func snapshot(
        _ events: [LoggedEvent] = [],
        data: Data? = nil,
        acked: [String: Int] = [:],
        enabled: Bool = true
    ) throws -> TrainingSnapshot {
        TrainingSnapshot(
            projection: try projection(try data ?? Fixtures.example()),
            checkIns: CheckInOverlay.fold(events, unsentSegments: [], ackedSeqs: acked),
            capabilities: .checkIns(enabled: enabled)
        )
    }

    private func today(_ snapshot: TrainingSnapshot, _ language: TrainingLanguage = .english) -> TodayTrainingBuilder {
        TodayTrainingBuilder(source: .loaded(snapshot), language: language)
    }

    /// The example with pain mode off (as the vault writes it when off).
    private func healthyExample() throws -> Data {
        try Fixtures.mutatedExample { object in
            var athlete = try XCTUnwrap(object["athlete"] as? [String: Any])
            let off: [String: Any] = ["active": false, "since": NSNull(), "sites": [Any](), "reason": NSNull(), "clearsAfter": NSNull()]
            athlete["painMode"] = off
            object["athlete"] = athlete
        }
    }

    // MARK: - The contract

    func testTheExampleHasSkeletonsAndPainMode() throws {
        let decoded = try Fixtures.exampleProjection()
        XCTAssertTrue(decoded.issues.isEmpty, decoded.issues.summary ?? "")
        let projection = decoded.projection
        XCTAssertEqual(projection.days.count, 14)
        XCTAssertEqual(projection.days.first?.date, D.date("2030-11-04"))
        XCTAssertEqual(projection.days.last?.date, D.date("2030-11-17"))
        XCTAssertTrue(projection.days.allSatisfy { $0.sessions.isEmpty })
        XCTAssertEqual(projection.days.first?.habitsExpected, ["holds", "gym"])

        let mode = try XCTUnwrap(projection.athlete.painMode)
        XCTAssertTrue(mode.active)
        XCTAssertEqual(mode.since, D.date("2030-10-14"))
        XCTAssertEqual(mode.sites, [.achillesLeft, .kneeRight])
        XCTAssertEqual(mode.reason, .known(.light))
        XCTAssertEqual(mode.clearsAfter, D.date("2030-10-30"))
    }

    func testTheMinimalFixtureHasEveryWindowDayAsASkeleton() throws {
        let projection = try projection(try Fixtures.minimal())
        XCTAssertNil(projection.plan)
        XCTAssertEqual(projection.days.count, 42)
        XCTAssertEqual(projection.days.first?.date, D.date("2030-10-07"))
        XCTAssertEqual(projection.days.last?.date, D.date("2030-11-17"))
        XCTAssertEqual(projection.athlete.painMode, PainMode.inactive)
        XCTAssertTrue(projection.days.allSatisfy { $0.fuel?.kind == .known(.daily) })
    }

    /// add-winter-arc-nutrition-and-rewards task 5.3: the golden check of
    /// the example's fuel, on every day.
    func testTheExamplesFuelOnEveryDay() throws {
        let snapshot = try Fixtures.exampleSnapshot()
        let days = snapshot.allDays
        XCTAssertEqual(days.count, 42, "four written weeks and fourteen skeletons")
        XCTAssertTrue(days.allSatisfy { $0.fuel != nil }, "fuel is on every day")
        XCTAssertEqual(Set(days.compactMap { $0.fuel?.load?.known }), Set(DayFuelLoad.allCases), "all five loads")
        XCTAssertEqual(Set(days.compactMap { $0.fuel?.fasting?.known }), Set(DayFastingPolicy.allCases), "both fasting values")
        XCTAssertEqual(days.filter { $0.fuel?.isCarbLoad == true }.map(\.date), [D.date("2030-11-01"), D.date("2030-11-02")])

        // A daily day of a build week: a band, fasting off with its reasons.
        let wednesday = try XCTUnwrap(snapshot.day(D.asOf)?.fuel)
        XCTAssertEqual(wednesday.kind, .known(.daily))
        XCTAssertFalse(wednesday.isCarbLoad)
        XCTAssertNil(wednesday.raceId)
        XCTAssertNil(wednesday.carbsGPerKg)
        XCTAssertNil(wednesday.carbsG)
        XCTAssertEqual(wednesday.carbsBand, GramsPerKgRange(min: 5, max: 7))
        XCTAssertEqual(wednesday.proteinGPerKg, 1.6)
        XCTAssertEqual(wednesday.fasting, .known(.off))
        XCTAssertEqual(wednesday.fastingReasons, [.known(.buildWeek), .known(.longSession)])
        XCTAssertEqual(wednesday.load, .known(.moderate))
        XCTAssertEqual(wednesday.plannedMin, 60)
        XCTAssertEqual(wednesday.rules, ["PM-FUEL-1", "PM-FUEL-4"])

        // A light and a high day.
        let thursday = try XCTUnwrap(snapshot.day(D.date("2030-10-24"))?.fuel)
        XCTAssertEqual(thursday.load, .known(.light))
        XCTAssertEqual(thursday.plannedMin, 18)
        XCTAssertEqual(thursday.carbsBand, GramsPerKgRange(min: 3, max: 5))
        let saturday = try XCTUnwrap(snapshot.day(D.date("2030-10-26"))?.fuel)
        XCTAssertEqual(saturday.load, .known(.high))
        XCTAssertEqual(saturday.carbsBand, GramsPerKgRange(min: 6, max: 10))

        // A carb-load day: one number, its grams and its race.
        let friday = try XCTUnwrap(snapshot.day(D.date("2030-11-01"))?.fuel)
        XCTAssertTrue(friday.isCarbLoad)
        XCTAssertEqual(friday.kind, .known(.carbLoad))
        XCTAssertEqual(friday.raceId, "valley-30k-2030")
        XCTAssertEqual(friday.carbsGPerKg, 8)
        XCTAssertEqual(friday.carbsG, 560)
        XCTAssertNil(friday.carbsBand)
        XCTAssertEqual(friday.load, .known(.carbLoad))
        XCTAssertEqual(friday.fastingReasons, [.known(.carbLoad)])

        // A skeleton: a rest day, fasting allowed.
        let unwritten = try XCTUnwrap(snapshot.day(skeleton)?.fuel)
        XCTAssertEqual(unwritten.load, .known(.rest))
        XCTAssertEqual(unwritten.fasting, .known(.allowed))
        XCTAssertTrue(unwritten.fastingReasons.isEmpty)
        XCTAssertEqual(unwritten.plannedMin, 0)
    }

    /// The gram targets the food side reads (the athlete weighs 70 kg).
    func testFuelTargetsOnTheExample() throws {
        let snapshot = try Fixtures.exampleSnapshot()
        let daily = try XCTUnwrap(snapshot.fuelTargets(on: D.asOf))
        XCTAssertEqual(try XCTUnwrap(daily.carbsMinG), 350, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(daily.carbsMaxG), 490, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(daily.proteinG), 112, accuracy: 1e-6)
        XCTAssertFalse(daily.isCarbLoad, "a fuel on the day is not a carb load")
        XCTAssertTrue(daily.isFastingPaused)
        XCTAssertTrue(daily.hasTrainingSessions)

        let load = try XCTUnwrap(snapshot.fuelTargets(on: D.date("2030-11-01")))
        XCTAssertTrue(load.isCarbLoad)
        XCTAssertEqual(try XCTUnwrap(load.carbsMinG), 560, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(load.carbsMaxG), 560, accuracy: 1e-6)

        // A skeleton day has targets too.
        let rest = try XCTUnwrap(snapshot.fuelTargets(on: skeleton))
        XCTAssertEqual(try XCTUnwrap(rest.carbsMinG), 210, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(rest.carbsMaxG), 350, accuracy: 1e-6)
        XCTAssertFalse(rest.isCarbLoad)
        XCTAssertFalse(rest.isFastingPaused)
        XCTAssertFalse(rest.hasTrainingSessions)

        // And with no plan at all.
        let minimal = try self.snapshot(data: try Fixtures.minimal())
        let noPlan = try XCTUnwrap(minimal.fuelTargets(on: D.asOf))
        XCTAssertEqual(try XCTUnwrap(noPlan.carbsMaxG), 350, accuracy: 1e-6)
        XCTAssertNil(snapshot.fuelTargets(on: D.date("2031-06-01")), "outside the file's window")
    }

    /// Only a carb-load day gets the carb-load line -- never "a day with a
    /// fuel", which is every day now.
    func testOnlyACarbLoadDayHasTheCarbLoadLine() throws {
        let builder = today(try Fixtures.exampleSnapshot())
        XCTAssertNil(builder.trainingDay(on: D.asOf).carbLoadLine)
        XCTAssertNil(builder.trainingDay(on: skeleton).carbLoadLine)
        XCTAssertEqual(builder.trainingDay(on: D.date("2030-11-01")).carbLoadLine, "Carb load: 560 g carbs (8 g/kg)")
        let plan = PlanBuilder(source: .loaded(try Fixtures.exampleSnapshot()), language: .english, today: D.asOf)
        XCTAssertNil(plan.dayRow(D.asOf).fuelLine)
        XCTAssertEqual(plan.dayRow(D.date("2030-11-02")).fuelLine, "Carb load: 700 g carbs (10 g/kg)")

        // A fuel from before `kind` covered every day: the single number.
        let old = try JSONDecoder().decode(DayFuel.self, from: Data(#"{"carbsGPerKg": 8, "carbsG": 560}"#.utf8))
        XCTAssertTrue(old.isCarbLoad)
        let band = try JSONDecoder().decode(DayFuel.self, from: Data(#"{"carbsGPerKg": {"min": 5, "max": 7}}"#.utf8))
        XCTAssertFalse(band.isCarbLoad)
    }

    func testTolerantFuelAndPainMode() throws {
        let fuel = try JSONDecoder().decode(DayFuel.self, from: Data(#"""
        { "kind": "snack", "load": "monster", "fasting": "sometimes",
          "fastingReasons": ["build-week", "moon", 3], "plannedMin": "long", "rules": "all" }
        """#.utf8))
        XCTAssertEqual(fuel.kind, .unknown("snack"))
        XCTAssertFalse(fuel.isCarbLoad)
        XCTAssertEqual(fuel.load, .unknown("monster"))
        XCTAssertNil(fuel.fasting?.known)
        XCTAssertFalse(fuel.isFastingOff)
        XCTAssertEqual(fuel.fastingReasons, [.known(.buildWeek), .unknown("moon")])
        XCTAssertNil(fuel.plannedMin)
        XCTAssertTrue(fuel.rules.isEmpty)

        let mode = try JSONDecoder().decode(PainMode.self, from: Data(#"""
        { "active": "yes", "since": "soon", "sites": ["achilles-left", "hip", "elbow"], "reason": "vibes" }
        """#.utf8))
        XCTAssertFalse(mode.active, "not a boolean = off")
        XCTAssertNil(mode.since)
        XCTAssertEqual(mode.sites, [.achillesLeft, .other])
        XCTAssertEqual(mode.reason, .unknown("vibes"))
        XCTAssertNil(mode.clearsAfter)

        // A file from before the change: no `days`, no `painMode`.
        let old = try Fixtures.mutatedExample { object in
            object["days"] = nil
            var athlete = try XCTUnwrap(object["athlete"] as? [String: Any])
            athlete["painMode"] = nil
            object["athlete"] = athlete
        }
        let before = try projection(old)
        XCTAssertTrue(before.days.isEmpty)
        XCTAssertNil(before.athlete.painMode)
        XCTAssertFalse(TrainingSnapshot(projection: before).painMode.isActive)
    }

    func testASkeletonNeverRepeatsADate() throws {
        let data = try Fixtures.mutatedExample { object in
            var days = try XCTUnwrap(object["days"] as? [[String: Any]])
            var planned = days[0]
            planned["date"] = "2030-10-23"
            days.append(planned)
            days.append(days[0])
            object["days"] = days
        }
        let projection = try projection(data)
        XCTAssertEqual(projection.days.count, 14)
        XCTAssertFalse(projection.days.contains { $0.date == D.asOf }, "a written week's date stays the week's")
        // The written week's day wins the lookup.
        XCTAssertEqual(TrainingSnapshot(projection: projection).day(D.asOf)?.sessions.isEmpty, false)
    }

    // MARK: - Every day works

    func testADateIsFoundInAWeekElseAmongTheSkeletons() throws {
        let snapshot = try Fixtures.exampleSnapshot()
        XCTAssertEqual(snapshot.day(D.asOf)?.sessions.first?.id, "2030-w43-wed-am")
        XCTAssertNil(snapshot.plan?.day(skeleton))
        XCTAssertEqual(snapshot.day(skeleton)?.habitsExpected, ["holds"])
        XCTAssertEqual(snapshot.day(D.date("2030-11-04"))?.habitsExpected, ["holds", "gym"], "Monday is a gym day")
        XCTAssertNil(snapshot.day(D.date("2031-06-01")))
    }

    func testTheCheckInWorksOnASkeletonDay() throws {
        let empty = try XCTUnwrap(today(try snapshot()).trainingDay(on: skeleton).checkIn)
        XCTAssertNil(empty.selected)
        XCTAssertNil(empty.sessionID)
        XCTAssertEqual(empty.buttons.count, 3)

        // A check-in (a lock-screen Control records exactly this) shows.
        let model = today(try snapshot([logged(checkIn(skeleton), seq: 1)])).trainingDay(on: skeleton)
        XCTAssertEqual(model.checkIn?.selected, .amberLight)
        XCTAssertEqual(model.checkIn?.deliveryLine, "Saved on phone")
        XCTAssertEqual(model.lightLine, "Morning check: Amber")
        XCTAssertEqual(model.emptyState?.kind, .weekNotWritten)
    }

    func testTheCheckInWorksWithoutAPlan() throws {
        let data = try Fixtures.minimal()
        let empty = today(try snapshot(data: data)).trainingDay(on: D.asOf)
        XCTAssertEqual(empty.emptyState?.kind, .noActivePlan)
        XCTAssertEqual(empty.checkIn?.buttons.count, 3)
        XCTAssertNil(empty.checkIn?.selected)

        let model = today(try snapshot([logged(checkIn(D.asOf, .greenLight), seq: 1)], data: data)).trainingDay(on: D.asOf)
        XCTAssertEqual(model.checkIn?.selected, .greenLight)
        XCTAssertEqual(model.lightLine, "Morning check: Green")
        XCTAssertNil(today(try snapshot(data: data, enabled: false)).trainingDay(on: D.asOf).checkIn)
    }

    /// A stale copy: a date the file doesn't cover still takes a check-in,
    /// and shows the phone's own.
    func testTheCheckInWorksOutsideTheFile() throws {
        let far = D.date("2031-06-01")
        let model = today(try snapshot([logged(checkIn(far, .redLight), seq: 1)])).trainingDay(on: far)
        XCTAssertEqual(model.checkIn?.selected, .redLight)
    }

    func testHabitsAreTickableOnASkeletonDay() throws {
        let monday = D.date("2030-11-04")
        let card = try XCTUnwrap(today(try snapshot()).habitsCard(on: monday))
        XCTAssertEqual(card.rows.filter(\.isScheduledToday).map(\.id), ["holds", "gym"])
        XCTAssertEqual(card.expectedCount, 2)
        XCTAssertEqual(card.doneCount, 0)
        XCTAssertEqual(today(try snapshot()).habits(on: monday).map(\.tick), [.tickable(done: false, pending: false), .tickable(done: false, pending: false)])

        let tick = logged(.habitTick(HabitTickPayload(date: monday, habitId: "gym", done: true)), seq: 1)
        let ticked = try XCTUnwrap(today(try snapshot([tick])).habitsCard(on: monday))
        XCTAssertEqual(ticked.doneCount, 1)
    }

    func testPlanShowsACheckInOnAnUnwrittenWeek() throws {
        let plain = PlanBuilder(source: .loaded(try snapshot()), language: .english, today: D.asOf)
        XCTAssertTrue(plain.week(D.week("2030-W45")).unwrittenDays.isEmpty)
        guard case .days = plain.week(D.week("2030-W43")).content else { return XCTFail("W43 is written") }
        XCTAssertTrue(plain.week(D.week("2030-W43")).unwrittenDays.isEmpty)

        let builder = PlanBuilder(source: .loaded(try snapshot([logged(checkIn(skeleton), seq: 1)])), language: .english, today: D.asOf)
        let week = builder.week(D.week("2030-W45"))
        XCTAssertEqual(week.unwrittenDays.map(\.date), [skeleton])
        XCTAssertEqual(week.unwrittenDays.first?.lightText, "Morning check: Amber")
        XCTAssertNil(week.unwrittenDays.first?.restText, "an unwritten day is not called a rest day")
        XCTAssertEqual(week.content, .outlineOnly("Sessions for this week aren't written yet"))
        XCTAssertEqual(builder.dayRow(skeleton).lightText, "Morning check: Amber")
        let cells = builder.month(year: 2030, month: 11).rows.flatMap(\.cells)
        XCTAssertEqual(cells.first { $0.date == skeleton }?.lightName, "Amber")
    }

    func testRewardFactsCountSkeletonDays() throws {
        let snapshot = try snapshot([logged(checkIn(D.asOf, .greenLight), seq: 1)], data: try Fixtures.minimal())
        let facts = TrainingRewardFacts.build(snapshot: snapshot, today: D.asOf)
        XCTAssertEqual(facts.days.count, 17, "2030-10-07 ... 2030-10-23")
        XCTAssertEqual(facts.days.last?.date, D.asOf)
        XCTAssertEqual(facts.days.last?.checkedIn, true)
        XCTAssertEqual(facts.days.filter(\.checkedIn).count, 1)
        XCTAssertTrue(facts.weeks.isEmpty, "no written week")
    }

    // MARK: - Pain mode

    func testTheVaultsPainModeShowsThePainFeatures() throws {
        let snapshot = try snapshot()
        XCTAssertEqual(snapshot.painMode.origin, .vault)
        let model = today(snapshot).trainingDay(on: D.asOf)
        XCTAssertEqual(model.checkIn?.pain?.isPainMode, true)
        XCTAssertEqual(model.painLine, "Pain: Achilles (left) 5.5/10 · Knee (right) 1/10")

        // A new day in pain mode: the step opens by itself after the light.
        let step = try XCTUnwrap(today(try self.snapshot([logged(checkIn(skeleton), seq: 1)])).trainingDay(on: skeleton).checkIn?.pain)
        XCTAssertTrue(step.isPainMode)
        XCTAssertTrue(step.opensExpanded)
        XCTAssertFalse(step.isRecorded)
        XCTAssertEqual(step.draft, PainDraft.zeros([.achillesLeft]), "the latest earlier day's Achilles site")
        XCTAssertEqual(step.payload(step.draft).date, skeleton)
    }

    func testOutsidePainModeTheCheckInIsTheLightOnly() throws {
        let snapshot = try snapshot(data: try healthyExample())
        XCTAssertFalse(snapshot.painMode.isActive)
        XCTAssertNil(snapshot.painMode.origin)

        let model = today(snapshot).trainingDay(on: D.asOf)
        XCTAssertNil(model.painLine, "no pain line while healthy, even for a recorded answer")
        let step = try XCTUnwrap(model.checkIn?.pain, "the link still needs the step's model")
        XCTAssertFalse(step.isPainMode)
        XCTAssertFalse(step.opensExpanded, "nothing opens by itself")
        XCTAssertEqual(step.somethingHurtsTitle, "Something hurts?")

        // Not asked, not in pain mode: still closed.
        let fresh = try XCTUnwrap(today(try self.snapshot([logged(checkIn(skeleton), seq: 1)], data: try healthyExample())).trainingDay(on: skeleton).checkIn?.pain)
        XCTAssertFalse(fresh.isRecorded)
        XCTAssertFalse(fresh.opensExpanded)

        let plan = PlanBuilder(source: .loaded(snapshot), language: .english, today: D.asOf)
        XCTAssertTrue(plan.dayRow(D.asOf).painTags.isEmpty)

        let czech = try XCTUnwrap(today(snapshot, .czech).trainingDay(on: D.asOf).checkIn?.pain)
        XCTAssertEqual(czech.somethingHurtsTitle, "Něco bolí?")
    }

    func testReportingPainTurnsThePhonesPainModeOn() throws {
        let data = try healthyExample()
        let hurts = logged(checkIn(D.asOf, pains: [PainEntry(site: .kneeLeft, score: 2)]), seq: 1)
        let snapshot = try snapshot([hurts], data: data)
        XCTAssertEqual(snapshot.painMode.origin, .phone)
        XCTAssertFalse(snapshot.painMode.vault.active)
        let model = today(snapshot).trainingDay(on: D.asOf)
        XCTAssertEqual(model.painLine, "Pain: Knee (left) 2/10")
        XCTAssertEqual(model.checkIn?.pain?.isPainMode, true)
        let plan = PlanBuilder(source: .loaded(snapshot), language: .english, today: D.asOf)
        XCTAssertEqual(plan.dayRow(D.asOf).painTags, ["Knee (left) 2/10"])

        // Nothing above 0 is not pain.
        let zero = logged(checkIn(D.asOf, pains: [PainEntry(site: .kneeLeft, score: 0)]), seq: 2)
        XCTAssertFalse(try self.snapshot([zero], data: data).painMode.isActive)
        XCTAssertFalse(try self.snapshot([logged(checkIn(D.asOf, pains: []), seq: 3)], data: data).painMode.isActive)
        // A corrected answer back to 0 turns it off again.
        XCTAssertFalse(try self.snapshot([hurts, zero], data: data).painMode.isActive)
    }

    func testTheVaultsWordEndsThePhonesPainMode() throws {
        let data = try healthyExample()
        // Acknowledged: the vault read the answer and still says "off".
        let acked = logged(checkIn(D.asOf, pains: [PainEntry(site: .kneeLeft, score: 2)]), seq: 4, device: "ios-0a1b2c3d")
        XCTAssertFalse(try snapshot([acked], data: data, acked: ["ios-0a1b2c3d": 24]).painMode.isActive)
        XCTAssertEqual(try snapshot([acked], data: data, acked: ["ios-0a1b2c3d": 3]).painMode.origin, .phone, "seq 4 is past the ack")

        // Not acknowledged, but the file already shows this very answer.
        let same = logged(checkIn(D.asOf, pains: [
            PainEntry(site: .achillesLeft, score: 5.5, note: "Stiff first steps, eases after 10 min"),
            PainEntry(site: .kneeRight, score: 1),
        ]), seq: 5)
        XCTAssertFalse(try snapshot([same], data: data).painMode.isActive)
        XCTAssertEqual(CheckInOverlay.fold([acked, same], unsentSegments: []).unconfirmedPainDates(vaultPains: [:]), [D.asOf])
    }

    // MARK: - Reminders

    func testACheckInReminderOnEveryDay() throws {
        // The minimal fixture: no plan, nothing checked in, no habits.
        let healthy = TrainingReminderPlanner.plan(snapshot: try snapshot(data: try Fixtures.minimal()), today: D.asOf, now: midnight, timeZone: prague, language: .english, days: 7)
        XCTAssertEqual(healthy.map(\.id), (0..<7).map { "checkin.\(D.asOf.adding(days: $0))" })
        XCTAssertTrue(healthy.allSatisfy { $0.hour == 4 && $0.minute == 5 })
        XCTAssertEqual(healthy.first?.title, "How do you feel today?")
        XCTAssertEqual(healthy.first?.body, "Green, amber or red?", "short outside pain mode")

        // A skeleton day of the example: the check-in and its habits.
        let unwritten = TrainingReminderPlanner.plan(snapshot: try snapshot(), today: D.date("2030-11-04"), now: midnight, timeZone: prague, language: .english, days: 1)
        XCTAssertEqual(unwritten.map(\.id), ["checkin.2030-11-04", "habits.2030-11-04"])
        XCTAssertEqual(unwritten.first?.body, "Green, amber or red? Add your pain score too.", "the example is in pain mode")

        // A rest day of a written week gets one too (it used to need a G/A/R session).
        let sunday = TrainingReminderPlanner.plan(snapshot: try snapshot(), today: D.date("2030-10-27"), now: midnight, timeZone: prague, language: .czech, days: 1)
        XCTAssertEqual(sunday.first?.id, "checkin.2030-10-27")
        XCTAssertEqual(sunday.first?.body, "Zelená, oranžová, nebo červená? Přidej i skóre bolesti.")
        let czech = TrainingReminderPlanner.plan(snapshot: try snapshot(data: try Fixtures.minimal()), today: D.asOf, now: midnight, timeZone: prague, language: .czech, days: 1)
        XCTAssertEqual(czech.first?.body, "Zelená, oranžová, nebo červená?")

        // A check-in on a day the file doesn't have removes its reminder.
        let far = D.date("2031-06-01")
        XCTAssertEqual(TrainingReminderPlanner.plan(snapshot: try snapshot(), today: far, now: midnight, timeZone: prague, language: .english, days: 1).map(\.id), ["checkin.2031-06-01"])
        XCTAssertEqual(TrainingReminderPlanner.plan(snapshot: try snapshot([logged(checkIn(far), seq: 1)]), today: far, now: midnight, timeZone: prague, language: .english, days: 1), [])
    }

    func testTheOwnersReminderTimes() throws {
        let times = TrainingReminderTimes(morningHour: 6, morningMinute: 30, eveningHour: 21, eveningMinute: 0)
        let reminders = TrainingReminderPlanner.plan(snapshot: try snapshot(), today: D.asOf, now: midnight, timeZone: prague, language: .english, times: times)
        XCTAssertEqual(reminders.map(\.id), ["checkin.2030-10-24", "habits.2030-10-24"])
        XCTAssertEqual(reminders.map(\.hour), [6, 21])
        XCTAssertEqual(reminders.map(\.minute), [30, 0])
        // 2030-10-24 06:30 in Prague (still summer time) is 04:30Z.
        XCTAssertEqual(TrainingReminderPlanner.fireDate(reminders[0], timeZone: prague), Date(timeIntervalSince1970: 1_919_046_600))

        XCTAssertEqual(TrainingReminderTimes.standard, TrainingReminderTimes(morningHour: 4, morningMinute: 5, eveningHour: 20, eveningMinute: 10))
        // A broken stored value is clamped into a day.
        let broken = TrainingReminderTimes(morningHour: 99, morningMinute: -5, eveningHour: -1, eveningMinute: 75)
        XCTAssertEqual(broken, TrainingReminderTimes(morningHour: 23, morningMinute: 0, eveningHour: 0, eveningMinute: 59))
    }
}
