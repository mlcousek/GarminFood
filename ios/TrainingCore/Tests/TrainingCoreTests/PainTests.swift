// PainTests.swift
//
// The morning pain score (add-checkin-pain-score): sites (an unknown one
// reads as `other`), the tolerant `day.pains` decoding, the vault's
// replace/keep rule in the phone's overlay and over the projection, the
// draft (rounding, add/remove, notes, default sites), the pain step on
// Today's check-in row, the card's pain line and the Plan day tags -- in
// English and Czech ("5,5/10": a plain comma, no grouping, so no CLDR
// no-break space can appear in these numbers).
//
// On the vault's example fixture: 2030-10-23 (asOf) has the left Achilles
// at 5.5 with a note and the right knee at 1; every other day is `null`.
// Everything is synthetic.

import XCTest
@testable import TrainingCore

final class PainTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_918_951_651)
    private let tuesday = D.date("2030-10-22")

    private func logged(_ payload: HubEventPayload, seq: Int, segment: UUID? = nil) -> LoggedEvent {
        LoggedEvent(
            event: HubEvent(id: "id-\(seq)", deviceId: "ios-0000beef", seq: seq, at: "t", payload: payload),
            recordedAt: t0.addingTimeInterval(Double(seq)),
            segmentID: segment
        )
    }

    private func checkIn(_ date: LocalDate = D.asOf, _ light: MorningLight = .amberLight, pains: [PainEntry]?) -> HubEventPayload {
        .morningCheckIn(MorningCheckInPayload(date: date, light: light, sessionId: nil, pains: pains))
    }

    private func projection(_ data: Data? = nil) throws -> Projection {
        guard let data else { return try Fixtures.exampleProjection().projection }
        guard case .success(let decoded) = ProjectionDecoder.decode(data) else {
            XCTFail("fixture did not decode")
            throw ProjectionRejection.invalid(reason: "test")
        }
        return decoded.projection
    }

    private func snapshot(_ events: [LoggedEvent] = [], unsent: Set<UUID> = [], enabled: Bool = true, data: Data? = nil) throws -> TrainingSnapshot {
        TrainingSnapshot(
            projection: try projection(data),
            checkIns: CheckInOverlay.fold(events, unsentSegments: unsent),
            capabilities: .checkIns(enabled: enabled)
        )
    }

    private func today(_ snapshot: TrainingSnapshot, _ language: TrainingLanguage = .english) -> TodayTrainingBuilder {
        TodayTrainingBuilder(source: .loaded(snapshot), language: language)
    }

    /// The example with `pains` of `date` in W43 (index 2) replaced.
    private func example(pains: Any, weekday: Int = 2) throws -> Data {
        try Fixtures.mutatedExample { object in
            try Fixtures.mutateDay(&object, week: 2, day: weekday) { day in
                day["pains"] = pains
            }
        }
    }

    // MARK: Sites and decoding

    func testUnknownSitesReadAsOther() {
        XCTAssertEqual(PainSite(wire: "achilles-left"), .achillesLeft)
        XCTAssertEqual(PainSite(wire: "knee-right"), .kneeRight)
        XCTAssertEqual(PainSite(wire: "other"), .other)
        XCTAssertEqual(PainSite(wire: "hip-left"), .other)
        XCTAssertEqual(PainSite(wire: ""), .other)
        XCTAssertEqual(PainSite.allCases.map(\.rawValue), ["achilles-left", "achilles-right", "knee-left", "knee-right", "other"])
    }

    func testTheExampleDaysDecodeTheirPains() throws {
        let plan = try XCTUnwrap(try projection().plan)
        let wednesday = try XCTUnwrap(plan.weeks[2].day(D.asOf))
        XCTAssertEqual(wednesday.pains, [
            PainEntry(site: .achillesLeft, score: 5.5, note: "Stiff first steps, eases after 10 min"),
            PainEntry(site: .kneeRight, score: 1)
        ])
        let others = plan.weeks.flatMap(\.days).filter { $0.date != D.asOf }
        XCTAssertEqual(others.count, 27)
        XCTAssertTrue(others.allSatisfy { $0.pains == nil }, "null = not asked")
    }

    func testDayPainsDecodeTolerantly() throws {
        let messy: [[String: Any]] = [
            ["site": "hip-left", "score": 2],
            ["site": "knee-left"],
            ["site": "knee-right", "score": "high"],
            ["site": "achilles-left", "score": 3, "note": 5],
            ["score": 0.5, "note": NSNull()]
        ]
        let day = try XCTUnwrap(try projection(try example(pains: messy)).plan?.weeks[2].day(D.asOf))
        XCTAssertEqual(day.pains, [
            PainEntry(site: .other, score: 2),
            PainEntry(site: .achillesLeft, score: 3),
            PainEntry(site: .other, score: 0.5)
        ], "entries without a numeric score are dropped")

        XCTAssertEqual(try projection(try example(pains: [Any]())).plan?.weeks[2].day(D.asOf)?.pains, [], "asked, nothing hurts")
        XCTAssertNil(try projection(try example(pains: "sore")).plan?.weeks[2].day(D.asOf)?.pains, "not a list = not asked")
        let absent = try Fixtures.mutatedExample { object in
            try Fixtures.mutateDay(&object, week: 2, day: 2) { day in day.removeValue(forKey: "pains") }
        }
        XCTAssertNil(try projection(absent).plan?.weeks[2].day(D.asOf)?.pains)
    }

    // MARK: Replace / keep (design D3)

    func testALaterCheckInWithoutPainsKeepsTheAnswer() {
        let overlay = CheckInOverlay.fold([
            logged(checkIn(pains: [PainEntry(site: .achillesLeft, score: 3)]), seq: 1),
            logged(checkIn(D.asOf, .greenLight, pains: nil), seq: 2)
        ], unsentSegments: [])
        XCTAssertEqual(overlay.light(on: D.asOf)?.value, .greenLight, "the light is the latest")
        XCTAssertEqual(overlay.pains(on: D.asOf)?.value, [PainEntry(site: .achillesLeft, score: 3)], "the pain is kept")
    }

    func testALaterCheckInWithPainsReplacesTheAnswer() {
        let events = [
            logged(checkIn(pains: [PainEntry(site: .achillesLeft, score: 3), PainEntry(site: .kneeLeft, score: 1)]), seq: 1),
            logged(checkIn(pains: [PainEntry(site: .achillesLeft, score: 2)]), seq: 2)
        ]
        XCTAssertEqual(CheckInOverlay.fold(events, unsentSegments: []).pains(on: D.asOf)?.value, [PainEntry(site: .achillesLeft, score: 2)])
        let emptied = CheckInOverlay.fold(events + [logged(checkIn(pains: []), seq: 3)], unsentSegments: [])
        XCTAssertEqual(emptied.pains(on: D.asOf)?.value, [], "[] replaces too: nothing hurts")
        XCTAssertNil(emptied.pains(on: tuesday), "another day is untouched")
    }

    func testOnlyLightsNeverMakeAPainAnswer() {
        let overlay = CheckInOverlay.fold([logged(checkIn(pains: nil), seq: 1)], unsentSegments: [])
        XCTAssertNil(overlay.pains(on: D.asOf))
        XCTAssertFalse(overlay.isEmpty)
    }

    func testThePhonesAnswerWinsOverTheProjection() throws {
        let replaced = try snapshot([logged(checkIn(pains: [PainEntry(site: .achillesLeft, score: 0)]), seq: 1)])
        XCTAssertEqual(replaced.plan?.day(D.asOf)?.pains, [PainEntry(site: .achillesLeft, score: 0)])

        let lightOnly = try snapshot([logged(checkIn(D.asOf, .greenLight, pains: nil), seq: 1)])
        XCTAssertEqual(lightOnly.plan?.day(D.asOf)?.light?.known, .greenLight)
        XCTAssertEqual(lightOnly.plan?.day(D.asOf)?.pains?.map(\.score), [5.5, 1], "a light-only check-in keeps the vault's answer")

        let tuesdayAnswer = try snapshot([logged(checkIn(tuesday, pains: []), seq: 1)])
        XCTAssertEqual(tuesdayAnswer.plan?.day(tuesday)?.pains, [])
    }

    // MARK: Draft

    func testDraftRoundsAndClamps() {
        XCTAssertEqual(PainDraft.rounded(4.3), 4.5)
        XCTAssertEqual(PainDraft.rounded(4.2), 4)
        XCTAssertEqual(PainDraft.rounded(-3), 0)
        XCTAssertEqual(PainDraft.rounded(12), 10)
        XCTAssertEqual(PainDraft.rounded(.nan), 0)
        var draft = PainDraft.zeros([.achillesLeft])
        draft.setScore(6.26, for: .achillesLeft)
        XCTAssertEqual(draft.entries, [PainEntry(site: .achillesLeft, score: 6.5)])
        XCTAssertTrue(draft.entries.allSatisfy(\.isValid))
    }

    func testDraftAddsAndRemovesSites() {
        var draft = PainDraft.zeros([.achillesLeft])
        XCTAssertEqual(draft.addableSites, [.achillesRight, .kneeLeft, .kneeRight, .other])
        draft.add(.kneeRight)
        draft.add(.kneeRight)
        XCTAssertEqual(draft.rows.map(\.site), [.achillesLeft, .kneeRight], "a site is there once")
        XCTAssertEqual(draft.addableSites, [.achillesRight, .kneeLeft, .other])
        draft.remove(.achillesLeft)
        draft.remove(.kneeRight)
        XCTAssertTrue(draft.isEmpty)
        XCTAssertEqual(draft.entries, [], "every row removed: asked, nothing hurts")
    }

    func testDraftNotes() {
        var draft = PainDraft.zeros([.other])
        draft.setNote("   ", for: .other)
        XCTAssertNil(draft.entries.first?.note, "a blank note is left out")
        draft.setNote("  Lower back \n", for: .other)
        XCTAssertEqual(draft.entries.first?.note, "Lower back")
        draft.setNote(String(repeating: "x", count: 250), for: .other)
        XCTAssertEqual(draft.entries.first?.note?.utf16.count, PainEntry.noteMaxLength)
        draft.setNote(String(repeating: "\u{1F9B5}", count: 150), for: .other)
        XCTAssertEqual(draft.entries.first?.note?.utf16.count, 200, "cut by UTF-16 units, never inside a character")
        XCTAssertTrue(draft.entries.allSatisfy(\.isValid))
    }

    func testDraftFromARecordedAnswer() {
        let draft = PainDraft(entries: [
            PainEntry(site: .kneeLeft, score: 1),
            PainEntry(site: .achillesLeft, score: 2),
            PainEntry(site: .kneeLeft, score: 3, note: "second")
        ])
        XCTAssertEqual(draft.rows.map(\.site), [.kneeLeft, .achillesLeft], "recorded order, one row per site")
        XCTAssertEqual(draft.rows.map(\.score), [3, 2], "the highest score of a site, as the vault reads it")
    }

    func testDefaultSitesComeFromTheLatestEarlierAchillesAnswer() throws {
        // Nothing scored before the example's Wednesday: the left Achilles.
        XCTAssertEqual(PainDraft.defaultSites(before: D.asOf, plan: try snapshot().plan), [.achillesLeft])

        // Monday both sides, Tuesday the right side and a knee: Tuesday wins.
        let both: [[String: Any]] = [["site": "achilles-right", "score": 1], ["site": "achilles-left", "score": 0]]
        let right: [[String: Any]] = [["site": "knee-left", "score": 2], ["site": "achilles-right", "score": 0]]
        let data = try Fixtures.mutatedExample { object in
            try Fixtures.mutateDay(&object, week: 2, day: 0) { $0["pains"] = both }
            try Fixtures.mutateDay(&object, week: 2, day: 1) { $0["pains"] = right }
        }
        let plan = try snapshot(data: data).plan
        XCTAssertEqual(PainDraft.defaultSites(before: D.asOf, plan: plan), [.achillesRight])
        XCTAssertEqual(PainDraft.defaultSites(before: tuesday, plan: plan), [.achillesLeft, .achillesRight], "in the offered order")

        // A knee alone is not an Achilles answer.
        let knee: [[String: Any]] = [["site": "knee-left", "score": 2]]
        let kneeOnly = try snapshot(data: try example(pains: knee, weekday: 1)).plan
        XCTAssertEqual(PainDraft.defaultSites(before: D.asOf, plan: kneeOnly), [.achillesLeft])
    }

    // MARK: The step on Today (design D5)

    func testTheStepIsOpenWhileThePainIsNotAsked() throws {
        let data = try example(pains: NSNull())
        let row = try XCTUnwrap(today(try snapshot(data: data)).trainingDay(on: D.asOf).checkIn)
        let step = try XCTUnwrap(row.pain, "the example's check-in chose amber")
        XCTAssertFalse(step.isRecorded)
        XCTAssertTrue(step.opensExpanded)
        XCTAssertEqual(step.draft, PainDraft.zeros([.achillesLeft]))
        XCTAssertEqual(step.title, "Pain this morning")
        XCTAssertEqual(step.hint, "0 = no pain, 10 = worst imaginable")
        XCTAssertEqual(step.saveTitle, "Save pain")
        XCTAssertEqual(step.siteName(.achillesLeft), "Achilles (left)")
        XCTAssertEqual(step.siteName(.other), "Other site")
        XCTAssertEqual(step.removeLabels[.kneeRight], "Remove Knee (right)")
        XCTAssertNil(step.deliveryLine)

        // One tap confirms 0: the same check-in as the row, plus pains.
        XCTAssertEqual(step.payload(step.draft), MorningCheckInPayload(
            date: D.asOf, light: .amberLight, sessionId: "2030-w43-wed-am", option: .a,
            pains: [PainEntry(site: .achillesLeft, score: 0)]
        ))
        XCTAssertNoThrow(try HubEventPayload.morningCheckIn(step.payload(step.draft)).validate())
    }

    func testNoStepWithoutAChosenLight() throws {
        let data = try Fixtures.mutatedExample { object in
            try Fixtures.mutateDay(&object, week: 2, day: 2) { day in
                day["light"] = NSNull()
                day["lightSource"] = NSNull()
            }
        }
        let row = try XCTUnwrap(today(try snapshot(data: data)).trainingDay(on: D.asOf).checkIn)
        XCTAssertNil(row.pain)
    }

    func testARecordedAnswerFoldsTheStepToEdit() throws {
        let model = today(try snapshot()).trainingDay(on: D.asOf)
        let step = try XCTUnwrap(model.checkIn?.pain)
        XCTAssertTrue(step.isRecorded)
        XCTAssertFalse(step.opensExpanded)
        XCTAssertEqual(step.editTitle, "Edit pain")
        XCTAssertEqual(step.draft.rows.map(\.site), [.achillesLeft, .kneeRight])
        XCTAssertEqual(step.draft.rows.map(\.score), [5.5, 1])
        XCTAssertEqual(model.painLine, "Pain: Achilles (left) 5.5/10 · Knee (right) 1/10")
    }

    func testAnEditReplacesAndShowsItsDelivery() throws {
        let segment = UUID()
        let edit = logged(checkIn(pains: [PainEntry(site: .achillesLeft, score: 3)]), seq: 1, segment: segment)
        let model = today(try snapshot([edit], unsent: [segment])).trainingDay(on: D.asOf)
        XCTAssertEqual(model.painLine, "Pain: Achilles (left) 3/10")
        XCTAssertEqual(model.checkIn?.pain?.deliveryLine, "Saved on phone")
        XCTAssertEqual(model.checkIn?.pain?.draft, PainDraft.zeros([.achillesLeft]).updating(3))

        let sent = today(try snapshot([edit], unsent: [])).trainingDay(on: D.asOf)
        XCTAssertEqual(sent.checkIn?.pain?.deliveryLine, "Sent")

        let none = today(try snapshot([logged(checkIn(pains: []), seq: 2)])).trainingDay(on: D.asOf)
        XCTAssertEqual(none.painLine, "Pain: none")
        XCTAssertEqual(none.checkIn?.pain?.draft.isEmpty, true)
    }

    func testThePainLineShowsWithoutRecording() throws {
        let model = today(try snapshot(enabled: false)).trainingDay(on: D.asOf)
        XCTAssertNil(model.checkIn)
        XCTAssertEqual(model.painLine, "Pain: Achilles (left) 5.5/10 · Knee (right) 1/10")
        XCTAssertNil(today(try snapshot()).trainingDay(on: tuesday).painLine, "not asked")
    }

    func testScoreTexts() throws {
        let step = try XCTUnwrap(today(try snapshot()).trainingDay(on: D.asOf).checkIn?.pain)
        XCTAssertEqual(step.scoreTexts.count, 21)
        XCTAssertEqual(step.scoreText(0), "0/10")
        XCTAssertEqual(step.scoreText(4.5), "4.5/10")
        XCTAssertEqual(step.scoreText(10), "10/10")
        XCTAssertEqual(step.scoreAccessibilityValue(4.5), "4.5 of 10")

        let czech = try XCTUnwrap(today(try snapshot(), .czech).trainingDay(on: D.asOf).checkIn?.pain)
        XCTAssertEqual(czech.scoreText(4.5), "4,5/10")
        XCTAssertEqual(czech.scoreAccessibilityValue(4.5), "4,5 z 10")
        XCTAssertEqual(czech.title, "Bolest ráno")
        XCTAssertEqual(czech.siteName(.achillesRight), "Achilovka (pravá)")
        XCTAssertEqual(czech.editTitle, "Upravit bolest")
    }

    func testCzechPainLine() throws {
        let model = today(try snapshot(), .czech).trainingDay(on: D.asOf)
        XCTAssertEqual(model.painLine, "Bolest: Achilovka (levá) 5,5/10 · Koleno (pravé) 1/10")
        let none = today(try snapshot([logged(checkIn(pains: []), seq: 1)]), .czech).trainingDay(on: D.asOf)
        XCTAssertEqual(none.painLine, "Bolest: žádná")
    }

    // MARK: Plan tags (design D6)

    func testPlanDayRowsCarryPainTags() throws {
        let builder = PlanBuilder(source: .loaded(try snapshot()), language: .english, today: D.asOf)
        guard case .days(let rows) = builder.week(D.week("2030-W43")).content else { return XCTFail("W43 is written") }
        XCTAssertEqual(rows[2].painTags, ["Achilles (left) 5.5/10", "Knee (right) 1/10"])
        XCTAssertTrue(rows.enumerated().filter { $0.offset != 2 }.allSatisfy { $0.element.painTags.isEmpty })
        XCTAssertEqual(builder.dayRow(D.asOf).painTags, ["Achilles (left) 5.5/10", "Knee (right) 1/10"], "the month's day sheet")

        let czech = PlanBuilder(source: .loaded(try snapshot()), language: .czech, today: D.asOf)
        XCTAssertEqual(czech.dayRow(D.asOf).painTags, ["Achilovka (levá) 5,5/10", "Koleno (pravé) 1/10"])
    }

    func testAnotherSiteShowsItsNote() throws {
        let other = logged(checkIn(pains: [PainEntry(site: .other, score: 2, note: "Lower back")]), seq: 1)
        let builder = PlanBuilder(source: .loaded(try snapshot([other])), language: .english, today: D.asOf)
        XCTAssertEqual(builder.dayRow(D.asOf).painTags, ["Other site 2/10 (Lower back)"])
    }
}

private extension PainDraft {
    /// The first row at `score` (test shorthand).
    func updating(_ score: Double) -> PainDraft {
        var copy = self
        if let site = copy.rows.first?.site { copy.setScore(score, for: site) }
        return copy
    }
}
