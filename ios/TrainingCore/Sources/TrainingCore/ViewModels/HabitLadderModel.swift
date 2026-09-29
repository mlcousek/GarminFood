// HabitLadderModel.swift
//
// Where each habit of the ladder stands (spec "The habit ladder shows where
// each habit stands"; design D10): every step in order with its state
// (active, next, later), its why, its start date or earliest start, its
// schedule in words, the 14-day window as "25 of 28 · 89 %" against the
// gate ("over 9 recorded days" when fewer were recorded, "not recorded yet"
// when the vault has nothing), and "Gate met: ..." where the vault says so
// (it sets `gateMet` only on the highest active step).
//
// Read-only: starting, pausing or ticking a habit stays a desk decision.
//
// Depended on by: the app's HabitLadderView. Tests: PlanBuilderTests.

import Foundation

public struct HabitLadderRowModel: Equatable, Sendable, Identifiable {
    public let id: String
    public let step: Int?
    public let icon: String?
    public let label: String
    public let state: HabitState?
    public let stateText: String?
    public let dose: String?
    public let why: String?
    /// "Started 20 Sept" / "Earliest start 28 Oct".
    public let dateText: String?
    public let schedule: String?
    public let adherence: String
    public let fraction: Double?
    public let gateMetText: String?
}

public struct HabitLadderModel: Equatable, Sendable {
    /// "Gate: 80 % · 14-day window".
    public let gateText: String?
    public let rows: [HabitLadderRowModel]
    /// "No habits in this plan".
    public let emptyText: String?
}

public extension PlanBuilder {
    func habitLadder() -> HabitLadderModel {
        let text = format.text
        guard let snapshot = source.snapshot else {
            return HabitLadderModel(gateText: nil, rows: [], emptyText: text(.habitsNone))
        }
        let habits = snapshot.habits
        var gateText: String?
        if let pct = habits.gate.adherencePct {
            gateText = text.format(.habitGate, pct, habits.gate.windowDays ?? 14)
        }
        let rows = habits.ladder.map { habit -> HabitLadderRowModel in
            var dateText: String?
            if let started = habit.started {
                dateText = text.format(.habitStarted, format.dates.dayMonth(started))
            } else if let earliest = habit.earliest {
                dateText = text.format(.habitEarliest, format.dates.dayMonth(earliest))
            }
            return HabitLadderRowModel(
                id: habit.id,
                step: habit.step,
                icon: habit.icon,
                label: habit.label.resolvedText(format.language) ?? habit.id,
                state: habit.state?.known,
                stateText: text.habitStateName(habit.state),
                dose: habit.dose.resolvedText(format.language),
                why: habit.why.resolvedText(format.language),
                dateText: dateText,
                schedule: format.schedule.line(habit.schedule),
                adherence: HabitText.adherence(habit.window14, gate: habits.gate, text: text),
                fraction: habit.window14?.pct.map { Double(min(max($0, 0), 100)) / 100 },
                gateMetText: habit.gateMet == true ? text(.habitGateMet) : nil
            )
        }
        return HabitLadderModel(gateText: gateText, rows: rows, emptyText: rows.isEmpty ? text(.habitsNone) : nil)
    }
}
