// TrainingStatsTests.swift
//
// Golden tests of the statistics models on the vault's example fixture
// (add-training-stats, tasks 2.x): adherence per week and per phase (and
// that the counts agree with the vault's own `actual`), weeks outside the
// file's window listed rather than counted, the G/A/R split with "option
// not identified", volume vs target through `PhaseRamp`, test histories
// judged in their direction and the left/right asymmetry. Today is the
// fixture's `asOf`, Wednesday 23 October 2030.
//
// Czech assertions compare only our own table strings and numbers, never
// CLDR month abbreviations or list spacing.

import XCTest
@testable import TrainingCore

final class TrainingStatsTests: XCTestCase {
    private func builder(_ language: TrainingLanguage = .english, data: Data? = nil, today: LocalDate = D.asOf) throws -> PlanBuilder {
        let bytes = try data ?? Fixtures.example()
        guard case .success(let decoded) = ProjectionDecoder.decode(bytes) else {
            XCTFail("fixture did not decode")
            throw ProjectionRejection.invalid(reason: "test")
        }
        return PlanBuilder(source: .loaded(TrainingSnapshot(projection: decoded.projection)), language: language, today: today)
    }

    // MARK: Adherence

    func testPhaseAdherence() throws {
        let plan = try builder()
        XCTAssertEqual(plan.defaultStatsScope(), .phase("test-base-2030"))
        let stats = plan.stats(scope: .phase("test-base-2030"))
        XCTAssertNil(stats.emptyState)
        XCTAssertEqual(stats.scopeTitle, "Test Base 2030")
        XCTAssertEqual(stats.rangeText, "14 Oct 2030 – 31 Jan 2031")

        let adherence = try XCTUnwrap(stats.adherence)
        XCTAssertEqual(adherence.weeks.map(\.title), ["W42", "W43", "W44"])
        // W44's Monday gym was skipped by a plan command: due, not done
        // (the stats design's rule), even before the week starts.
        XCTAssertEqual(adherence.weeks.map(\.countsText), [
            "8 done · 0 missed · 0 planned",
            "1 done · 1 missed · 4 planned",
            "0 done · 0 missed · 4 planned · 1 skipped"
        ])
        XCTAssertEqual(adherence.weeks.map(\.adherenceText), ["100 %", "50 %", "0 %"])
        XCTAssertEqual(adherence.weeks.map(\.isCurrent), [false, true, false])
        XCTAssertEqual(adherence.totals.done, 9)
        XCTAssertEqual(adherence.totals.missed, 1)
        XCTAssertEqual(adherence.totals.skipped, 1)
        XCTAssertEqual(adherence.totals.planned, 8)
        // 9 of 11 due.
        XCTAssertEqual(adherence.summary, "Done 82 % of the sessions due so far")
        XCTAssertNil(adherence.outsideText)
        XCTAssertEqual(adherence.phases.map(\.title), ["Test Base 2030"])
        XCTAssertEqual(adherence.legend.missed, "Missed")
    }

    func testSeasonAdherenceListsWeeksOutsideTheWindow() throws {
        let stats = try builder().stats(scope: .season)
        XCTAssertEqual(stats.scopeTitle, "Whole season")
        let adherence = try XCTUnwrap(stats.adherence)
        XCTAssertEqual(adherence.weeks.map(\.title), ["W41", "W42", "W43", "W44"])
        XCTAssertEqual(adherence.phases.map(\.title), ["Test Prelude 2030", "Test Base 2030"])
        XCTAssertEqual(adherence.phases.map(\.countsText), ["2 done · 0 missed · 0 planned", "9 done · 1 missed · 8 planned · 1 skipped"])
        // 11 of 13 due.
        XCTAssertEqual(adherence.summary, "Done 85 % of the sessions due so far")
        // The season started in W36; W36-W40 are not in the file: listed, not zero.
        XCTAssertEqual(adherence.outsideText, "Not in the app's window: W36, W37, W38, W39, W40")

        let czech = try XCTUnwrap(try builder(.czech).stats(scope: .season).adherence)
        XCTAssertEqual(czech.summary, "Hotovo 85 % tréninků, které už byly na řadě")
        XCTAssertEqual(czech.weeks[0].countsText, "2 hotovo · 0 vynecháno · 0 naplánováno")
        XCTAssertEqual(czech.outsideText, "Mimo okno aplikace: T36, T37, T38, T39, T40")
    }

    /// The counts are the vault's statuses tallied, so they must agree with
    /// the vault's own `actual` for every week it has counted.
    func testCountsAgreeWithTheVaultsActual() throws {
        let snapshot = try Fixtures.exampleSnapshot()
        let stats = try builder().stats(scope: .season)
        let rows = try XCTUnwrap(stats.adherence).weeks
        for week in try XCTUnwrap(snapshot.plan).weeks {
            guard let actual = week.actual, let row = rows.first(where: { $0.id == week.week.description }) else { continue }
            XCTAssertEqual(row.counts.done, actual.sessionsDone, "\(week.week)")
            XCTAssertEqual(row.counts.missed, actual.sessionsMissed, "\(week.week)")
        }
    }

    func testSkippedSessionsAreDueButNotDone() throws {
        // `skipped` is reserved in v1; if the vault ever writes it, it counts as due.
        let data = try Fixtures.mutatedExample { object in
            try Fixtures.mutateSession(&object, week: 2, day: 0, session: 0) { session in session["status"] = "skipped" }
        }
        let week = try XCTUnwrap(try builder(data: data).stats(scope: .phase("test-base-2030")).adherence?.weeks[1])
        XCTAssertEqual(week.counts.skipped, 1)
        XCTAssertEqual(week.countsText, "1 done · 0 missed · 4 planned · 1 skipped")
        XCTAssertEqual(week.adherenceText, "50 %")
        XCTAssertNil(StatusCounts().adherence)
    }

    // MARK: G / A / R

    func testOptionSplit() throws {
        let split = try XCTUnwrap(try builder().stats(scope: .phase("test-base-2030")).options)
        XCTAssertEqual(split.total, 3)
        XCTAssertNil(split.emptyText)
        XCTAssertEqual(split.shares.map(\.code), ["G", "A", "R", nil])
        XCTAssertEqual(split.shares.map(\.count), [0, 1, 1, 1])
        XCTAssertEqual(split.shares.map(\.label), ["Planned session", "Easier", "Alternative", "Option not identified"])
        XCTAssertEqual(split.shares[1].text, "1 session · 33 %")
        XCTAssertEqual(split.shares[0].text, "0 sessions · 0 %")
        XCTAssertEqual(split.shares.map(\.fraction).reduce(0, +), 1, accuracy: 1e-9)

        let czech = try XCTUnwrap(try builder(.czech).stats(scope: .phase("test-base-2030")).options)
        XCTAssertEqual(czech.shares[1].text, "1 trénink · 33 %")
        XCTAssertEqual(czech.shares[3].label, "Možnost nerozpoznána")

        let prelude = try XCTUnwrap(try builder().stats(scope: .phase("test-prelude-2030")).options)
        XCTAssertEqual(prelude.total, 0)
        XCTAssertEqual(prelude.emptyText, "No traffic-light session done yet")
    }

    // MARK: Volume

    func testVolumeVsTarget() throws {
        let volume = try XCTUnwrap(try builder().stats(scope: .phase("test-base-2030")).volume)
        XCTAssertEqual(volume.rows.map(\.label), ["W42", "W43", "W44", "W45", "W46"])
        // W43's target is the red-held 55 km (the vault's rule edit).
        XCTAssertEqual(volume.rows.map(\.valueText), ["60.1 of 55 km", "10.1 of 55 km", "40 km", "45 km", "–"])
        XCTAssertEqual(volume.rows.map(\.deltaText), ["+5.1 km (+9 %)", "−44.9 km (−82 %)", nil, nil, nil])
        XCTAssertEqual(volume.summaryLines, [
            "Planned 195 km in total",
            "Ran 70.2 of 110 km planned",
            "1 of 2 weeks within 10 % of target",
            "Average 35.1 km a week"
        ])
        // The Phase screen and the statistics read the same ramp.
        let phase = try XCTUnwrap(try builder().phaseDetail(id: "test-base-2030"))
        XCTAssertEqual(volume.rows.map(\.targetKm), phase.weeks.map(\.targetKm))
        XCTAssertEqual(volume.rows.map(\.actualKm), phase.weeks.map(\.actualKm))

        let season = try XCTUnwrap(try builder().stats(scope: .season).volume)
        XCTAssertEqual(season.rows.first?.label, "W41")
        XCTAssertEqual(season.rows.first?.valueText, "22.6 of 30 km")
        XCTAssertEqual(season.rows.count, 6)

        let czech = try XCTUnwrap(try builder(.czech).stats(scope: .phase("test-base-2030")).volume)
        XCTAssertEqual(czech.rows[0].valueText, "60,1 z 55 km")
        XCTAssertEqual(czech.rows[0].deltaText, "+5,1 km (+9 %)")
    }

    // MARK: Tests

    func testTestHistoryAndAsymmetry() throws {
        let tests = try builder().stats(scope: .season).tests
        XCTAssertEqual(tests.map(\.workout), ["calf-raise-test", "time-trial-3k"])
        let calf = tests[0]
        XCTAssertEqual(calf.title, "Single-leg calf raise to failure")
        XCTAssertNil(calf.emptyText)
        XCTAssertEqual(calf.measures.map(\.label), ["Left", "Right"])
        XCTAssertEqual(calf.measures.map(\.latestText), ["22 reps", "27 reps"])
        XCTAssertEqual(calf.measures.map(\.changeText), ["18 → 22 reps", "24 → 27 reps"])
        XCTAssertEqual(calf.measures.map(\.verdict), [.improved, .improved])
        XCTAssertEqual(calf.measures[0].verdictText, "Improved")
        XCTAssertEqual(calf.measures[0].points.map(\.value), [18, 22])
        XCTAssertEqual(calf.measures[0].points.last?.dateText, "16 Oct")

        let pair = try XCTUnwrap(calf.pairs.first)
        XCTAssertEqual(pair.stem, "reps")
        XCTAssertEqual(pair.leftLabel, "Left")
        XCTAssertEqual(pair.rightLabel, "Right")
        XCTAssertEqual(pair.history.map(\.asymmetry), [6.0 / 24.0, 5.0 / 27.0])
        XCTAssertEqual(pair.history.map(\.text), ["L 18 · R 24 · 25 %", "L 22 · R 27 · 19 %"])
        XCTAssertEqual(pair.latestText, "Asymmetry 19 %")

        let trial = tests[1]
        XCTAssertEqual(trial.emptyText, "No results yet")
        XCTAssertTrue(trial.pairs.isEmpty)
        XCTAssertNil(trial.measures.first?.latestText)

        let czech = try XCTUnwrap(try builder(.czech).stats(scope: .season).tests.first?.pairs.first)
        XCTAssertEqual(czech.latestText, "Asymetrie 19 %")
        XCTAssertEqual(czech.history.last?.text, "L 22 · P 27 · 19 %")
    }

    func testAsymmetryArithmetic() {
        XCTAssertEqual(TestAsymmetry.asymmetry(left: 22, right: 27), 5.0 / 27.0, accuracy: 1e-12)
        XCTAssertEqual(TestAsymmetry.asymmetry(left: 27, right: 22), 5.0 / 27.0, accuracy: 1e-12)
        XCTAssertEqual(TestAsymmetry.asymmetry(left: 0, right: 0), 0)
        XCTAssertEqual(TestVerdict.judge(first: 612, last: 600, better: OpenEnum<MeasureDirection>(.lower)), .improved)
        XCTAssertEqual(TestVerdict.judge(first: 600, last: 600, better: OpenEnum<MeasureDirection>(.higher)), .unchanged)
        XCTAssertNil(TestVerdict.judge(first: 1, last: 2, better: nil))
    }

    // MARK: States

    func testStatesWithoutAPlan() throws {
        let minimal = try builder(data: try Fixtures.minimal()).stats(scope: .season)
        XCTAssertEqual(minimal.emptyState?.kind, .noActivePlan)
        XCTAssertNil(minimal.adherence)
        let waiting = PlanBuilder(source: .notGenerated, language: .english, today: D.asOf).stats(scope: .season)
        XCTAssertEqual(waiting.emptyState?.kind, .notGenerated)
        let unknownPhase = try builder().stats(scope: .phase("no-such-phase"))
        XCTAssertEqual(unknownPhase.emptyState?.kind, .noActivePlan)
    }
}
