// CheckInBuilderTests.swift
//
// What the screens show once the app may record (add-training-checkins
// design D5, D6, D8; spec training-checkins), on the vault's example
// fixture: the check-in row (traffic-light day, rest day, hidden without a
// device id), the phone's light reaching the option cards and the light
// line, habit toggles (the phone's tick over the vault's count), the
// session rating, Czech text, and the training reminders.

import XCTest
@testable import TrainingCore

final class CheckInBuilderTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_918_951_651)

    private func logged(_ payload: HubEventPayload, seq: Int, segment: UUID? = nil) -> LoggedEvent {
        LoggedEvent(
            event: HubEvent(id: "id-\(seq)", deviceId: "ios-0000beef", seq: seq, at: "t", payload: payload),
            recordedAt: t0.addingTimeInterval(Double(seq)),
            segmentID: segment
        )
    }

    private func snapshot(_ events: [LoggedEvent] = [], enabled: Bool = true, unsent: Set<UUID> = [], data: Data? = nil) throws -> TrainingSnapshot {
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
        return TrainingSnapshot(
            projection: projection,
            checkIns: CheckInOverlay.fold(events, unsentSegments: unsent),
            capabilities: .checkIns(enabled: enabled)
        )
    }

    private func today(_ snapshot: TrainingSnapshot, _ language: TrainingLanguage = .english) -> TodayTrainingBuilder {
        TodayTrainingBuilder(source: .loaded(snapshot), language: language)
    }

    private func amber(_ date: String = "2030-10-23") -> HubEventPayload {
        .morningCheckIn(MorningCheckInPayload(date: D.date(date), light: .amberLight, sessionId: "2030-w43-wed-am"))
    }

    // MARK: Check-in row

    /// The example with this morning's vault check-in removed.
    private func withoutTodaysLight() throws -> Data {
        try Fixtures.mutatedExample { object in
            try Fixtures.mutateDay(&object, week: 2, day: 2) { day in
                day["light"] = NSNull()
                day["lightSource"] = NSNull()
            }
        }
    }

    func testCheckInRowOnATrafficLightDay() throws {
        let model = today(try snapshot(data: try withoutTodaysLight())).trainingDay(on: D.asOf)
        let row = try XCTUnwrap(model.checkIn)
        XCTAssertEqual(row.title, "Morning check-in")
        XCTAssertEqual(row.sessionID, "2030-w43-wed-am")
        XCTAssertEqual(row.buttons.map(\.letter), ["G", "A", "R"])
        XCTAssertEqual(row.buttons.map(\.name), ["Green", "Amber", "Red"])
        XCTAssertEqual(row.buttons.map(\.meaning), ["Planned session", "Easier", "Alternative"])
        XCTAssertEqual(row.buttons[0].accessibilityLabel, "Morning check-in Green, Planned session")
        XCTAssertNil(row.selected)
        XCTAssertTrue(row.buttons.allSatisfy { !$0.isSelected })
        XCTAssertNil(row.deliveryLine)
        // The option cards still only open the detail.
        XCTAssertEqual(model.sessions[0].options[1].action, .openDetail(sessionID: "2030-w43-wed-am", option: "A"))
    }

    func testTheVaultsCheckInIsShownAsChosen() throws {
        // The example's own amber check-in (lightSource "checkin").
        let row = try XCTUnwrap(today(try snapshot()).trainingDay(on: D.asOf).checkIn)
        XCTAssertEqual(row.selected, .amberLight)
        XCTAssertNil(row.deliveryLine, "not the phone's own event")
        // A light inferred from the executed option is not a check-in.
        let inferred = try XCTUnwrap(today(try snapshot()).trainingDay(on: D.date("2030-10-15")).checkIn)
        XCTAssertNil(inferred.selected)
    }

    func testCheckInRowOnARestDay() throws {
        let row = try XCTUnwrap(today(try snapshot()).trainingDay(on: D.date("2030-10-27")).checkIn)
        XCTAssertNil(row.sessionID)
        XCTAssertEqual(row.buttons.count, 3)
    }

    func testNoCheckInWithoutADeviceID() throws {
        let builder = today(try snapshot(enabled: false))
        XCTAssertNil(builder.trainingDay(on: D.asOf).checkIn)
        XCTAssertEqual(builder.habits(on: D.asOf).map(\.tick), [.displayOnly])
    }

    func testNoCheckInOutsideThePlan() throws {
        XCTAssertNil(today(try snapshot()).trainingDay(on: D.date("2031-06-01")).checkIn)
    }

    func testThePhonesLightReachesTheCards() throws {
        let model = today(try snapshot([logged(amber(), seq: 1)])).trainingDay(on: D.asOf)
        let row = try XCTUnwrap(model.checkIn)
        XCTAssertEqual(row.selected, .amberLight)
        XCTAssertEqual(row.buttons.map(\.isSelected), [false, true, false])
        XCTAssertEqual(row.deliveryLine, "Saved on phone")
        XCTAssertEqual(model.lightLine, "Morning check: Amber")
        XCTAssertEqual(model.sessions[0].options.map(\.highlight), [nil, .morningLight, nil])
    }

    func testLatestCheckInWinsAndShowsSent() throws {
        let segment = UUID()
        let green = HubEventPayload.morningCheckIn(MorningCheckInPayload(date: D.asOf, light: .greenLight, sessionId: "2030-w43-wed-am"))
        let model = today(try snapshot([logged(amber(), seq: 1, segment: segment), logged(green, seq: 2, segment: segment)])).trainingDay(on: D.asOf)
        XCTAssertEqual(model.checkIn?.selected, .greenLight)
        XCTAssertEqual(model.checkIn?.deliveryLine, "Sent")
        XCTAssertEqual(model.sessions[0].options.map(\.highlight), [.morningLight, nil, nil])
    }

    func testTheLightAlsoReachesThePlanTab() throws {
        let red = HubEventPayload.morningCheckIn(MorningCheckInPayload(date: D.asOf, light: .redLight, sessionId: "2030-w43-wed-am"))
        let checkedIn = try snapshot([logged(red, seq: 1)])
        let plan = PlanBuilder(source: .loaded(checkedIn), language: .english, today: D.asOf)
        let detail = try XCTUnwrap(plan.sessionDetail(id: "2030-w43-wed-am"))
        XCTAssertEqual(detail.options[detail.initialOptionIndex].code, "R", "the detail opens on the phone's checked-in option")
    }

    func testCzechCheckIn() throws {
        let row = try XCTUnwrap(today(try snapshot([logged(amber(), seq: 1)]), .czech).trainingDay(on: D.asOf).checkIn)
        XCTAssertEqual(row.title, "Ranní kontrola")
        XCTAssertEqual(row.buttons.map(\.name), ["Zelená", "Oranžová", "Červená"])
        XCTAssertEqual(row.deliveryLine, "Uloženo v telefonu")
        XCTAssertEqual(row.buttons[1].accessibilityLabel, "Ranní kontrola Oranžová, Lehčí")
    }

    // MARK: Habits

    func testHabitTicksFollowTheVaultCount() throws {
        // 2030-10-23 expects "holds" and the vault counted one.
        let rows = today(try snapshot()).habits(on: D.asOf)
        XCTAssertEqual(rows.map(\.id), ["holds"])
        XCTAssertEqual(rows[0].tick, .tickable(done: true, pending: false))
        // 2030-10-24: nothing known yet.
        let tomorrow = today(try snapshot()).habits(on: D.date("2030-10-24"))
        XCTAssertEqual(tomorrow.map(\.tick), [.tickable(done: false, pending: false), .tickable(done: false, pending: false)])
    }

    func testThePhonesTickWins() throws {
        let off = HubEventPayload.habitTick(HabitTickPayload(date: D.asOf, habitId: "holds", done: false))
        let on = HubEventPayload.habitTick(HabitTickPayload(date: D.date("2030-10-24"), habitId: "gym", done: true))
        let builder = today(try snapshot([logged(off, seq: 1), logged(on, seq: 2)]))
        XCTAssertEqual(builder.habits(on: D.asOf)[0].tick, .tickable(done: false, pending: true))
        let tomorrow = builder.habits(on: D.date("2030-10-24"))
        XCTAssertEqual(tomorrow.first { $0.id == "gym" }?.tick, .tickable(done: true, pending: true))
    }

    /// polish-training-today D2: the Habits card ticks what the day
    /// expects, counts the phone's latest tick, and never ticks the rest.
    func testHabitsCardTicksAndProgress() throws {
        let off = HubEventPayload.habitTick(HabitTickPayload(date: D.asOf, habitId: "holds", done: false))
        let card = try XCTUnwrap(today(try snapshot([logged(off, seq: 1)])).habitsCard(on: D.asOf))
        XCTAssertEqual(card.rows.map(\.id), ["holds", "gym"])
        XCTAssertEqual(card.rows[0].tick, .tickable(done: false, pending: true))
        XCTAssertEqual(card.rows[1].tick, .displayOnly, "gym is not expected on Wednesday")
        XCTAssertEqual(card.doneCount, 0)
        XCTAssertEqual(card.progressText, "0 of 1 done today")

        let tomorrow = try XCTUnwrap(today(try snapshot()).habitsCard(on: D.date("2030-10-24")))
        XCTAssertEqual(tomorrow.rows.map(\.tick), [.tickable(done: false, pending: false), .tickable(done: false, pending: false)])
        XCTAssertEqual(tomorrow.progressText, "0 of 2 done today")
    }

    // MARK: Rating

    func testSessionRating() throws {
        let segment = UUID()
        let rpe = HubEventPayload.sessionRPE(SessionRPEPayload(date: D.date("2030-10-22"), sessionId: "2030-w43-tue-am", rpe: 6))
        let note = HubEventPayload.sessionNote(SessionNotePayload(date: D.date("2030-10-22"), sessionId: "2030-w43-tue-am", text: "Calf tight"))
        let rated = try snapshot([logged(rpe, seq: 1, segment: segment), logged(note, seq: 2)])
        let plan = PlanBuilder(source: .loaded(rated), language: .english, today: D.asOf)
        let rating = try XCTUnwrap(plan.sessionDetail(id: "2030-w43-tue-am")?.rating)
        XCTAssertEqual(rating.sessionID, "2030-w43-tue-am")
        XCTAssertEqual(rating.date, D.date("2030-10-22"))
        XCTAssertEqual(rating.rpe, 6)
        XCTAssertEqual(rating.rpeDeliveryLine, "Sent")
        XCTAssertEqual(rating.note, "Calf tight")
        XCTAssertEqual(rating.noteDeliveryLine, "Saved on phone")

        let empty = try XCTUnwrap(plan.sessionDetail(id: "2030-w43-thu-pm")?.rating)
        XCTAssertNil(empty.rpe)
        XCTAssertNil(empty.note)

        let readOnly = PlanBuilder(source: .loaded(try snapshot(enabled: false)), language: .english, today: D.asOf)
        XCTAssertNil(readOnly.sessionDetail(id: "2030-w43-tue-am")?.rating)
    }

    func testRatingFallsBackToTheVaultsFeedback() throws {
        let plan = PlanBuilder(source: .loaded(try snapshot()), language: .english, today: D.asOf)
        let rating = try XCTUnwrap(plan.sessionDetail(id: "2030-w43-tue-am")?.rating)
        XCTAssertEqual(rating.rpe, 7)
        XCTAssertEqual(rating.note, "Calf tight on the last repeat, eased off.")
        XCTAssertNil(rating.rpeDeliveryLine)
        XCTAssertNil(rating.noteDeliveryLine)
    }

    // MARK: Reminders

    private let prague = TimeZone(identifier: "Europe/Prague")!
    /// 2030-10-23 00:00 in Prague.
    private let midnight = Date(timeIntervalSince1970: 1_918_936_800)

    func testRemindersForTodayAndTomorrow() throws {
        let reminders = TrainingReminderPlanner.plan(snapshot: try snapshot(data: try withoutTodaysLight()), today: D.asOf, now: midnight, timeZone: prague, language: .english)
        // The 23rd: a G/A/R day without a light; its one habit already done.
        // The 24th: no options; two habits unknown.
        XCTAssertEqual(reminders.map(\.id), ["checkin.2030-10-23", "habits.2030-10-24"])
        XCTAssertEqual(reminders[0].title, "How do you feel today?")
        XCTAssertEqual(reminders[0].hour, 4)
        XCTAssertEqual(reminders[0].minute, 5)
        XCTAssertEqual(reminders[1].title, "Evening habits")
        let fire = try XCTUnwrap(TrainingReminderPlanner.fireDate(reminders[0], timeZone: prague))
        XCTAssertEqual(fire, Date(timeIntervalSince1970: 1_918_951_500)) // 02:05Z
    }

    func testCheckingInRemovesTheMorningReminder() throws {
        let local = TrainingReminderPlanner.plan(snapshot: try snapshot([logged(amber(), seq: 1)], data: try withoutTodaysLight()), today: D.asOf, now: midnight, timeZone: prague, language: .english)
        XCTAssertEqual(local.map(\.id), ["habits.2030-10-24"])
        // The vault's own check-in counts too (the example's amber).
        let vault = TrainingReminderPlanner.plan(snapshot: try snapshot(), today: D.asOf, now: midnight, timeZone: prague, language: .english)
        XCTAssertEqual(vault.map(\.id), ["habits.2030-10-24"])
    }

    func testPastRemindersAndReadOnlyPlanNothing() throws {
        // 05:00 in Prague: the 04:05 reminder has passed.
        let late = Date(timeIntervalSince1970: 1_918_954_800)
        let reminders = TrainingReminderPlanner.plan(snapshot: try snapshot(), today: D.asOf, now: late, timeZone: prague, language: .czech)
        XCTAssertEqual(reminders.map(\.id), ["habits.2030-10-24"])
        XCTAssertEqual(reminders[0].title, "Večerní návyky")
        XCTAssertEqual(TrainingReminderPlanner.plan(snapshot: try snapshot(enabled: false), today: D.asOf, now: midnight, timeZone: prague, language: .english), [])
        XCTAssertEqual(TrainingReminderPlanner.plan(snapshot: nil, today: D.asOf, now: midnight, timeZone: prague, language: .english), [])
    }
}
