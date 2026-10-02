// PlanEditingTests.swift
//
// Plan edits from the phone (add-plan-editing; spec training-plan-editing),
// on the vault's example fixture, whose `asOf` is Wednesday 23 October 2030
// (W43, revision 1; W44 proposed, revision 1, with the race on Sunday
// 3 November and a two-ambers rule edit on Wednesday 30 October):
//
//   - what is offered: moves inside the week from today on, swap partners,
//     skip/unskip, rule overrides, nothing for a race (A50), past days and
//     done sessions, a week without a revision, stacked edits;
//   - the command builders and their refusals;
//   - the fold: pending (saved/sent), withdrawing, received, and the
//     vault's own example commands with the example projection's acks and
//     outcomes (absorbed, refused with its bilingual reason, superseded,
//     retracted), an unknown outcome word;
//   - the preview: move, swap, skip, unskip, a stale move, a rule override
//     without preview;
//   - the screens' words in English and Czech, the week's plan changes,
//     the row and Today badges;
//   - a round trip through the real recorder, log and queue.
//
// Real stores on temp files for the recorder (house convention); dates in
// assertions are built with DateText, never spelled, so CLDR changes can't
// break them.

import XCTest
import VaultKit
@testable import TrainingCore

final class PlanEditingTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_918_951_651)
    private let me = "ios-0000beef"
    private let w43 = D.week("2030-W43")
    private let w44 = D.week("2030-W44")

    private func logged(_ payload: HubEventPayload, seq: Int, segment: UUID? = nil, device: String = "ios-0000beef") -> LoggedEvent {
        LoggedEvent(
            event: HubEvent(id: "cmd-\(seq)", deviceId: device, seq: seq, at: "t", payload: payload),
            recordedAt: t0.addingTimeInterval(Double(seq)),
            segmentID: segment
        )
    }

    private func snapshot(
        _ events: [LoggedEvent] = [],
        unsent: Set<UUID> = [],
        acks: [String: Int] = [:],
        outcomes: [PlanOutcome] = [],
        capabilities: TrainingCapabilities = .recording(enabled: true),
        data: Data? = nil
    ) throws -> TrainingSnapshot {
        let projection: Projection
        if let data {
            guard case .success(let decoded) = ProjectionDecoder.decode(data) else {
                XCTFail("fixture did not decode")
                throw ProjectionRejection.invalid(reason: "test")
            }
            projection = decoded.projection
        } else {
            projection = try Fixtures.exampleProjection().projection
        }
        let overlay = PendingOverlay.fold(events, unsentSegments: unsent, ackedSeqs: acks, outcomes: outcomes)
        return TrainingSnapshot(projection: projection, overlay: overlay, capabilities: capabilities)
    }

    private func builder(_ snapshot: TrainingSnapshot, _ language: TrainingLanguage = .english) -> PlanBuilder {
        PlanBuilder(source: .loaded(snapshot), language: language, today: D.asOf)
    }

    private func options(_ id: String, _ snapshot: TrainingSnapshot) throws -> PlanEditOptions {
        try XCTUnwrap(PlanEditPolicy.options(sessionID: id, snapshot: snapshot, today: D.asOf))
    }

    private func rows(_ week: ISOWeek, _ snapshot: TrainingSnapshot) throws -> [SessionRowModel] {
        guard case .days(let days) = builder(snapshot).week(week).content else {
            XCTFail("week \(week) has no days")
            return []
        }
        return days.flatMap(\.sessions)
    }

    private func move(_ id: String, from: String, to: String, week: ISOWeek? = nil) -> HubEventPayload {
        .sessionMoved(SessionMovedPayload(week: week ?? w43, baseRevision: 1, sessionId: id, from: D.date(from), to: D.date(to)))
    }

    private func short(_ date: String, _ language: TrainingLanguage = .english) -> String {
        DateText(language).short(D.date(date))
    }

    // MARK: What is offered

    func testTodaysSessionMovesWithinTheWeekFromTodayOn() throws {
        let options = try self.options("2030-w43-wed-am", try snapshot())
        XCTAssertEqual(options.week, w43)
        XCTAssertEqual(options.baseRevision, 1)
        XCTAssertEqual(options.date, D.asOf)
        XCTAssertEqual(options.moveTargets, ["2030-10-24", "2030-10-25", "2030-10-26", "2030-10-27"].map(D.date),
                       "no Monday or Tuesday (past), no day of W44")
        XCTAssertEqual(Set(options.swapPartners.map(\.sessionID)), ["2030-w43-thu-pm", "2030-w43-sun-pm", "2030-w43-sat-am"])
        XCTAssertTrue(options.canSkip)
        XCTAssertFalse(options.canUnskip)
        XCTAssertEqual(options.overridableRules, [])
        XCTAssertNil(options.block)

        // The spec's scenario: Thursday's session, opened on Wednesday.
        let thursday = try self.options("2030-w43-thu-pm", try snapshot())
        XCTAssertEqual(thursday.moveTargets, ["2030-10-23", "2030-10-25", "2030-10-26", "2030-10-27"].map(D.date))
    }

    func testPastDaysAndDoneSessions() throws {
        let snap = try snapshot()
        // Tuesday's mobility session is the example's missed one (Monday's
        // gym session is done by hand since the vault's 2026-10-01 fixture).
        let missed = try self.options("2030-w43-tue-pm", snap)
        XCTAssertEqual(missed.moveTargets, [])
        XCTAssertEqual(missed.swapPartners, [])
        XCTAssertTrue(missed.canSkip, "the vault skips past days")
        XCTAssertEqual(missed.block, .pastDay)

        let done = try self.options("2030-w43-tue-am", snap)
        XCTAssertEqual(done.moveTargets, [])
        XCTAssertFalse(done.canSkip, "tasks 0.2: a done session is not skipped")
        XCTAssertEqual(done.block, .done)

        XCTAssertThrowsError(try PlanEditPolicy.move(sessionID: "2030-w43-tue-pm", to: D.date("2030-10-24"), snapshot: snap, today: D.asOf))
        XCTAssertThrowsError(try PlanEditPolicy.skip(sessionID: "2030-w43-tue-am", reason: nil, snapshot: snap, today: D.asOf))
        // The vault's session-pain note on the done tempo only informs:
        // there is no rule to override (add-daily-checkin-and-pain-mode).
        XCTAssertEqual(done.overridableRules, [])

        // Done without a watch (`done.source: "manual"`, no activity) is
        // done like any other.
        let byHand = try self.options("2030-w43-mon-pm", snap)
        XCTAssertEqual(byHand.block, .done)
        XCTAssertFalse(byHand.canSkip)
    }

    func testTheRaceSessionIsFixed() throws {
        let snap = try snapshot()
        let race = try self.options("2030-w44-sun-am", snap)
        XCTAssertEqual(race.block, .race)
        XCTAssertEqual(race.moveTargets, [])
        XCTAssertEqual(race.swapPartners, [])
        XCTAssertFalse(race.canSkip)

        let easy = try self.options("2030-w44-fri-am", snap)
        XCTAssertEqual(Set(easy.swapPartners.map(\.sessionID)), ["2030-w44-mon-pm", "2030-w44-wed-am", "2030-w44-tue-am"],
                       "the race is nobody's swap partner")

        XCTAssertThrowsError(try PlanEditPolicy.move(sessionID: "2030-w44-sun-am", to: D.date("2030-11-02"), snapshot: snap, today: D.asOf))
        XCTAssertThrowsError(try PlanEditPolicy.skip(sessionID: "2030-w44-sun-am", reason: "tired", snapshot: snap, today: D.asOf))
        XCTAssertThrowsError(try PlanEditPolicy.swap(sessionID: "2030-w44-fri-am", with: "2030-w44-sun-am", snapshot: snap, today: D.asOf))

        let detail = try XCTUnwrap(builder(snap).sessionDetail(id: "2030-w44-sun-am"))
        let editing = try XCTUnwrap(detail.editing)
        XCTAssertEqual(editing.blockText, TrainingText(.english)(.editBlockRace))
        XCTAssertTrue(editing.moveTargets.isEmpty && editing.swapPartners.isEmpty && !editing.canSkip)
        let czech = try XCTUnwrap(builder(snap, .czech).sessionDetail(id: "2030-w44-sun-am")?.editing)
        XCTAssertTrue(czech.blockText?.hasPrefix("Závod:") ?? false)
    }

    func testBuildersMakeTheCommandsTheVaultExpects() throws {
        let snap = try snapshot()
        XCTAssertEqual(
            try PlanEditPolicy.move(sessionID: "2030-w43-wed-am", to: D.date("2030-10-25"), snapshot: snap, today: D.asOf),
            move("2030-w43-wed-am", from: "2030-10-23", to: "2030-10-25")
        )
        XCTAssertThrowsError(try PlanEditPolicy.move(sessionID: "2030-w43-wed-am", to: D.date("2030-10-28"), snapshot: snap, today: D.asOf), "another week")
        XCTAssertThrowsError(try PlanEditPolicy.move(sessionID: "2030-w43-wed-am", to: D.date("2030-10-22"), snapshot: snap, today: D.asOf), "a past day")
        XCTAssertThrowsError(try PlanEditPolicy.move(sessionID: "2030-w43-wed-am", to: D.asOf, snapshot: snap, today: D.asOf), "the same day")

        XCTAssertEqual(
            try PlanEditPolicy.swap(sessionID: "2030-w43-wed-am", with: "2030-w43-sat-am", snapshot: snap, today: D.asOf),
            .sessionsSwapped(SessionsSwappedPayload(week: w43, baseRevision: 1, a: "2030-w43-wed-am", aDate: D.asOf, b: "2030-w43-sat-am", bDate: D.date("2030-10-26")))
        )
        XCTAssertEqual(
            try PlanEditPolicy.skip(sessionID: "2030-w43-wed-am", reason: "  Calf tight \n", snapshot: snap, today: D.asOf),
            .sessionSkipped(SessionSkippedPayload(week: w43, baseRevision: 1, sessionId: "2030-w43-wed-am", reason: "Calf tight"))
        )
        XCTAssertEqual(
            try PlanEditPolicy.skip(sessionID: "2030-w43-wed-am", reason: "   ", snapshot: snap, today: D.asOf),
            .sessionSkipped(SessionSkippedPayload(week: w43, baseRevision: 1, sessionId: "2030-w43-wed-am", reason: nil)),
            "tasks 0.4: a blank reason is no reason"
        )
        XCTAssertEqual(
            try PlanEditPolicy.unskip(sessionID: "2030-w44-mon-pm", snapshot: snap, today: D.asOf),
            .sessionUnskipped(SessionUnskippedPayload(week: w44, baseRevision: 1, sessionId: "2030-w44-mon-pm"))
        )
        XCTAssertThrowsError(try PlanEditPolicy.unskip(sessionID: "2030-w43-wed-am", snapshot: snap, today: D.asOf), "not skipped")
        for payload in [
            try PlanEditPolicy.move(sessionID: "2030-w43-wed-am", to: D.date("2030-10-27"), snapshot: snap, today: D.asOf),
            try PlanEditPolicy.unskip(sessionID: "2030-w44-mon-pm", snapshot: snap, today: D.asOf)
        ] {
            XCTAssertNoThrow(try payload.validate())
        }
    }

    func testRuleOverrideIsOfferedWithItsWarning() throws {
        let snap = try snapshot()
        let options = try self.options("2030-w44-wed-am", snap)
        XCTAssertEqual(options.overridableRules, ["two-ambers"])
        XCTAssertEqual(
            try PlanEditPolicy.overrideRule("two-ambers", sessionID: "2030-w44-wed-am", snapshot: snap, today: D.asOf),
            .ruleOverridden(RuleOverriddenPayload(week: w44, baseRevision: 1, sessionId: "2030-w44-wed-am", rule: "two-ambers"))
        )
        XCTAssertThrowsError(try PlanEditPolicy.overrideRule("red-holds", sessionID: "2030-w44-wed-am", snapshot: snap, today: D.asOf))
        XCTAssertEqual(try self.options("2030-w43-wed-am", snap).overridableRules, [], "no rule edited it")

        let overrideCommand = try XCTUnwrap(builder(snap).sessionDetail(id: "2030-w44-wed-am")?.editing?.overrides.first)
        XCTAssertEqual(overrideCommand.rule, "two-ambers")
        XCTAssertEqual(overrideCommand.buttonTitle, "Override the rule two-ambers")
        XCTAssertEqual(overrideCommand.warningTitle, "Override the rule two-ambers?")
        XCTAssertTrue(overrideCommand.warningMessage.hasPrefix("Two amber mornings in a row"), overrideCommand.warningMessage)
        XCTAssertTrue(overrideCommand.warningMessage.hasSuffix(TrainingText(.english)(.editOverrideMessage)))
        let czech = try XCTUnwrap(builder(snap, .czech).sessionDetail(id: "2030-w44-wed-am")?.editing?.overrides.first)
        XCTAssertEqual(czech.warningTitle, "Obejít pravidlo two-ambers?")
    }

    func testNothingWithoutTheCapability() throws {
        let snap = try snapshot(capabilities: .checkIns(enabled: true))
        XCTAssertNil(PlanEditPolicy.options(sessionID: "2030-w43-wed-am", snapshot: snap, today: D.asOf))
        XCTAssertNil(builder(snap).sessionDetail(id: "2030-w43-wed-am")?.editing)
        XCTAssertThrowsError(try PlanEditPolicy.move(sessionID: "2030-w43-wed-am", to: D.date("2030-10-25"), snapshot: snap, today: D.asOf))
        XCTAssertFalse(TrainingCapabilities.checkIns(enabled: true).canEditPlan)
        XCTAssertTrue(TrainingCapabilities.recording(enabled: true).canEditPlan)
        XCTAssertEqual(TrainingCapabilities.recording(enabled: false), .readOnly)
    }

    func testAWeekWithoutRevisionCannotBeEdited() throws {
        let data = try Fixtures.mutatedExample { object in
            var plan = try XCTUnwrap(object["plan"] as? [String: Any])
            var weeks = try XCTUnwrap(plan["weeks"] as? [[String: Any]])
            XCTAssertEqual(weeks[2]["week"] as? String, "2030-W43")
            weeks[2]["revision"] = NSNull()
            plan["weeks"] = weeks
            object["plan"] = plan
        }
        let options = try self.options("2030-w43-wed-am", try snapshot(data: data))
        XCTAssertEqual(options.block, .noRevision)
        XCTAssertNil(options.baseRevision)
        XCTAssertFalse(options.hasActions)
    }

    // MARK: The vault's answers

    func testTheVaultsExampleCommandsFoldWithTheExampleOutcomes() throws {
        let projection = try Fixtures.exampleProjection().projection
        let events = HubEventCodec.decode(try EventFixtures.vault("events.v1.example.jsonl")).events
        let logged = events.map { LoggedEvent(event: $0, recordedAt: t0.addingTimeInterval(Double($0.seq)), segmentID: nil) }
        let outcomes = PlanOutcome.parse(projection.outcomes)
        // Ten command outcomes and (since 2026-10-01) two refused habit
        // ticks, which name no week and no session and match no command.
        XCTAssertEqual(outcomes.count, 12)
        XCTAssertEqual(outcomes.filter { $0.type == "habit.tick" }.map(\.seq), [30, 31])
        XCTAssertTrue(outcomes.filter { $0.type == "habit.tick" }.allSatisfy { $0.week == nil && $0.sessionId == nil && $0.status.known == .refused })
        let overlay = PendingOverlay.fold(logged, unsentSegments: [], ackedSeqs: CheckInOverlay.ackedSeqs(from: projection.acks), outcomes: outcomes)
        XCTAssertEqual(overlay.commands.map(\.seq), [4, 13, 14, 15, 16, 17, 19, 22, 23])

        func status(_ seq: Int) throws -> PlanCommandStatus {
            try XCTUnwrap(overlay.commands.first { $0.seq == seq }).status
        }
        XCTAssertTrue(try status(4).isApplied, "absorbed reads as applied")
        XCTAssertTrue(try status(14).isApplied)
        guard case .resolved(let refused, let reason) = try status(16) else { return XCTFail("seq 16 unresolved") }
        XCTAssertEqual(refused.known, .refused)
        XCTAssertEqual(reason?.resolved(.english), "Session 2030-w44-sun-am is a race: its date is set by the organiser, so the app cannot move, swap or skip it.")
        XCTAssertTrue(reason?.resolved(.czech).hasPrefix("Trénink 2030-w44-sun-am je závod") ?? false)
        XCTAssertTrue(try status(23).isNotApplied)
        guard case .resolved(let retracted, _) = try status(19) else { return XCTFail("seq 19 unresolved") }
        XCTAssertEqual(retracted.known, .retracted)
        XCTAssertFalse(overlay.commands.contains { $0.status.isPending }, "everything is acknowledged")

        // Nothing to preview: the projection already folded them all.
        let plan = try XCTUnwrap(projection.plan)
        XCTAssertEqual(EffectivePlan(plan: plan, overlay: overlay).plan, plan)
    }

    func testTheScreensShowTheVaultsAnswers() throws {
        let projection = try Fixtures.exampleProjection().projection
        let events = HubEventCodec.decode(try EventFixtures.vault("events.v1.example.jsonl")).events
        let logged = events.map { LoggedEvent(event: $0, recordedAt: t0.addingTimeInterval(Double($0.seq)), segmentID: nil) }
        let snap = try snapshot(
            logged,
            acks: CheckInOverlay.ackedSeqs(from: projection.acks),
            outcomes: PlanOutcome.parse(projection.outcomes)
        )

        // The week lists this phone's changes with the answers.
        let changes = builder(snap).week(w44).planChanges
        XCTAssertEqual(changes.map(\.commandID), [13, 14, 15, 16, 19, 22, 23].map { events[$0 - 1].id })
        let raceMove = try XCTUnwrap(changes.first { $0.commandID == events[15].id })
        XCTAssertEqual(raceMove.status.kind, .refused)
        XCTAssertEqual(raceMove.status.statusText, "Refused")
        XCTAssertEqual(raceMove.status.description, "Move to " + short("2030-11-02"))
        XCTAssertFalse(raceMove.status.canWithdraw)
        let czech = try XCTUnwrap(builder(snap, .czech).week(w44).planChanges.first { $0.commandID == events[15].id })
        XCTAssertEqual(czech.status.statusText, "Odmítnuto")
        XCTAssertTrue(czech.status.reason?.hasPrefix("Trénink 2030-w44-sun-am je závod") ?? false)
        XCTAssertEqual(czech.status.description, "Přesunout na " + short("2030-11-02", .czech))
        XCTAssertEqual(builder(snap).week(w43).planChanges.first?.status.statusText, "Refused", "the past-day move")

        // The superseded move marks its session on the week.
        let fri = try XCTUnwrap(try rows(w44, snap).first { $0.id == "2030-w44-fri-am" })
        XCTAssertEqual(fri.editBadge, .notApplied)
        XCTAssertEqual(fri.editBadgeText, "Change not applied")
        let race = try XCTUnwrap(try rows(w44, snap).first { $0.id == "2030-w44-sun-am" })
        XCTAssertNil(race.editBadge, "its latest command (the unskip) was applied")

        let detail = try XCTUnwrap(builder(snap).sessionDetail(id: "2030-w44-fri-am")?.editing?.latest)
        XCTAssertEqual(detail.kind, .notApplied)
        XCTAssertEqual(detail.statusText, "Not applied")
        XCTAssertEqual(detail.reason, "Session 2030-w44-fri-am is on 2030-10-29, not 2030-11-01.")
        XCTAssertEqual(detail.description, "Move to " + short("2030-10-30"))
    }

    func testAnUnknownOutcomeAndAnAppliedOverride() throws {
        let overrideCommand = logged(.ruleOverridden(RuleOverriddenPayload(week: w44, baseRevision: 1, sessionId: "2030-w44-wed-am", rule: "two-ambers")), seq: 40)
        let applied = PlanOutcome(event: overrideCommand.event.id, deviceId: me, seq: 40, type: "plan.rule.overridden", week: w44, sessionId: "2030-w44-wed-am", status: OpenEnum(PlanOutcomeStatus.applied), reason: nil)
        let snap = try snapshot([overrideCommand], acks: [me: 40], outcomes: [applied])
        let options = try self.options("2030-w44-wed-am", snap)
        XCTAssertEqual(options.withdrawable, [overrideCommand.event.id], "tasks 0.3: an applied override can be withdrawn")
        XCTAssertEqual(options.overridableRules, [], "already overridden")
        XCTAssertNil(options.block)
        XCTAssertEqual(try PlanEditPolicy.withdraw(commandID: overrideCommand.event.id, snapshot: snap), .eventRetracted(EventRetractedPayload(target: overrideCommand.event.id)))

        let odd = PlanOutcome(event: overrideCommand.event.id, deviceId: me, seq: 40, type: nil, week: nil, sessionId: nil, status: OpenEnum(rawValue: "postponed"), reason: LocalizedText(values: ["en": "Later.", "cz": "Později."]))
        let oddSnap = try snapshot([overrideCommand], acks: [me: 40], outcomes: [odd])
        let latest = try XCTUnwrap(builder(oddSnap).sessionDetail(id: "2030-w44-wed-am")?.editing?.latest)
        XCTAssertEqual(latest.kind, .answered)
        XCTAssertEqual(latest.statusText, "Answered by the vault")
        XCTAssertEqual(latest.reason, "Later.")
        XCTAssertEqual(builder(oddSnap, .czech).sessionDetail(id: "2030-w44-wed-am")?.editing?.latest?.reason, "Později.")
        XCTAssertThrowsError(try PlanEditPolicy.withdraw(commandID: overrideCommand.event.id, snapshot: oddSnap), "not applied, not pending")
    }

    func testOutcomesParseTolerantly() {
        let values: [JSONValue] = [
            .object(["event": .string("e1"), "seq": .number(3), "status": .string("refused"), "reason": .object(["en": .string("No."), "cz": .string("Ne.")])]),
            .object(["event": .string("e2"), "status": .string("applied"), "reason": .null, "week": .string("2030-W44")]),
            .object(["event": .string("e3")]),
            .string("junk")
        ]
        let outcomes = PlanOutcome.parse(values)
        XCTAssertEqual(outcomes.map(\.event), ["e1", "e2"], "an entry without a status is left out")
        XCTAssertEqual(outcomes[0].seq, 3)
        XCTAssertEqual(outcomes[0].reason?.resolved(.czech), "Ne.")
        XCTAssertNil(outcomes[1].reason)
        XCTAssertEqual(outcomes[1].week, w44)
    }

    // MARK: Pending and the preview

    func testPendingCommandsShowAtOnce() throws {
        let segment = UUID()
        let moveSat = logged(move("2030-w43-sat-am", from: "2030-10-26", to: "2030-10-27"), seq: 30)
        let skipThu = logged(.sessionSkipped(SessionSkippedPayload(week: w43, baseRevision: 1, sessionId: "2030-w43-thu-pm", reason: "Calf")), seq: 31, segment: segment)
        let snap = try snapshot([moveSat, skipThu])
        let plan = try XCTUnwrap(snap.plan)
        XCTAssertEqual(plan.overlay.commands.map(\.status), [.pending(.savedOnPhone), .pending(.sent)])
        XCTAssertEqual(plan.overlay.commands.map(\.previewed), [true, true])

        XCTAssertEqual(plan.day(D.date("2030-10-26"))?.sessions.map(\.id), [])
        let moved = try XCTUnwrap(plan.day(D.date("2030-10-27"))?.sessions.first)
        XCTAssertEqual(moved.id, "2030-w43-sat-am")
        XCTAssertEqual(moved.origin?["kind"]?.stringValue, "moved")
        XCTAssertEqual(moved.origin?["from"]?.stringValue, "2030-10-26")
        XCTAssertEqual(moved.origin?["event"]?.stringValue, moveSat.event.id)
        XCTAssertEqual(plan.day(D.date("2030-10-24"))?.sessions.first?.status?.known, .skipped)

        // Marked on the week, in the detail and on Today.
        let sat = try XCTUnwrap(try rows(w43, snap).first { $0.id == "2030-w43-sat-am" })
        XCTAssertEqual(sat.date, D.date("2030-10-27"))
        XCTAssertEqual(sat.editBadge, .pending)
        XCTAssertEqual(sat.editBadgeText, "Change pending")
        let editing = try XCTUnwrap(builder(snap).sessionDetail(id: "2030-w43-sat-am")?.editing)
        XCTAssertEqual(editing.latest?.statusText, "Pending · Saved on phone")
        XCTAssertEqual(editing.latest?.description, "Move to " + short("2030-10-27"))
        XCTAssertEqual(editing.blockText, TrainingText(.english)(.editBlockWaiting))
        XCTAssertTrue(editing.moveTargets.isEmpty && editing.swapPartners.isEmpty && !editing.canSkip, "tasks 0.1: only Withdraw")
        XCTAssertEqual(editing.withdrawable.map(\.commandID), [moveSat.event.id])
        let thu = try XCTUnwrap(builder(snap).sessionDetail(id: "2030-w43-thu-pm")?.editing?.latest)
        XCTAssertEqual(thu.statusText, "Pending · Sent")
        XCTAssertEqual(thu.description, "Skip: Calf")
        let czech = try XCTUnwrap(builder(snap, .czech).sessionDetail(id: "2030-w43-sat-am")?.editing?.latest)
        XCTAssertEqual(czech.statusText, "Čeká · Uloženo v telefonu")
        XCTAssertEqual(czech.description, "Přesunout na " + short("2030-10-27", .czech))
        let today = TodayTrainingBuilder(source: .loaded(snap), language: .english).trainingDay(on: D.date("2030-10-27"))
        XCTAssertEqual(today.sessions.first?.pendingBadge, "Change pending")

        // A waiting session is nobody's swap partner.
        XCTAssertEqual(try self.options("2030-w43-wed-am", snap).swapPartners.map(\.sessionID), ["2030-w43-sun-pm"])

        // Withdraw the move.
        XCTAssertEqual(try PlanEditPolicy.withdraw(commandID: moveSat.event.id, snapshot: snap), .eventRetracted(EventRetractedPayload(target: moveSat.event.id)))
        XCTAssertThrowsError(try PlanEditPolicy.withdraw(commandID: "nope", snapshot: snap))
    }

    func testWithdrawingAndReceived() throws {
        let moveSat = logged(move("2030-w43-sat-am", from: "2030-10-26", to: "2030-10-27"), seq: 30)
        let skipThu = logged(.sessionSkipped(SessionSkippedPayload(week: w43, baseRevision: 1, sessionId: "2030-w43-thu-pm")), seq: 31)
        let retract = logged(.eventRetracted(EventRetractedPayload(target: moveSat.event.id)), seq: 32)

        let withdrawing = try snapshot([moveSat, skipThu, retract])
        let plan = try XCTUnwrap(withdrawing.plan)
        let command = try XCTUnwrap(plan.overlay.command(id: moveSat.event.id))
        XCTAssertEqual(command.status, .withdrawing(.savedOnPhone))
        XCTAssertFalse(command.previewed)
        XCTAssertEqual(plan.day(D.date("2030-10-26"))?.sessions.map(\.id), ["2030-w43-sat-am"], "back where the vault has it")
        let latest = try XCTUnwrap(builder(withdrawing).sessionDetail(id: "2030-w43-sat-am")?.editing?.latest)
        XCTAssertEqual(latest.statusText, "Withdrawal pending · Saved on phone")
        XCTAssertFalse(latest.canWithdraw)
        XCTAssertEqual(try rows(w43, withdrawing).first { $0.id == "2030-w43-sat-am" }?.editBadge, .pending)
        XCTAssertThrowsError(try PlanEditPolicy.withdraw(commandID: moveSat.event.id, snapshot: withdrawing))

        // The vault read all three but published no outcome.
        let acked = try snapshot([moveSat, skipThu, retract], acks: [me: 32])
        let overlay = try XCTUnwrap(acked.plan?.overlay)
        XCTAssertEqual(overlay.command(id: moveSat.event.id)?.status, .resolved(OpenEnum(PlanOutcomeStatus.retracted), reason: nil))
        XCTAssertEqual(overlay.command(id: skipThu.event.id)?.status, .received)
        XCTAssertEqual(builder(acked).sessionDetail(id: "2030-w43-thu-pm")?.editing?.latest?.statusText, "Received by the vault")
        XCTAssertNil(try rows(w43, acked).first { $0.id == "2030-w43-thu-pm" }?.editBadge)
        XCTAssertEqual(acked.plan?.day(D.date("2030-10-24"))?.sessions.first?.status?.known, .planned, "no preview once acknowledged")
    }

    func testSwapUnskipAndOverridePreview() throws {
        let swap = logged(.sessionsSwapped(SessionsSwappedPayload(week: w43, baseRevision: 1, a: "2030-w43-thu-pm", aDate: D.date("2030-10-24"), b: "2030-w43-sat-am", bDate: D.date("2030-10-26"))), seq: 50)
        let unskip = logged(.sessionUnskipped(SessionUnskippedPayload(week: w44, baseRevision: 1, sessionId: "2030-w44-mon-pm")), seq: 51)
        let overrideCommand = logged(.ruleOverridden(RuleOverriddenPayload(week: w44, baseRevision: 1, sessionId: "2030-w44-wed-am", rule: "two-ambers")), seq: 52)
        let stale = logged(move("2030-w43-sun-pm", from: "2030-10-27", to: "2030-10-26"), seq: 53)
        let snap = try snapshot([swap, unskip, overrideCommand, stale])
        let plan = try XCTUnwrap(snap.plan)

        XCTAssertEqual(plan.day(D.date("2030-10-24"))?.sessions.map(\.id), ["2030-w43-sat-am"])
        XCTAssertEqual(plan.day(D.date("2030-10-26"))?.sessions.map(\.id), ["2030-w43-thu-pm"])
        XCTAssertEqual(plan.day(D.date("2030-10-26"))?.sessions.first?.origin?["kind"]?.stringValue, "swapped")
        XCTAssertEqual(plan.day(D.date("2030-10-26"))?.sessions.first?.origin?["from"]?.stringValue, "2030-10-24")
        XCTAssertEqual(plan.day(D.date("2030-10-28"))?.sessions.first?.status?.known, .planned)

        let previewed = Dictionary(uniqueKeysWithValues: plan.overlay.commands.map { ($0.seq, $0.previewed) })
        XCTAssertEqual(previewed, [50: true, 51: true, 52: false, 53: false],
                       "an override has no preview; the Sunday walk is on Friday, not on 27 October")
        XCTAssertEqual(plan.day(D.date("2030-10-25"))?.sessions.map(\.id), ["2030-w43-sun-pm"], "the stale move changes nothing")
        XCTAssertEqual(plan.overlay.command(id: stale.event.id)?.status, .pending(.savedOnPhone), "still pending: the vault will answer")

        let wed = try self.options("2030-w44-wed-am", snap)
        XCTAssertEqual(wed.block, .waiting)
        XCTAssertEqual(wed.overridableRules, [])
        XCTAssertEqual(wed.withdrawable, [overrideCommand.event.id])
        XCTAssertEqual(builder(snap).sessionDetail(id: "2030-w44-wed-am")?.editing?.latest?.description, "Override the rule two-ambers")
        let seenFromSat = try XCTUnwrap(builder(snap).sessionDetail(id: "2030-w43-sat-am")?.editing?.latest?.description)
        XCTAssertTrue(seenFromSat.hasPrefix("Swap with "), seenFromSat)
        XCTAssertTrue(seenFromSat.hasSuffix("(" + short("2030-10-24") + ")"), seenFromSat)
    }

    // MARK: Recorder round trip

    func testACommandGoesThroughTheRecorderAndComesBackAnswered() async throws {
        let directory = try makeTemporaryDirectory()
        let identity = DeviceIdentityStore(directory: directory, makeID: { VaultDeviceID("ios-0000beef")! })
        try await identity.ensureIdentity(now: t0)
        let recorder = TrainingRecorder(
            log: TrainingEventLog.make(directory: directory),
            identity: identity,
            queue: VaultWriteQueue.make(directory: directory),
            makeID: { _ in "01becdb6-a200-7abc-bd11-2233445566ff" }
        )
        let payload = try PlanEditPolicy.move(sessionID: "2030-w43-sat-am", to: D.date("2030-10-27"), snapshot: try snapshot(), today: D.asOf)
        let event = try await recorder.record(payload, now: t0)
        XCTAssertEqual(event.type, .sessionMoved)

        var edits = await recorder.planEdits()
        XCTAssertEqual(edits.commands.map(\.status), [.pending(.savedOnPhone)])
        let checkIns = await recorder.overlay()
        XCTAssertTrue(checkIns.isEmpty, "a command is not a check-in")

        let transport = RecordingTransport()
        let result = await recorder.drain(transport: transport, now: t0.addingTimeInterval(120))
        XCTAssertEqual(result.delivered.count, 1)
        edits = await recorder.planEdits()
        XCTAssertEqual(edits.commands.map(\.status), [.pending(.sent)])
        let delivered = HubEventCodec.decode(try XCTUnwrap(transport.created.values.first))
        XCTAssertEqual(delivered.events, [event])

        let acks: [String: JSONValue] = [me: .object(["seq": .number(Double(event.seq)), "maxSeq": .number(Double(event.seq))])]
        let outcomes: [JSONValue] = [.object([
            "event": .string(event.id), "deviceId": .string(me), "seq": .number(Double(event.seq)),
            "type": .string("plan.session.moved"), "week": .string("2030-W43"), "sessionId": .string("2030-w43-sat-am"),
            "status": .string("applied"), "reason": .null
        ])]
        edits = await recorder.planEdits(acks: acks, outcomes: outcomes)
        XCTAssertEqual(edits.commands.map(\.status), [.resolved(OpenEnum(PlanOutcomeStatus.applied), reason: nil)])
    }
}
