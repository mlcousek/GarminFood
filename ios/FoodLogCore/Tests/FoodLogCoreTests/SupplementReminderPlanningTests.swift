// SupplementReminderPlanningTests.swift
//
// add-supplements wave 4 (4.1-4.3) and the slot times the wave-3 WIP added:
//   - default / user reminder times and the Today card's clock-preferred slot;
//   - slot reminders: one per slot with items due, skipped once the slot is
//     ticked or when nothing is due, none while the feature is off (4.3),
//     text diffed so a language switch re-plans (diff through
//     `NotificationPlanning.diff`);
//   - restock: once per pack;
//   - the "Taken" action (`SupplementSlotTaking`) against REAL stores on
//     temp files: ticks exactly the slot's due items, twice is idempotent.

import XCTest
@testable import FoodLogCore

final class SupplementReminderPlanningTests: XCTestCase {
    private let today = "2026-09-25"
    private let tomorrow = "2026-09-26"
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("supplement-reminders-\(UUID().uuidString)", isDirectory: true)
    }

    private func product(_ name: String, _ ingredient: IngredientID = .creatine) -> SupplementProduct {
        SupplementProduct(name: name, ingredients: [IngredientAmount(ingredient: ingredient, amount: 5, unit: .g)])
    }

    /// Creatine + D3 in the morning, magnesium in the evening, all daily.
    private func stack() -> (plan: SupplementPlan, creatine: SupplementProduct, d3: SupplementProduct, magnesium: SupplementProduct) {
        let creatine = product("Creatine")
        let d3 = product("D3", .vitaminD)
        let magnesium = product("Magnesium", .magnesium)
        var plan = SupplementPlan(products: [creatine, d3, magnesium])
        plan.setSchedule(SupplementSchedule(slots: [.morning]), for: creatine.id, from: "2026-09-01")
        plan.setSchedule(SupplementSchedule(slots: [.morning]), for: d3.id, from: "2026-09-01")
        plan.setSchedule(SupplementSchedule(slots: [.evening]), for: magnesium.id, from: "2026-09-01")
        return (plan, creatine, d3, magnesium)
    }

    private func record(_ product: SupplementProduct, _ slot: TimeSlot, day: String) -> IntakeRecord {
        IntakeRecord(day: day, productId: product.id, slot: slot, servings: 1, takenAt: now, kind: .planned, recordedOn: day)
    }

    // MARK: - Slot times

    func testDefaultReminderTimes() {
        let plan = SupplementPlan()
        XCTAssertEqual(plan.reminderMinute(for: .morning), 8 * 60)
        XCTAssertEqual(plan.reminderMinute(for: .evening), 21 * 60)
        XCTAssertNil(plan.reminderMinute(for: .preWorkout))
        XCTAssertNil(plan.reminderMinute(for: .withBreakfast))
        XCTAssertEqual(plan.reminderMinute(for: .custom(name: "Lunch", minute: 12 * 60)), 12 * 60)
        XCTAssertNil(plan.reminderMinute(for: .custom(name: "Odd", minute: 5000)))
    }

    func testUserReminderTimesOverrideAndTurnOff() {
        var plan = SupplementPlan()
        plan.setReminderMinute(7 * 60 + 30, for: .morning)
        plan.setReminderMinute(nil, for: .evening)
        plan.setReminderMinute(6 * 60, for: .preWorkout)
        XCTAssertEqual(plan.reminderMinute(for: .morning), 7 * 60 + 30)
        XCTAssertNil(plan.reminderMinute(for: .evening), "explicitly off wins over the default")
        XCTAssertEqual(plan.reminderMinute(for: .preWorkout), 6 * 60)
        plan.setReminderMinute(9 * 60, for: .morning)
        XCTAssertEqual(plan.slotReminders?.filter { $0.slotKey == "morning" }.count, 1)
    }

    func testReminderTimesSurviveEncoding() throws {
        var plan = SupplementPlan()
        plan.setReminderMinute(nil, for: .evening)
        let decoded = try JSONDecoder().decode(SupplementPlan.self, from: JSONEncoder().encode(plan))
        XCTAssertNil(decoded.reminderMinute(for: .evening))
        // A plan file written before slot reminders existed.
        let old = try JSONDecoder().decode(SupplementPlan.self, from: Data(#"{"products":[],"items":[]}"#.utf8))
        XCTAssertNil(old.slotReminders)
        XCTAssertEqual(old.reminderMinute(for: .evening), 21 * 60)
    }

    func testPreferredSlotFollowsTheClock() {
        let plan = SupplementPlan()
        let slots: [TimeSlot] = [.morning, .preWorkout, .evening]
        XCTAssertNil(SupplementSlotTimes.preferredSlot(among: slots, atMinute: 7 * 60, plan: plan))
        XCTAssertEqual(SupplementSlotTimes.preferredSlot(among: slots, atMinute: 12 * 60, plan: plan), .morning)
        XCTAssertEqual(SupplementSlotTimes.preferredSlot(among: slots, atMinute: 22 * 60, plan: plan), .evening)
    }

    /// Spec "Slot variant after the morning".
    func testCurrentSlotAfterTheMorningIsDone() {
        let s = stack()
        let records = [record(s.creatine, .morning, day: today), record(s.d3, .morning, day: today)]
        let checklist = SupplementChecklist(day: today, plan: s.plan, records: records, trainingDays: [])
        let preferred = SupplementSlotTimes.preferredSlot(among: checklist.slots, atMinute: 10 * 60, plan: s.plan)
        XCTAssertEqual(checklist.currentSlot(preferring: preferred), .evening)
        XCTAssertEqual(checklist.entries(in: .evening).map(\.item.productId), [s.magnesium.id])
    }

    func testSlotsInUseAndActiveProducts() {
        var s = stack()
        s.plan.setSchedule(nil, for: s.d3.id, from: today)
        XCTAssertEqual(s.plan.slotsInUse(on: today), [.morning, .evening])
        XCTAssertEqual(s.plan.activeProducts(on: today).map(\.id), [s.creatine.id, s.magnesium.id])
        XCTAssertEqual(s.plan.inactiveProducts(on: today).map(\.id), [s.d3.id])
    }

    // MARK: - Slot reminders (4.1)

    private func planSlots(_ plan: SupplementPlan, records: [IntakeRecord] = [], enabled: Bool = true, nowMinute: Int = 6 * 60) -> [PlannedSupplementReminder] {
        NotificationPlanning.planSupplementSlotReminders(
            isEnabled: enabled,
            plan: plan,
            days: [today, tomorrow],
            records: records,
            trainingDays: [],
            today: today,
            nowMinute: nowMinute
        )
    }

    func testOneReminderPerSlotWithItemsDue() {
        let s = stack()
        let planned = planSlots(s.plan)
        XCTAssertEqual(planned.map(\.id), [
            "slot.\(today).morning", "slot.\(today).evening",
            "slot.\(tomorrow).morning", "slot.\(tomorrow).evening",
        ])
        let morning = planned[0]
        XCTAssertEqual(morning.hour, 8)
        XCTAssertEqual(morning.minute, 0)
        XCTAssertTrue(morning.body.contains("Creatine"))
        XCTAssertTrue(morning.body.contains("D3"))
        XCTAssertEqual(morning.userInfo, SupplementSlotTaking.userInfo(day: today, slotKey: "morning"))
    }

    /// Spec "Slot completed early".
    func testCompletedSlotIsSkipped() {
        let s = stack()
        let planned = planSlots(s.plan, records: [record(s.magnesium, .evening, day: today)])
        XCTAssertFalse(planned.map(\.id).contains("slot.\(today).evening"))
        XCTAssertTrue(planned.map(\.id).contains("slot.\(tomorrow).evening"))
    }

    func testPartlyTickedSlotNamesOnlyWhatIsLeft() {
        let s = stack()
        let planned = planSlots(s.plan, records: [record(s.creatine, .morning, day: today)])
        let morning = planned.first { $0.id == "slot.\(today).morning" }
        XCTAssertNotNil(morning)
        XCTAssertFalse(morning?.body.contains("Creatine") ?? true)
        XCTAssertTrue(morning?.body.contains("D3") ?? false)
    }

    /// Spec "Nothing due in a slot": pre-workout on training days only, and
    /// a slot with no reminder time is never planned.
    func testNothingDueOrNoTimeMeansNoReminder() {
        var s = stack()
        let caffeine = product("Caffeine", .caffeine)
        s.plan.products.append(caffeine)
        s.plan.setSchedule(SupplementSchedule(slots: [.preWorkout], pattern: .trainingDays), for: caffeine.id, from: "2026-09-01")
        s.plan.setReminderMinute(17 * 60, for: .preWorkout)
        XCTAssertFalse(planSlots(s.plan).contains { $0.id.hasSuffix(".preWorkout") }, "rest day")

        let withTraining = NotificationPlanning.planSupplementSlotReminders(
            isEnabled: true, plan: s.plan, days: [today], records: [], trainingDays: [today], today: today, nowMinute: 0
        )
        XCTAssertTrue(withTraining.contains { $0.id == "slot.\(today).preWorkout" })

        s.plan.setReminderMinute(nil, for: .preWorkout)
        let off = NotificationPlanning.planSupplementSlotReminders(
            isEnabled: true, plan: s.plan, days: [today], records: [], trainingDays: [today], today: today, nowMinute: 0
        )
        XCTAssertFalse(off.contains { $0.id.hasSuffix(".preWorkout") })
    }

    func testTodaysPassedReminderIsLeftOut() {
        let s = stack()
        let planned = planSlots(s.plan, nowMinute: 12 * 60)
        XCTAssertFalse(planned.map(\.id).contains("slot.\(today).morning"))
        XCTAssertTrue(planned.map(\.id).contains("slot.\(today).evening"))
        XCTAssertTrue(planned.map(\.id).contains("slot.\(tomorrow).morning"))
    }

    /// Task 4.3: disabling removes every pending supplement reminder via the
    /// scheduler's diff.
    func testDisabledPlansNothingAndTheDiffRemovesPending() {
        let s = stack()
        let prefix = "supplement."
        let pending = Dictionary(uniqueKeysWithValues: planSlots(s.plan).map { (prefix + $0.id, $0.text) })
        XCTAssertFalse(pending.isEmpty)

        let planned = planSlots(s.plan, enabled: false)
        XCTAssertTrue(planned.isEmpty)
        XCTAssertTrue(NotificationPlanning.planSupplementRestockReminders(isEnabled: false, plan: s.plan, records: [], trainingDays: [], today: today).isEmpty)

        let diff = NotificationPlanning.diff(planned: [:], pending: pending, ownedPrefix: prefix)
        XCTAssertEqual(diff.toRemove, pending.keys.sorted())
        XCTAssertTrue(diff.toAdd.isEmpty)
    }

    /// Spec "Language switch": the same id with different text is re-added.
    func testChangedTextIsReplanned() {
        let s = stack()
        let prefix = "supplement."
        let planned = Dictionary(uniqueKeysWithValues: planSlots(s.plan).map { (prefix + $0.id, $0.text) })
        var pending = planned
        let first = planned.keys.sorted()[0]
        pending[first] = NotificationPlanning.NotificationText(title: "Ranní doplňky", body: "Vezmi si: Creatine, D3")
        let diff = NotificationPlanning.diff(planned: planned, pending: pending, ownedPrefix: prefix)
        XCTAssertEqual(diff.toAdd, [first])
        XCTAssertTrue(diff.toRemove.isEmpty)
    }

    // MARK: - Restock (4.1)

    /// Spec "Running low": one reminder at the lead time, none again until
    /// the stock is refilled.
    func testRestockOncePerPack() {
        var omega = product("Omega-3", .omega3EPA_DHA)
        omega.stockServings = 7
        omega.stockSetOn = today
        var plan = SupplementPlan(products: [omega])
        plan.setSchedule(SupplementSchedule(slots: [.morning]), for: omega.id, from: "2026-09-01")

        let first = NotificationPlanning.planSupplementRestockReminders(isEnabled: true, plan: plan, records: [], trainingDays: [], today: today)
        XCTAssertEqual(first.map(\.id), ["restock.\(omega.id.uuidString).\(today)"])
        XCTAssertEqual(first.first?.kind, .restock(productId: omega.id))
        XCTAssertTrue(first.first?.title.contains("Omega-3") ?? false)
        XCTAssertTrue(first.first?.userInfo.isEmpty ?? false)

        plan.products[0].restockRemindedFor = today
        XCTAssertTrue(NotificationPlanning.planSupplementRestockReminders(isEnabled: true, plan: plan, records: [], trainingDays: [], today: today).isEmpty)

        // Plenty of stock: nothing.
        plan.products[0].restockRemindedFor = nil
        plan.products[0].stockServings = 60
        XCTAssertTrue(NotificationPlanning.planSupplementRestockReminders(isEnabled: true, plan: plan, records: [], trainingDays: [], today: today).isEmpty)
    }

    // MARK: - "Taken" action (4.2)

    func testUserInfoRoundTrip() {
        let info: [AnyHashable: Any] = SupplementSlotTaking.userInfo(day: today, slotKey: "custom:Lunch")
        let parsed = SupplementSlotTaking.parse(info)
        XCTAssertEqual(parsed?.day, today)
        XCTAssertEqual(parsed?.slotKey, "custom:Lunch")
        XCTAssertNil(SupplementSlotTaking.parse(["supplementDay": "not a day", "supplementSlot": "morning"]))
        XCTAssertNil(SupplementSlotTaking.parse([:]))
    }

    /// Spec "Taken from the lock screen" + "Double tap".
    func testTakenActionTicksTheSlotOnceWithRealStores() async throws {
        let directory = tempDirectory()
        let planStore = SupplementPlanStore(fileURL: directory.appendingPathComponent("supplement-plan.json"))
        let intakeStore = SupplementIntakeStore(directoryURL: directory.appendingPathComponent("SupplementIntake", isDirectory: true))
        let s = stack()
        for product in s.plan.products { try await planStore.upsertProduct(product) }
        try await planStore.setSchedule(SupplementSchedule(slots: [.morning]), for: s.creatine.id, from: "2026-09-01")
        try await planStore.setSchedule(SupplementSchedule(slots: [.morning]), for: s.d3.id, from: "2026-09-01")
        try await planStore.setSchedule(SupplementSchedule(slots: [.evening]), for: s.magnesium.id, from: "2026-09-01")

        let first = try await SupplementSlotTaking.take(slotKey: "morning", on: today, planStore: planStore, intakeStore: intakeStore, trainingDays: [], today: today, now: now)
        let second = try await SupplementSlotTaking.take(slotKey: "morning", on: today, planStore: planStore, intakeStore: intakeStore, trainingDays: [], today: today, now: now)

        XCTAssertEqual(Set(first.map(\.productId)), [s.creatine.id, s.d3.id])
        XCTAssertEqual(first.map(\.id), second.map(\.id), "the second delivery keeps the first records")
        let stored = try await SupplementIntakeStore(directoryURL: directory.appendingPathComponent("SupplementIntake", isDirectory: true)).records(forDay: today)
        XCTAssertEqual(stored.count, 2)
        XCTAssertTrue(stored.allSatisfy { $0.slot == .morning && $0.kind == .planned })

        let plan = try await planStore.plan()
        let checklist = SupplementChecklist(day: today, plan: plan, records: stored, trainingDays: [])
        XCTAssertTrue(checklist.isComplete(.morning))
        XCTAssertFalse(checklist.isComplete(.evening))
    }

    func testTakingASlotWithNothingDueWritesNothing() async throws {
        let directory = tempDirectory()
        let planStore = SupplementPlanStore(fileURL: directory.appendingPathComponent("supplement-plan.json"))
        let intakeStore = SupplementIntakeStore(directoryURL: directory.appendingPathComponent("SupplementIntake", isDirectory: true))
        let records = try await SupplementSlotTaking.take(slotKey: "evening", on: today, planStore: planStore, intakeStore: intakeStore, trainingDays: [], today: today, now: now)
        XCTAssertTrue(records.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("SupplementIntake/2026-09.json").path))
    }

    // MARK: - Texts

    func testFormatUsesLocaleDecimals() {
        XCTAssertEqual(SupplementFormat.amount(2.5, unit: .g, locale: Locale(identifier: "cs_CZ")), "2,5 g")
        XCTAssertEqual(SupplementFormat.amount(1000, unit: .iu, locale: Locale(identifier: "en_US")), "1000 IU")
        XCTAssertEqual(SupplementFormat.amount(75, unit: .ug, locale: Locale(identifier: "en_US")), "75 µg")
        XCTAssertEqual(SupplementFormat.clock(minute: 21 * 60 + 5), "21:05")
    }
}
