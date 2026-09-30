// PlanBuilderTests.swift
//
// Golden tests of the Plan tab's models on the vault's example fixture
// (tasks 3.4, 1.4; spec training-plan-view): the week agenda (targets vs
// `actual`, the week's own phase, unplanned rows, outline-only and
// out-of-season weeks, paging), the month grid (42 cells, ISO week numbers
// across a year boundary, glyph styles, race flags, today), the session
// detail (pre-selection, steps, why, done, fuel, test vs history, race)
// and the habit ladder.

import XCTest
@testable import TrainingCore

final class PlanBuilderTests: XCTestCase {
    private func builder(_ language: TrainingLanguage = .english, data: Data? = nil, today: LocalDate = D.asOf) throws -> PlanBuilder {
        let bytes = try data ?? Fixtures.example()
        guard case .success(let decoded) = ProjectionDecoder.decode(bytes) else {
            XCTFail("fixture did not decode")
            throw ProjectionRejection.invalid(reason: "test")
        }
        return PlanBuilder(source: .loaded(TrainingSnapshot(projection: decoded.projection)), language: language, today: today)
    }

    private func days(_ model: WeekAgendaModel) throws -> [DayRowModel] {
        guard case .days(let days) = model.content else {
            XCTFail("expected days, got \(model.content)")
            return []
        }
        return days
    }

    // MARK: Week

    func testWeekInProgress() throws {
        let week = try builder().week(D.week("2030-W43"))
        XCTAssertEqual(week.title, "W43 · 21–27 Oct")
        XCTAssertEqual(week.phaseTitle, "Test Base 2030")
        XCTAssertEqual(week.statusText, "Approved")
        XCTAssertEqual(week.kindText, "Build")
        XCTAssertNil(week.noteText)
        XCTAssertEqual(week.runLine, "Run 10.1 of 55 km")
        XCTAssertEqual(Array(week.ruleNoteLines.prefix(2)), [
            "Red morning on 2030-10-14: volume held at last week's 55 km instead of adding.",
            "Three green mornings in a row (2030-10-16 – 2030-10-18): the next step up is allowed."
        ])
        // add-checkin-pain-score: the vault's pain-high note, shown like any
        // other rule note of the week.
        XCTAssertEqual(week.ruleNoteLines.count, 3)
        XCTAssertTrue(week.ruleNoteLines[2].hasPrefix("Achilles (left) 5.5/10 on 2030-10-23"))
        XCTAssertEqual(week.sessionsLine, "1 done · 1 missed of 6")
        let rows = try days(week)
        XCTAssertEqual(rows.count, 7)
        XCTAssertEqual(rows.map(\.title).first, "Mon 21")
        XCTAssertEqual(rows.filter(\.isToday).map(\.date), [D.asOf])
        XCTAssertEqual(rows[0].sessions.first?.status, .missed)
        XCTAssertEqual(rows[0].sessions.first?.statusText, "Missed")
        // Sunday's walk was moved to Friday by a plan command.
        XCTAssertNil(rows[4].restText)
        XCTAssertEqual(rows[4].sessions.map(\.id), ["2030-w43-sun-pm"])
        XCTAssertEqual(rows[6].restText, "Rest day")
        XCTAssertEqual(rows[3].sessions.first?.badgeText, "Test")
        XCTAssertEqual(week.previous, D.week("2030-W42"))
        XCTAssertEqual(week.next, D.week("2030-W44"))
    }

    func testWeekOfTheAdjacentPhaseNamesItsOwnPhase() throws {
        let week = try builder().week(D.week("2030-W41"))
        XCTAssertEqual(week.phaseTitle, "Test Prelude 2030")
        XCTAssertEqual(week.kindText, "Transition")
        XCTAssertEqual(week.runLine, "Run 22.6 of 30 km")
        XCTAssertEqual(try builder(.czech).week(D.week("2030-W41")).phaseTitle, "Testovací úvod 2030")
    }

    func testUnplannedRowsAndTheDoneOption() throws {
        let rows = try days(try builder().week(D.week("2030-W42")))
        let tuesday = rows[1]
        XCTAssertEqual(tuesday.sessions.first?.doneText, "Done · R")
        XCTAssertEqual(tuesday.unplanned.map(\.text), ["Unplanned · Ride · 8.4 km · 24 min"])
        XCTAssertEqual(tuesday.sessions.first?.status, .done)
        XCTAssertEqual(rows[4].sessions.first?.doneText, "Done · A")
        let anonymous = try days(try builder(data: try Fixtures.exampleWithAnonymousFridayRun()).week(D.week("2030-W42")))
        XCTAssertEqual(anonymous[4].sessions.first?.doneText, "Done")
        XCTAssertEqual(rows[5].sessions.first?.fuelLine, "Fuel: 60 g carbs/h")
        XCTAssertEqual(rows[6].unplanned.first?.text, "Unplanned · Swim · 1.2 km · 35 min")
        XCTAssertEqual(try builder().week(D.week("2030-W42")).noteText, "Plan starts")
    }

    func testFutureWeekShowsTargetsOnly() throws {
        let week = try builder().week(D.week("2030-W44"))
        XCTAssertEqual(week.runLine, "Run target 40 km")
        XCTAssertEqual(week.sessionsLine, "Sessions planned: 5")
        XCTAssertEqual(week.ruleNoteLines, [])
        XCTAssertEqual(week.statusText, "Proposed")
        XCTAssertEqual(week.kindText, "Race")
        XCTAssertEqual(week.noteText, "Race week")
        let rows = try days(week)
        XCTAssertEqual(rows[4].fuelLine, "Carb load: 560 g carbs (8 g/kg)")
        XCTAssertEqual(rows[6].raceLines, ["Race day: Test Valley 30K"])
    }

    func testPagingIntoTheOutline() throws {
        let week = try builder().week(D.week("2030-W45"))
        XCTAssertEqual(week.kindText, "Recovery")
        XCTAssertEqual(week.runLine, "Run target 45 km")
        XCTAssertEqual(week.phaseTitle, "Test Base 2030")
        XCTAssertEqual(week.content, .outlineOnly("Sessions for this week aren't written yet"))
    }

    func testWeeksOutsideEveryPhaseAndTheEdgeOfTheSeason() throws {
        let week = try builder().week(D.week("2031-W10"))
        guard case .empty(let state) = week.content else { return XCTFail("\(week.content)") }
        XCTAssertEqual(state.title, "No plan for this week")
        // The season runs to 2031-08-31 (2031-W35): no next page beyond it.
        XCTAssertNil(try builder().week(D.week("2031-W35")).next)
        XCTAssertNil(try builder().week(D.week("2030-W36")).previous)
    }

    func testMinimalWeekHasNoActivePlan() throws {
        let week = try builder(data: try Fixtures.minimal()).week(D.week("2030-W43"))
        guard case .empty(let state) = week.content else { return XCTFail("\(week.content)") }
        XCTAssertEqual(state.title, "No active plan")
    }

    // MARK: Month

    func testMonthGrid() throws {
        let month = try builder().month(year: 2030, month: 10)
        XCTAssertEqual(month.title, "October 2030")
        XCTAssertEqual(month.weekdayHeaders.first, "Mon")
        XCTAssertEqual(month.rows.count, 6)
        XCTAssertEqual(month.rows.flatMap(\.cells).count, 42)
        XCTAssertEqual(month.rows.map(\.label), ["W40", "W41", "W42", "W43", "W44", "W45"])
        XCTAssertEqual(month.rows.map(\.targetText), [nil, "30 km", "55 km", "55 km", "40 km", "45 km"])
        XCTAssertEqual(month.rows[0].cells[0].date, D.date("2030-09-30"))
        XCTAssertFalse(month.rows[0].cells[0].isInMonth)
        XCTAssertNil(month.emptyState)

        let cells = Dictionary(uniqueKeysWithValues: month.rows.flatMap(\.cells).map { ($0.date, $0) })
        XCTAssertEqual(cells[D.date("2030-10-21")]?.glyphs.map(\.style), [.missed])
        XCTAssertEqual(cells[D.date("2030-10-22")]?.glyphs.map(\.style), [.done])
        XCTAssertEqual(cells[D.date("2030-10-15")]?.glyphs.map(\.style), [.done, .unplanned])
        XCTAssertEqual(cells[D.date("2030-10-17")]?.glyphs.map(\.style), [.done, .done, .unplanned])
        XCTAssertEqual(cells[D.date("2030-10-24")]?.glyphs.map(\.style), [.planned])
        XCTAssertEqual(cells[D.date("2030-10-23")]?.isToday, true)
        XCTAssertEqual(cells[D.date("2030-11-03")]?.raceNames, ["Test Valley 30K"])
        XCTAssertEqual(cells[D.date("2030-11-03")]?.isInMonth, false)
        XCTAssertEqual(cells[D.date("2030-10-21")]?.accessibilityLabel, "Mon 21 Oct. Gym A, Missed. Morning check: Green")
        XCTAssertEqual(cells[D.date("2030-10-21")]?.lightName, "Green")
        XCTAssertEqual(cells[D.date("2030-10-28")]?.glyphs.map(\.style), [.skipped])
        XCTAssertEqual(month.previous.month, 9)
        XCTAssertEqual(month.next.month, 11)
    }

    func testGlyphOverflow() throws {
        let data = try Fixtures.mutatedExample { object in
            try Fixtures.mutateDay(&object, week: 1, day: 3) { day in
                let extra: [[String: Any]] = [
                    ["note": "a", "sport": "Ride", "group": "ride", "start": "19:00", "km": 5, "min": 15],
                    ["note": "b", "sport": "Walk", "group": "walk", "start": "20:00", "km": 2, "min": 25],
                ]
                day["unplanned"] = ((day["unplanned"] as? [[String: Any]]) ?? []) + extra
            }
        }
        let month = try builder(data: data).month(year: 2030, month: 10)
        let cell = try XCTUnwrap(month.rows.flatMap(\.cells).first { $0.date == D.date("2030-10-17") })
        XCTAssertEqual(cell.glyphs.count, 3)
        XCTAssertEqual(cell.overflow, 2)
    }

    func testJanuaryAcrossTheYearBoundary() throws {
        let month = try builder().month(year: 2027, month: 1)
        XCTAssertEqual(month.rows[0].week, D.week("2026-W53"))
        XCTAssertEqual(month.rows[0].label, "W53")
        XCTAssertEqual(month.rows[0].cells[0].date, D.date("2026-12-28"))
        XCTAssertEqual(month.previous.year, 2026)
        XCTAssertEqual(month.previous.month, 12)
        XCTAssertEqual(try builder(.czech).month(year: 2027, month: 1).rows[0].label, "T53")
    }

    // MARK: Session detail

    func testDetailOpensOnTheTappedOptionElseG() throws {
        let plan = try builder()
        XCTAssertEqual(plan.sessionDetail(id: "2030-w43-wed-am", option: "R")?.initialOptionIndex, 2)
        // Untapped: the morning's amber check-in picks A.
        XCTAssertEqual(plan.sessionDetail(id: "2030-w43-wed-am")?.initialOptionIndex, 1)
        // No light, nothing done: G.
        XCTAssertEqual(plan.sessionDetail(id: "2030-w44-tue-am")?.initialOptionIndex, 0)
        XCTAssertNil(plan.sessionDetail(id: "no-such-session"))
    }

    func testDetailOfARedDay() throws {
        let detail = try XCTUnwrap(try builder().sessionDetail(id: "2030-w42-tue-am"))
        XCTAssertEqual(detail.initialOptionIndex, 2)
        XCTAssertEqual(detail.dateLine, "Tue 15 Oct · Morning")
        XCTAssertEqual(detail.statusText, "Done")
        XCTAssertEqual(detail.whyLines, ["Traffic-light day", "Aerobic volume below the first threshold"])
        XCTAssertEqual(detail.options.map(\.code), ["G", "A", "R"])
        XCTAssertEqual(detail.options[0].steps, ["10 km · Z1 · ≤140 bpm"])
        XCTAssertEqual(detail.options[1].steps, ["6 km · Z1 · 6:15 /km · flat route only"])
        XCTAssertEqual(detail.options[2].steps, ["Warm-up 5 min", "35 min · Z1", "Cool-down 5 min", "Hold 3 × 45 s · each side · after the ride"])
        XCTAssertEqual(detail.options[2].targetLines, ["45 min", "≤128 bpm · Z1"])
        let done = try XCTUnwrap(detail.done)
        XCTAssertEqual(done.optionText, "Option R · Alternative")
        XCTAssertEqual(done.activityLine, "Ride · 05:10 · 21.3 km · 46 min")
        XCTAssertEqual(done.recognisedText, "Inferred from the sport")
        XCTAssertNil(detail.originText)
    }

    func testDoneOptionFromTheActivityName() throws {
        let detail = try XCTUnwrap(try builder().sessionDetail(id: "2030-w42-fri-am"))
        XCTAssertEqual(detail.initialOptionIndex, 1)
        XCTAssertEqual(detail.done?.optionText, "Option A · Easier")
        XCTAssertEqual(detail.done?.recognisedText, "Recognised from the activity's name")
        XCTAssertEqual(try builder(.czech).sessionDetail(id: "2030-w42-fri-am")?.done?.recognisedText, "Rozpoznáno podle názvu aktivity")
    }

    func testDoneOptionNotIdentified() throws {
        let detail = try XCTUnwrap(try builder(data: try Fixtures.exampleWithAnonymousFridayRun()).sessionDetail(id: "2030-w42-fri-am"))
        XCTAssertEqual(detail.done?.optionText, "Option not identified")
        XCTAssertEqual(detail.done?.recognisedText, "Matched by date and sport")
        XCTAssertEqual(detail.initialOptionIndex, 0)
    }

    func testStepsNotPublished() throws {
        let detail = try XCTUnwrap(try builder().sessionDetail(id: "2030-w42-thu-pm"))
        XCTAssertTrue(detail.options.isEmpty)
        XCTAssertEqual(detail.single?.targetLines, ["5 km"])
        XCTAssertEqual(detail.single?.steps, [])
        XCTAssertEqual(detail.single?.stepsPlaceholder, "Steps not published")
    }

    func testTestResultAgainstHistory() throws {
        let detail = try XCTUnwrap(try builder().sessionDetail(id: "2030-w42-wed-pm"))
        XCTAssertEqual(detail.badgeText, "Test")
        let test = try XCTUnwrap(detail.test)
        XCTAssertNil(test.placeholder)
        XCTAssertEqual(test.rows.map(\.label), ["Left", "Right"])
        XCTAssertEqual(test.rows.map(\.valueText), ["22 reps", "27 reps"])
        XCTAssertEqual(test.rows.map(\.previousText), ["Previous 18 reps", "Previous 24 reps"])
        XCTAssertEqual(test.rows.map(\.trend), [.improved, .improved])
        XCTAssertEqual(test.rows.map(\.trendText), ["Improved", "Improved"])
        XCTAssertEqual(detail.done?.recognisedText, "Recorded as a test result")
        XCTAssertNil(detail.done?.optionText)
        XCTAssertEqual(detail.single?.steps, ["Single-leg calf raise · 1 × max · each side"])

        let czech = try XCTUnwrap(try builder(.czech).sessionDetail(id: "2030-w42-wed-pm")?.test)
        XCTAssertEqual(czech.rows.map(\.label), ["Levá", "Pravá"])
        XCTAssertEqual(czech.rows.first?.previousText, "Minule 18 reps")
    }

    func testTestBeforeItIsDone() throws {
        let test = try XCTUnwrap(try builder().sessionDetail(id: "2030-w43-thu-pm")?.test)
        XCTAssertEqual(test.placeholder, "No result yet")
        XCTAssertTrue(test.rows.isEmpty)
    }

    func testLowerIsBetterTrend() throws {
        let data = try Fixtures.mutatedExample { object in
            try Fixtures.mutateSession(&object, week: 2, day: 3, session: 0) { session in
                let test: [String: Any] = ["workout": "time-trial-3k", "result": ["time_s": 700], "note": NSNull(), "ref": NSNull()]
                session["test"] = test
            }
            var tests = try XCTUnwrap(object["tests"] as? [[String: Any]])
            let entry: [String: Any] = ["date": "2030-09-20", "sessionId": "x", "values": ["time_s": 720], "note": NSNull()]
            tests[1]["history"] = [entry]
            object["tests"] = tests
        }
        let row = try XCTUnwrap(try builder(data: data).sessionDetail(id: "2030-w43-thu-pm")?.test?.rows.first)
        XCTAssertEqual(row.label, "Time")
        XCTAssertEqual(row.valueText, "700 s")
        XCTAssertEqual(row.trend, .improved)
    }

    func testRaceSessionDetail() throws {
        let detail = try XCTUnwrap(try builder().sessionDetail(id: "2030-w44-sun-am"))
        XCTAssertEqual(detail.badgeText, "Race")
        XCTAssertEqual(detail.raceLine, "Race day: Test Valley 30K · Sun 3 Nov")
        // The session's own fuel, plus its day's carb load if the plan put
        // it on a carb-load day (a plan command moved it to Saturday in the
        // current example; the vault is about to refuse that for races).
        let raceDate = try Fixtures.exampleDate(ofSession: "2030-w44-sun-am")
        if raceDate == D.date("2030-11-03") {
            XCTAssertEqual(detail.fuelLines, ["Fuel: 70 g carbs/h"])
            XCTAssertNil(detail.originText)
        } else {
            XCTAssertEqual(detail.fuelLines, ["Fuel: 70 g carbs/h", "Carb load: 700 g carbs (10 g/kg)"])
            XCTAssertEqual(detail.originText, "Moved from Sun 3 Nov")
        }
        let swapped = try XCTUnwrap(try builder().sessionDetail(id: "2030-w44-fri-am"))
        XCTAssertEqual(swapped.fuelLines, [])
        XCTAssertEqual(swapped.originText, "Swapped from Fri 1 Nov")
        XCTAssertEqual(try builder(.czech).sessionDetail(id: "2030-w44-fri-am")?.originText, "Prohozeno z pá 1. 11.")
        let ruled = try XCTUnwrap(try builder().sessionDetail(id: "2030-w44-wed-am"))
        XCTAssertEqual(ruled.originText, "Changed by a rule")
        XCTAssertEqual(ruled.whyLines.last, "Two amber mornings in a row (2030-10-22, 2030-10-23): only the ride option (R) stays for this quality session.")
    }

    func testOriginAndRuleNotesOncePublished() throws {
        let data = try Fixtures.mutatedExample { object in
            try Fixtures.mutateSession(&object, week: 2, day: 2, session: 0) { session in
                session["origin"] = ["movedFrom": "2030-10-21"]
                session["ruleNotes"] = [["en": "Two ambers make the next quality session a ride", "cz": "Dvě oranžové"]]
                if var options = session["options"] as? [[String: Any]] {
                    options[0]["watch"] = ["name": "Easy 10", "state": "scheduled"]
                    session["options"] = options
                }
            }
        }
        let detail = try XCTUnwrap(try builder(data: data).sessionDetail(id: "2030-w43-wed-am"))
        XCTAssertEqual(detail.originText, "Moved from Mon 21 Oct")
        XCTAssertEqual(detail.whyLines.last, "Two ambers make the next quality session a ride")
        XCTAssertEqual(detail.options[0].watchLine, "On Garmin calendar")
        XCTAssertEqual(detail.options[2].watchLine, "Couldn't send to Garmin calendar")
    }

    // MARK: Habit ladder

    func testHabitLadder() throws {
        let ladder = try builder().habitLadder()
        XCTAssertEqual(ladder.gateText, "Gate: 80 % · 14-day window")
        XCTAssertNil(ladder.emptyText)
        XCTAssertEqual(ladder.rows.map(\.id), ["holds", "gym", "stretch", "quality", "pool", "stretch-plus"])
        XCTAssertEqual(ladder.rows.map(\.stateText), ["Active", "Active", "Next", "Later", "Later", "Later"])
        XCTAssertEqual(ladder.rows[0].why, "Tendon load")
        XCTAssertEqual(ladder.rows[1].dateText, "Started 14 Oct")
        XCTAssertEqual(ladder.rows[1].adherence, "2 of 3 · 66 % · over 9 recorded days")
        XCTAssertNil(ladder.rows[1].gateMetText)
        XCTAssertEqual(ladder.rows[2].adherence, "not recorded yet")
        XCTAssertEqual(ladder.rows[2].dateText, "Earliest start 28 Oct")
        XCTAssertEqual(ladder.rows[2].schedule, "After sessions: easy")
        XCTAssertEqual(ladder.rows[3].schedule, "Once a week")
        XCTAssertEqual(ladder.rows[4].schedule, "every 2 weeks · Sat")
    }

    func testGateMet() throws {
        let data = try Fixtures.mutatedExample { object in
            var habits = try XCTUnwrap(object["habits"] as? [String: Any])
            var ladder = try XCTUnwrap(habits["ladder"] as? [[String: Any]])
            ladder[1]["window14"] = ["done": 25, "expected": 28, "pct": 89, "recordedDays": 14]
            ladder[1]["gateMet"] = true
            habits["ladder"] = ladder
            object["habits"] = habits
        }
        let row = try builder(data: data).habitLadder().rows[1]
        XCTAssertEqual(row.adherence, "25 of 28 · 89 %")
        XCTAssertEqual(row.gateMetText, "Gate met: the next habit can start at your Sunday review")
    }

    func testMinimalLadderIsEmpty() throws {
        let ladder = try builder(data: try Fixtures.minimal()).habitLadder()
        XCTAssertTrue(ladder.rows.isEmpty)
        XCTAssertEqual(ladder.emptyText, "No habits in this plan")
    }
}
