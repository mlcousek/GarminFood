// HabitsCardModel.swift
//
// Today's Habits card as a pure model (polish-training-today D2, spec
// training-today "The habit ladder is tracked from Today"). The owner could
// not track the ladder: the old card listed only the habits the plan
// expected that day and hid itself otherwise, and the ladder was one tap
// behind it. This card shows whenever the plan has a ladder:
//
//   - where he stands: "Step 2 of 6" (the highest active step);
//   - the active habits (plus any the day expects), each with its 14-day
//     window against the gate and, when the plan expects it on the shown
//     day, the on/off tick of add-training-checkins (A42); an active habit
//     the day doesn't expect says "Not on today's plan" and has no tick;
//   - the day's progress: "1 of 2 done today", from the phone's latest
//     ticks over the projection's counts (`TrainingSnapshot.habitDone`);
//   - the next step and what unlocks it: "Gate met: ..." where the vault
//     says so, else "Unlocks when <current> holds 80 % over a 14-day
//     window", and its earliest start.
//
// The phone never decides a gate: `gateMet`, `window14` and the states are
// read from the projection. Rows reuse `HabitRowModel`
// (TodayTrainingModel.swift), so the tick and adherence rules stay one.
//
// Depended on by: the app's HabitsTodayCard (Training/TrainingTodayCards
// .swift). Tests: TodayBuilderTests.

import Foundation

public struct HabitNextStepModel: Equatable, Sendable, Identifiable {
    public let id: String
    public let icon: String?
    public let label: String
    /// "Next step: Stretch after easy runs".
    public let title: String
    /// "Gate met: ..." or "Unlocks when Gym twice a week holds 80 % over a
    /// 14-day window"; `nil` without a gate.
    public let unlockText: String?
    /// "Earliest start 28 Oct".
    public let earliestText: String?
    public let accessibilityLabel: String
}

public struct HabitsCardModel: Equatable, Sendable {
    public let date: LocalDate
    /// "Step 2 of 6"; `nil` when no step is active yet.
    public let stepText: String?
    /// Ladder order: the active habits and the day's expected ones.
    public let rows: [HabitRowModel]
    /// Expected on the shown day, and how many of those are done.
    public let expectedCount: Int
    public let doneCount: Int
    /// "1 of 2 done today"; `nil` when the day expects none.
    public let progressText: String?
    public let next: HabitNextStepModel?
}

public extension TodayTrainingBuilder {
    /// The Habits card for `date`; `nil` (card hidden) only when the plan
    /// has no habit ladder.
    func habitsCard(on date: LocalDate) -> HabitsCardModel? {
        guard let snapshot = source.snapshot else { return nil }
        let habits = snapshot.habits
        guard !habits.ladder.isEmpty else { return nil }
        let text = format.text
        let day = snapshot.plan?.day(date)
        let expected = Set(day?.habitsExpected ?? [])

        let shown = habits.ladder.filter { $0.state?.known == .active || expected.contains($0.id) }
        let rows = shown.map { habit -> HabitRowModel in
            let scheduled = expected.contains(habit.id)
            return habitRow(habit, day: scheduled ? day : nil, gate: habits.gate, snapshot: snapshot, scheduled: scheduled)
        }
        let scheduledIDs = shown.map(\.id).filter { expected.contains($0) }
        let done = scheduledIDs.filter { snapshot.habitDone($0, on: date).done }.count
        let progress = scheduledIDs.isEmpty ? nil : text.format(.habitsDoneToday, done, scheduledIDs.count)

        let currentIndex = habits.ladder.lastIndex { $0.state?.known == .active }
        let stepText = currentIndex.map { text.format(.habitStepOf, $0 + 1, habits.ladder.count) }
        let current = currentIndex.map { habits.ladder[$0] }

        var next: HabitNextStepModel?
        if let upcoming = habits.ladder.first(where: { $0.state?.known == .next }) {
            let label = upcoming.label.resolvedText(format.language) ?? upcoming.id
            var unlock: String?
            if current?.gateMet == true {
                unlock = text(.habitGateMet)
            } else if let current, let pct = habits.gate.adherencePct {
                let currentLabel = current.label.resolvedText(format.language) ?? current.id
                unlock = text.format(.habitUnlockWhen, currentLabel, pct, habits.gate.windowDays ?? 14)
            }
            let earliest = upcoming.earliest.map { text.format(.habitEarliest, format.dates.dayMonth($0)) }
            let title = text.format(.habitNextStep, label)
            next = HabitNextStepModel(
                id: upcoming.id,
                icon: upcoming.icon,
                label: label,
                title: title,
                unlockText: unlock,
                earliestText: earliest,
                accessibilityLabel: [title, unlock, earliest].compactMap { $0 }.joined(separator: ". ")
            )
        }

        return HabitsCardModel(
            date: date,
            stepText: stepText,
            rows: rows,
            expectedCount: scheduledIDs.count,
            doneCount: done,
            progressText: progress,
            next: next
        )
    }
}
