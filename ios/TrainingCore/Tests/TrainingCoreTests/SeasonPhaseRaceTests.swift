// SeasonPhaseRaceTests.swift
//
// Golden tests of the Season, Phase and Race models on the vault's example
// fixture (add-season-phase-race-screens, tasks 2.x): the timeline's
// fractions, gaps, lanes and countdowns; a phase's header, ramp against
// the vault's `actual`, key sessions, tests and recap; a race's
// checkpoint table (clock times, buffers, section paces), fuel totals,
// carb-load grams from the plan and from the weight formula, gear and
// taper. The fixture is the vault's synthetic 2030/31 season; "today" is
// its `asOf`, Wednesday 23 October 2030. polish-training-today D3: B races
// before the first phase (the season starting earlier than its first
// phase) are drawn, listed, opened and shown on Today's chip.
//
// Czech assertions avoid Foundation's CLDR spacing and month abbreviations
// (they are data, not this code): only our own table strings and numbers
// are compared.

import XCTest
@testable import TrainingCore

final class SeasonPhaseRaceTests: XCTestCase {
    private func builder(_ language: TrainingLanguage = .english, data: Data? = nil, today: LocalDate = D.asOf) throws -> PlanBuilder {
        let bytes = try data ?? Fixtures.example()
        guard case .success(let decoded) = ProjectionDecoder.decode(bytes) else {
            XCTFail("fixture did not decode")
            throw ProjectionRejection.invalid(reason: "test")
        }
        return PlanBuilder(source: .loaded(TrainingSnapshot(projection: decoded.projection)), language: language, today: today)
    }

    /// `object["athlete"]["weightKg"] = value`.
    private static func setWeight(_ object: inout [String: Any], _ value: Any) throws {
        var athlete = try XCTUnwrap(object["athlete"] as? [String: Any])
        athlete["weightKg"] = value
        object["athlete"] = athlete
    }

    // MARK: Season

    func testSeasonTimeline() throws {
        let season = try builder().seasonTimeline()
        XCTAssertNil(season.emptyState)
        XCTAssertEqual(season.title, "Season 2030/31")
        XCTAssertEqual(season.goal, "Finish the ridge ultra healthy")
        // September's abbreviation is CLDR data ("Sep" or "Sept"), so it is
        // taken from DateText rather than spelled here.
        let en = DateText(.english)
        XCTAssertEqual(season.periodText, "\(en.dayMonthYear(D.date("2030-09-02"))) – 31 Aug 2031")

        // 2030-09-02 ... 2031-08-31 is 363 days.
        let span = 363.0
        XCTAssertEqual(season.bands.map(\.id), ["test-prelude-2030", "test-base-2030"])
        let prelude = season.bands[0]
        let base = season.bands[1]
        XCTAssertEqual(prelude.start, 0, accuracy: 1e-9)
        XCTAssertEqual(prelude.end, 41 / span, accuracy: 1e-9)
        XCTAssertEqual(base.start, 42 / span, accuracy: 1e-9)
        XCTAssertEqual(base.end, 151 / span, accuracy: 1e-9)
        XCTAssertEqual(prelude.status, .closed)
        XCTAssertEqual(prelude.statusText, "Closed")
        XCTAssertEqual(prelude.kindText, "Transition")
        XCTAssertEqual(prelude.weeksText, "1 week")
        XCTAssertEqual(prelude.dateText, "\(en.dayMonth(D.date("2030-09-02"))) – 13 Oct 2030")
        XCTAssertFalse(prelude.isSelected)
        XCTAssertEqual(base.statusText, "Active")
        XCTAssertEqual(base.kindText, "Base")
        XCTAssertEqual(base.weeksText, "5 weeks")
        XCTAssertEqual(base.dateText, "14 Oct 2030 – 31 Jan 2031")
        XCTAssertTrue(base.isSelected)
        XCTAssertTrue(base.isCurrent)
        XCTAssertFalse(prelude.isCurrent)

        // The rest of the season has no phase: drawn, not hidden.
        XCTAssertEqual(season.gaps.count, 1)
        XCTAssertEqual(season.gaps.first?.from, D.date("2031-02-01"))
        XCTAssertEqual(season.gaps.first?.to, D.date("2031-08-31"))
        XCTAssertEqual(season.gaps.first?.end, 1)
        XCTAssertEqual(season.gaps.first?.label, "No phase planned")

        XCTAssertEqual(season.today?.date, D.asOf)
        XCTAssertEqual(season.today?.fraction ?? -1, 51 / span, accuracy: 1e-9)
        XCTAssertEqual(season.today?.isClamped, false)

        // Monthly ticks from 1 Oct 2030 to 1 Aug 2031; January carries the year.
        XCTAssertEqual(season.ticks.count, 11)
        XCTAssertEqual(season.ticks.first?.date, D.date("2030-10-01"))
        XCTAssertEqual(season.ticks.first?.label, "Oct")
        XCTAssertEqual(season.ticks.first { $0.date == D.date("2031-01-01") }?.label, "Jan 2031")
        XCTAssertEqual(season.ticks.last?.date, D.date("2031-08-01"))
    }

    func testSeasonRaces() throws {
        let season = try builder().seasonTimeline()
        XCTAssertEqual(season.races.map(\.id), ["lakeside-10k-2030", "valley-30k-2030", "ridge-ultra-2031"])
        let lakeside = season.races[0]
        let valley = season.races[1]
        let ridge = season.races[2]

        XCTAssertTrue(lakeside.isPast)
        XCTAssertEqual(lakeside.countdown, "32 days ago")
        XCTAssertEqual(lakeside.priorityText, "C race")
        XCTAssertEqual(lakeside.distanceText, "10 km")
        XCTAssertNil(lakeside.unanchoredText)

        XCTAssertEqual(valley.countdown, "in 11 days")
        XCTAssertEqual(valley.priority, .b)
        XCTAssertEqual(valley.priorityText, "B race")
        XCTAssertEqual(valley.dateText, "3 Nov 2030")
        XCTAssertEqual(valley.distanceText, "30 km / 900m+")

        XCTAssertTrue(ridge.isHero)
        XCTAssertTrue(ridge.isApproximate)
        XCTAssertEqual(ridge.priorityText, "Hero race")
        XCTAssertEqual(ridge.countdown, "in about 241 days")
        XCTAssertEqual(ridge.unanchoredText, "No phase covers this race yet")
        XCTAssertEqual(ridge.fraction, 292 / 363.0, accuracy: 1e-9)

        // Lakeside and Valley would overlap: two lanes, nothing dropped.
        XCTAssertEqual(season.races.map(\.lane), [0, 1, 0])
        XCTAssertEqual(season.lanes, 2)
        XCTAssertEqual(season.nextRace?.id, "valley-30k-2030")

        let czech = try builder(.czech).seasonTimeline()
        XCTAssertEqual(czech.title, "Sezóna 2030/31")
        XCTAssertEqual(czech.races[0].countdown, "před 32 dny")
        XCTAssertEqual(czech.races[1].countdown, "za 11 dní")
        XCTAssertEqual(czech.races[2].priorityText, "Hlavní závod")
        XCTAssertEqual(czech.gaps.first?.label, "Žádná fáze v plánu")
    }

    /// polish-training-today D3: the season starts two weeks before its
    /// first phase and two B races fall in that gap, with no phase.
    private func earlyBRaces() throws -> Data {
        try Fixtures.mutatedExample { object in
            var season = try XCTUnwrap(object["season"] as? [String: Any])
            var phases = try XCTUnwrap(season["phases"] as? [[String: Any]])
            phases[0]["period"] = ["from": "2030-09-16", "to": "2030-10-13"]
            season["phases"] = phases
            var races = try XCTUnwrap(season["races"] as? [[String: Any]])
            races.append(["id": "relay-2030", "name": "Test Relay", "date": "2030-09-05", "dateApprox": false, "priority": "B", "hero": false, "phaseId": NSNull()])
            races.append(["id": "trail-2030", "name": "Test Trail", "date": "2030-09-12", "dateApprox": false, "priority": "B", "hero": false, "phaseId": NSNull()])
            season["races"] = races
            object["season"] = season
        }
    }

    func testBRacesBeforeTheFirstPhase() throws {
        let data = try earlyBRaces()
        let today = D.date("2030-09-03")
        let season = try builder(data: data, today: today).seasonTimeline()
        // The gap before the first phase is drawn, not hidden.
        XCTAssertEqual(season.gaps.first?.from, D.date("2030-09-02"))
        XCTAssertEqual(season.gaps.first?.to, D.date("2030-09-15"))
        XCTAssertEqual(season.gaps.first?.start, 0)
        XCTAssertEqual(season.gaps.first?.label, "No phase planned")
        // Both B races are on the axis, in date order, none dropped.
        XCTAssertEqual(season.races.map(\.id), ["relay-2030", "trail-2030", "lakeside-10k-2030", "valley-30k-2030", "ridge-ultra-2031"])
        let relay = season.races[0]
        XCTAssertEqual(relay.priority, .b)
        XCTAssertEqual(relay.priorityCode, "B")
        XCTAssertEqual(relay.priorityText, "B race")
        XCTAssertEqual(relay.unanchoredText, "No phase covers this race yet")
        XCTAssertEqual(relay.countdown, "in 2 days")
        XCTAssertFalse(relay.isClamped)
        XCTAssertEqual(Set(season.races.prefix(3).map(\.lane)).count, 3, "three close labels, three lanes")
        XCTAssertEqual(season.nextRace?.id, "relay-2030")

        // The race screen opens an unanchored B race.
        let detail = try XCTUnwrap(try builder(data: data, today: today).raceDetail(id: "trail-2030"))
        XCTAssertEqual(detail.priority, .b)
        XCTAssertEqual(detail.priorityText, "B race")
        XCTAssertNil(detail.phaseTitle)
        XCTAssertEqual(detail.unanchoredText, "No phase covers this race yet")
        XCTAssertTrue(detail.taper.isEmpty)
        XCTAssertEqual(detail.stubText, "Race prep not written yet")
        XCTAssertEqual(try builder(data: data, today: today).nextRaceID(), "relay-2030")

        // Today's chip: the B race next, the hero as the main race.
        guard case .success(let decoded) = ProjectionDecoder.decode(data) else { return XCTFail("did not decode") }
        let chip = try XCTUnwrap(TodayTrainingBuilder(source: .loaded(TrainingSnapshot(projection: decoded.projection)), language: .english).raceChip(from: today))
        XCTAssertEqual(chip.raceID, "relay-2030")
        XCTAssertEqual(chip.priorityText, "B race")
        XCTAssertEqual(chip.countdown, "in 2 days")
        XCTAssertEqual(chip.mainRace?.text, "Main race: Ridge Ultra · in about 291 days")
    }

    func testLanesNeverDropALabel() {
        XCTAssertEqual(SeasonLanes.assign([0.1, 0.15, 0.5, 0.3], width: 0.22), [0, 1, 0, 2])
        XCTAssertEqual(SeasonLanes.assign([], width: 0.22), [])
        XCTAssertEqual(SeasonLanes.assign([0.5, 0.5, 0.5], width: 0.1), [0, 1, 2])
    }

    func testNoSeason() throws {
        let season = try builder(data: try Fixtures.minimal()).seasonTimeline()
        XCTAssertEqual(season.emptyState?.title, "No season yet")
        XCTAssertTrue(season.bands.isEmpty)
        XCTAssertTrue(season.races.isEmpty)
        let waiting = PlanBuilder(source: .waitingForFirstSync, language: .english, today: D.asOf).seasonTimeline()
        XCTAssertEqual(waiting.emptyState?.kind, .fetching)
    }

    func testRacesOutsideTheSeasonAreClampedAndFlagged() throws {
        let data = try Fixtures.mutatedExample { object in
            var season = try XCTUnwrap(object["season"] as? [String: Any])
            var races = try XCTUnwrap(season["races"] as? [[String: Any]])
            races[0]["date"] = "2030-08-01"
            season["races"] = races
            object["season"] = season
        }
        let early = try XCTUnwrap(try builder(data: data).seasonTimeline().races.first)
        XCTAssertEqual(early.fraction, 0)
        XCTAssertTrue(early.isClamped)
    }

    // MARK: Phase

    func testSelectedPhase() throws {
        let phase = try XCTUnwrap(try builder().phaseDetail(id: "test-base-2030"))
        XCTAssertEqual(phase.title, "Test Base 2030")
        XCTAssertEqual(phase.kindText, "Base")
        XCTAssertEqual(phase.statusText, "Active")
        XCTAssertEqual(phase.dateText, "14 Oct 2030 – 31 Jan 2031")
        XCTAssertEqual(phase.progressText, "Week 2 of 16 · 100 days left")
        XCTAssertTrue(phase.isSelected)
        XCTAssertNil(phase.restrictedText)
        XCTAssertEqual(phase.goals, ["Healthy tendon", "Volume"])
        XCTAssertEqual(phase.rules, [
            "Two ambers make the next quality session a ride",
            "A red morning holds next week's volume",
            "Three greens allow a step up",
            "Long run at most 35 % of the week"
        ])
        XCTAssertNil(phase.recap)

        XCTAssertEqual(phase.weeks.map(\.week), ["2030-W42", "2030-W43", "2030-W44", "2030-W45", "2030-W46"].map(D.week))
        // The written week's own target (55) wins over the outline's (50),
        // the same number Plan -> Week shows; W43 is the red-held 55.
        XCTAssertEqual(phase.weeks.map(\.targetKm), [55, 55, 40, 45, nil])
        XCTAssertEqual(phase.weeks.map(\.actualKm), [60.1, 10.1, nil, nil, nil])
        XCTAssertEqual(phase.weeks[0].actualText, "60.1 km")
        XCTAssertEqual(phase.weeks[0].targetText, "55 km")
        XCTAssertEqual(phase.weeks[0].actualFraction, 1)
        XCTAssertEqual(phase.weeks[0].targetFraction ?? 0, 55 / 60.1, accuracy: 1e-9)
        XCTAssertTrue(phase.weeks[1].isCurrent)
        XCTAssertTrue(phase.weeks[2].isFuture)
        XCTAssertNil(phase.weeks[2].actualText)
        XCTAssertEqual(phase.weeks[0].noteText, "Plan starts")

        XCTAssertEqual(phase.keySessions.map(\.id), [
            "2030-w42-wed-pm", "2030-w42-sat-am", "2030-w43-tue-am", "2030-w43-thu-pm", "2030-w43-sat-am",
            // The rule-edited tempo (only R left) is still a key session.
            "2030-w44-wed-am", "2030-w44-sun-am"
        ])
        XCTAssertEqual(phase.keySessions.first?.dateText, "Wed 16 Oct")
        XCTAssertEqual(phase.keySessions.first?.row.badgeText, "Test")
        XCTAssertEqual(phase.tests.map(\.valuesText), ["Left 22 reps · Right 27 reps"])
        XCTAssertEqual(phase.tests.first?.dateText, "Wed 16 Oct")
        XCTAssertEqual(phase.races.map(\.id), ["valley-30k-2030"])

        let czech = try XCTUnwrap(try builder(.czech).phaseDetail(id: "test-base-2030"))
        XCTAssertEqual(czech.progressText, "Týden 2 z 16 · zbývá 100 dní")
        XCTAssertEqual(czech.goals, ["Zdravá šlacha", "Objem"])
        XCTAssertEqual(czech.weeks[0].actualText, "60,1 km")
    }

    func testClosedPhaseHasARecap() throws {
        let phase = try XCTUnwrap(try builder().phaseDetail(id: "test-prelude-2030"))
        XCTAssertFalse(phase.isSelected)
        XCTAssertEqual(phase.restrictedText, "Goals and rules are published for the current phase only.")
        XCTAssertTrue(phase.goals.isEmpty)
        XCTAssertTrue(phase.rules.isEmpty)
        XCTAssertEqual(phase.progressText, "Finished")
        XCTAssertEqual(phase.progressFraction, 1)
        XCTAssertEqual(phase.weeks.map(\.targetKm), [30])
        XCTAssertEqual(phase.weeks.map(\.actualKm), [22.6])

        let recap = try XCTUnwrap(phase.recap)
        XCTAssertEqual(recap.text, "Recovered; tests set the baseline.")
        XCTAssertEqual(recap.runLine, "Ran 22.6 of 30 km planned")
        XCTAssertEqual(recap.withinLine, "0 of 1 weeks within 10 % of target")
        XCTAssertEqual(recap.biggestLine, "Biggest week: 22.6 km (W41)")
        XCTAssertEqual(recap.testLines, [])
        XCTAssertEqual(recap.raceLines, ["Lakeside 10K · \(DateText(.english).dayMonthYear(D.date("2030-09-21")))"])

        XCTAssertNil(try builder().phaseDetail(id: "no-such-phase"))
        XCTAssertEqual(try builder().defaultPhaseID(), "test-base-2030")
    }

    func testRecapTestLinesJudgeTheDirection() throws {
        // Widen the prelude to cover both calf-raise results.
        let data = try Fixtures.mutatedExample { object in
            var season = try XCTUnwrap(object["season"] as? [String: Any])
            var phases = try XCTUnwrap(season["phases"] as? [[String: Any]])
            phases[0]["period"] = ["from": "2030-09-02", "to": "2030-10-20"]
            season["phases"] = phases
            object["season"] = season
        }
        let recap = try XCTUnwrap(try builder(data: data).phaseDetail(id: "test-prelude-2030")?.recap)
        XCTAssertEqual(recap.testLines, ["Left: 18 → 22 reps · Improved", "Right: 24 → 27 reps · Improved"])
    }

    func testPhaseRampTotals() throws {
        let snapshot = try Fixtures.exampleSnapshot()
        let phase = try XCTUnwrap(snapshot.phase(id: "test-base-2030"))
        let ramp = PhaseRamp.series(phase, snapshot: snapshot, today: D.asOf)
        let totals = PhaseRamp.totals(ramp)
        XCTAssertEqual(totals.weeks, 5)
        XCTAssertEqual(totals.plannedTotal, 195)
        XCTAssertEqual(totals.knownWeeks, 2)
        XCTAssertEqual(totals.actualTotal, 70.2)
        XCTAssertEqual(totals.plannedKnown, 110)
        XCTAssertEqual(totals.withinTen, 1)
        XCTAssertEqual(totals.unknownWeeks, 0)
        XCTAssertEqual(totals.biggest, RampPeak(week: D.week("2030-W42"), km: 60.1))
        XCTAssertEqual(totals.meanWeekly, 35.1)
    }

    func testAStartedWeekOutsideTheWindowHasNoActual() throws {
        // Seen from mid-November, W44 has happened, W45 is outside the file.
        let phase = try XCTUnwrap(try builder(today: D.date("2030-11-13")).phaseDetail(id: "test-base-2030"))
        let w45 = try XCTUnwrap(phase.weeks.first { $0.week == D.week("2030-W45") })
        XCTAssertNil(w45.actualKm)
        XCTAssertEqual(w45.actualText, "Not in the app's window")
        XCTAssertFalse(w45.isFuture)
    }

    // MARK: Race

    func testRaceWithPrep() throws {
        let race = try XCTUnwrap(try builder().raceDetail(id: "valley-30k-2030"))
        XCTAssertEqual(race.name, "Test Valley 30K")
        XCTAssertEqual(race.dateText, "Sun 3 Nov 2030")
        XCTAssertEqual(race.priorityText, "B race")
        XCTAssertEqual(race.distanceText, "30 km / 900m+")
        XCTAssertEqual(race.goalText, "Sub-3h")
        XCTAssertEqual(race.countdown, "in 11 days")
        XCTAssertEqual(race.daysUntil, 11)
        XCTAssertEqual(race.phaseTitle, "Test Base 2030")
        XCTAssertNil(race.unanchoredText)
        XCTAssertNil(race.stubText)
        XCTAssertNil(race.reportText)
        XCTAssertEqual(race.startText, "Start 09:00")
        XCTAssertEqual(race.cutoffText, "Cutoff 5 h 30 min · 14:30")
        // Found by `raceId`, wherever the plan put it (a plan command moved
        // it to the day before in the current example).
        XCTAssertEqual(race.sessions.map(\.id), ["2030-w44-sun-am"])

        XCTAssertEqual(race.checkpoints.map(\.name), ["Start", "CP1 Mill", "CP2 Ridge", "Finish"])
        let mill = race.checkpoints[1]
        XCTAssertEqual(mill.kmText, "11.5 km")
        XCTAssertEqual(mill.climbText, "320 m+")
        XCTAssertEqual(mill.aidText, "Water")
        XCTAssertEqual(mill.targetText, "Target 1 h 5 min · 10:05")
        XCTAssertNil(mill.cutoffText)
        XCTAssertNil(mill.bufferText)
        XCTAssertEqual(mill.paceText, "5:39 /km")
        XCTAssertEqual(mill.hrCapText, "≤160 bpm")
        let ridge = race.checkpoints[2]
        XCTAssertEqual(ridge.cutoffText, "Cutoff 3 h 30 min · 12:30")
        XCTAssertEqual(ridge.bufferText, "Buffer 1 h 25 min")
        XCTAssertEqual(ridge.paceText, "6:19 /km")
        let finish = race.checkpoints[3]
        XCTAssertEqual(finish.targetText, "Target 2 h 58 min · 11:58")
        XCTAssertEqual(finish.bufferText, "Buffer 2 h 32 min")
        XCTAssertEqual(finish.paceText, "5:53 /km")
        XCTAssertEqual(finish.aidText, "No aid")
        XCTAssertNil(race.checkpoints[0].paceText)

        XCTAssertEqual(race.fuel?.lines, ["70 g carbs/h", "Every 25 min", "500 ml fluid/h"])
        XCTAssertEqual(race.fuel?.totalLines, ["About 208 g carbs to the finish", "About 1.5 l fluid to the finish"])

        XCTAssertEqual(race.carbLoad.map(\.date), [D.date("2030-11-01"), D.date("2030-11-02")])
        XCTAssertEqual(race.carbLoad.map(\.offsetText), ["2 days before", "1 day before"])
        XCTAssertEqual(race.carbLoad.map(\.amountText), ["560 g carbs · 8 g/kg", "700 g carbs · 10 g/kg"])
        XCTAssertEqual(race.carbLoad.map(\.source), [.plan, .plan])
        XCTAssertEqual(race.carbLoad.first?.sourceText, "From your plan")
        XCTAssertEqual(race.carbLoad.first?.dateText, "Fri 1 Nov")

        XCTAssertEqual(race.gear.map(\.item), ["Soft flask 500 ml", "Wind jacket"])
        XCTAssertEqual(race.gear.map(\.tagText), ["Mandatory", "Optional"])

        XCTAssertEqual(race.taper.map(\.week), [D.week("2030-W43"), D.week("2030-W44")])
        XCTAssertEqual(race.taper.map(\.isRaceWeek), [false, true])
        XCTAssertEqual(race.taper.map(\.isCurrent), [true, false])
        XCTAssertEqual(race.taper.map(\.targetText), ["Run target 55 km", "Run target 40 km"])  // W43 held at 55 by the red-holds rule
        XCTAssertEqual(race.taper.last?.kindText, "Race")
        XCTAssertEqual(race.taper.last?.noteText, "Race week")

        let czech = try XCTUnwrap(try builder(.czech).raceDetail(id: "valley-30k-2030"))
        XCTAssertEqual(czech.countdown, "za 11 dní")
        XCTAssertEqual(czech.carbLoad.map(\.offsetText), ["2 dny před závodem", "1 den před závodem"])
        XCTAssertEqual(czech.carbLoad.first?.amountText, "560 g sacharidů · 8 g/kg")
        XCTAssertEqual(czech.fuel?.totalLines.last, "Zhruba 1,5 l tekutin do cíle")
        XCTAssertEqual(czech.gear.first?.tagText, "Povinné")
    }

    func testCarbLoadOutsideTheWindowUsesTheWeight() throws {
        let data = try Fixtures.mutatedExample { object in
            try Self.setWeight(&object, 72)
            try Fixtures.mutateDay(&object, week: 3, day: 5) { day in day["fuel"] = NSNull() }
        }
        let rows = try XCTUnwrap(try builder(data: data).raceDetail(id: "valley-30k-2030")).carbLoad
        XCTAssertEqual(rows[0].source, .plan)
        XCTAssertEqual(rows[0].grams, 560)
        XCTAssertEqual(rows[1].source, .estimate(weightKg: 72))
        XCTAssertEqual(rows[1].grams, 720)
        XCTAssertEqual(rows[1].amountText, "720 g carbs · 10 g/kg")
        XCTAssertEqual(rows[1].sourceText, "Estimated for 72 kg")

        let noWeight = try Fixtures.mutatedExample { object in
            try Self.setWeight(&object, NSNull())
            try Fixtures.mutateDay(&object, week: 3, day: 5) { day in day["fuel"] = NSNull() }
        }
        let unknown = try XCTUnwrap(try builder(data: noWeight).raceDetail(id: "valley-30k-2030")).carbLoad[1]
        XCTAssertNil(unknown.grams)
        XCTAssertEqual(unknown.source, .unknown)
        XCTAssertEqual(unknown.amountText, "10 g/kg")
        XCTAssertEqual(unknown.sourceText, "No body weight in the plan to count grams")
    }

    func testRacesWithoutPrep() throws {
        let ridge = try XCTUnwrap(try builder().raceDetail(id: "ridge-ultra-2031"))
        XCTAssertEqual(ridge.stubText, "Race prep not written yet")
        XCTAssertEqual(ridge.unanchoredText, "No phase covers this race yet")
        XCTAssertNil(ridge.phaseTitle)
        XCTAssertTrue(ridge.isHero)
        XCTAssertEqual(ridge.priorityText, "A race")
        XCTAssertEqual(ridge.countdown, "in about 241 days")
        XCTAssertTrue(ridge.taper.isEmpty)
        XCTAssertTrue(ridge.checkpoints.isEmpty)
        XCTAssertNil(ridge.fuel)

        let lakeside = try XCTUnwrap(try builder().raceDetail(id: "lakeside-10k-2030"))
        XCTAssertTrue(lakeside.isPast)
        XCTAssertEqual(lakeside.countdown, "32 days ago")
        XCTAssertEqual(lakeside.reportText, "Race report written")

        XCTAssertNil(try builder().raceDetail(id: "no-such-race"))
        XCTAssertEqual(try builder().nextRaceID(), "valley-30k-2030")
        XCTAssertEqual(try builder(today: D.date("2031-07-01")).nextRaceID(), "ridge-ultra-2031")
    }

    // MARK: Display arithmetic

    func testClockAndPace() throws {
        let start = try XCTUnwrap(ClockTime("22:30"))
        XCTAssertEqual(NumberText.clock(start, plus: 200), "01:50 +1 d")
        XCTAssertEqual(NumberText.clock(start, plus: 0), "22:30")
        XCTAssertNil(NumberText.clock(nil, plus: 10))
        XCTAssertNil(NumberText.clock(start, plus: nil))
        XCTAssertEqual(NumberText.pace(minutesPerKm: 65 / 11.5), "5:39 /km")
        XCTAssertNil(NumberText.pace(minutesPerKm: 0))
        XCTAssertEqual(NumberText.percent(0.1852), "19 %")
    }

    func testTheSectionSkipsACheckpointWithoutATarget() throws {
        let data = try Fixtures.mutatedExample { object in
            var season = try XCTUnwrap(object["season"] as? [String: Any])
            var races = try XCTUnwrap(season["races"] as? [[String: Any]])
            var prep = try XCTUnwrap(races[1]["prep"] as? [String: Any])
            var checkpoints = try XCTUnwrap(prep["checkpoints"] as? [[String: Any]])
            checkpoints[2]["targetMin"] = NSNull()
            prep["checkpoints"] = checkpoints
            races[1]["prep"] = prep
            season["races"] = races
            object["season"] = season
        }
        let race = try XCTUnwrap(try builder(data: data).raceDetail(id: "valley-30k-2030"))
        XCTAssertNil(race.checkpoints[2].paceText)
        XCTAssertNil(race.checkpoints[2].bufferText)
        // Finish is measured from CP1 (km 11.5, minute 65): 113 min over 18.5 km.
        XCTAssertEqual(race.checkpoints[3].paceText, NumberText.pace(minutesPerKm: 113 / 18.5))
    }
}
