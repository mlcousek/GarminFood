// TrainingSnapshot.swift
//
// What every builder reads instead of the raw file (design D8), so later
// changes extend the screens instead of rewriting them:
//
//   - `EffectivePlan` = the selected phase's weeks (+) a `PendingOverlay`.
//     The overlay is always empty here; add-plan-editing fills it with the
//     phone's unacknowledged commands, and every screen then shows the
//     moved or skipped session with its pending badge without a builder
//     change;
//   - `TrainingCapabilities` is all `false` here; add-training-checkins
//     turns on check-ins and habit ticks, and the option cards' action goes
//     from `.openDetail` to `.checkIn`.
//
// Lookups across the season live here too (a week's own phase by
// `phaseId`, outline rows of every phase, races), so the builders never
// walk the file themselves.
//
// Depended on by: every builder, the app's TrainingModel. Tests: through
// the builder tests.

import Foundation

/// The phone's pending commands (add-plan-editing). Empty in this change.
public struct PendingOverlay: Equatable, Sendable {
    public static let empty = PendingOverlay()

    public init() {}

    public var isEmpty: Bool { true }
}

/// What the app may do beyond reading (design D8). All `false` here.
public struct TrainingCapabilities: Equatable, Sendable {
    public var canCheckIn: Bool
    public var canTickHabits: Bool
    public var canEditPlan: Bool
    public var canRateSession: Bool

    public static let readOnly = TrainingCapabilities(canCheckIn: false, canTickHabits: false, canEditPlan: false, canRateSession: false)

    public init(canCheckIn: Bool, canTickHabits: Bool, canEditPlan: Bool, canRateSession: Bool) {
        self.canCheckIn = canCheckIn
        self.canTickHabits = canTickHabits
        self.canEditPlan = canEditPlan
        self.canRateSession = canRateSession
    }
}

/// The selected phase as the screens see it: the file's weeks with the
/// overlay applied (a no-op until add-plan-editing).
public struct EffectivePlan: Equatable, Sendable {
    public let plan: Plan
    public let overlay: PendingOverlay

    public init(plan: Plan, overlay: PendingOverlay = .empty) {
        self.plan = plan
        self.overlay = overlay
    }

    public var weeks: [Week] { plan.weeks }

    public func week(_ isoWeek: ISOWeek) -> Week? {
        weeks.first { $0.week == isoWeek }
    }

    public func week(containing date: LocalDate) -> Week? {
        weeks.first { $0.from <= date && date <= $0.to } ?? week(ISOWeek(containing: date))
    }

    public func day(_ date: LocalDate) -> Day? {
        week(containing: date)?.day(date)
    }
}

public struct TrainingSnapshot: Equatable, Sendable {
    public let asOf: LocalDate?
    public let athlete: Athlete
    public let season: Season?
    public let plan: EffectivePlan?
    public let workouts: [String: Workout]
    public let tests: [TestHistory]
    public let habits: Habits
    public let freshness: TrainingFreshness
    public let capabilities: TrainingCapabilities

    public init(
        asOf: LocalDate?,
        athlete: Athlete,
        season: Season?,
        plan: EffectivePlan?,
        workouts: [String: Workout],
        tests: [TestHistory],
        habits: Habits,
        freshness: TrainingFreshness = TrainingFreshness(),
        capabilities: TrainingCapabilities = .readOnly
    ) {
        self.asOf = asOf
        self.athlete = athlete
        self.season = season
        self.plan = plan
        self.workouts = workouts
        self.tests = tests
        self.habits = habits
        self.freshness = freshness
        self.capabilities = capabilities
    }

    /// From a decoded projection, with an empty overlay.
    public init(projection: Projection, freshness: TrainingFreshness = TrainingFreshness(), overlay: PendingOverlay = .empty) {
        self.init(
            asOf: projection.asOf,
            athlete: projection.athlete,
            season: projection.season,
            plan: projection.plan.map { EffectivePlan(plan: $0, overlay: overlay) },
            workouts: projection.workouts,
            tests: projection.tests,
            habits: projection.habits,
            freshness: freshness
        )
    }

    // MARK: Lookups

    public var zoneMapper: HRZoneMapper { HRZoneMapper(zones: athlete.hrZones) }

    /// Every phase the file knows: the season's, else just the plan's.
    public var phases: [PhaseSummary] {
        if let phases = season?.phases, !phases.isEmpty { return phases }
        return plan.map { [$0.plan.phase] } ?? []
    }

    public func phase(id: String?) -> PhaseSummary? {
        guard let id else { return nil }
        if let phase = phases.first(where: { $0.id == id }) { return phase }
        if let plan, plan.plan.phase.id == id { return plan.plan.phase }
        return nil
    }

    /// The phase whose period contains `date`.
    public func phase(containing date: LocalDate) -> PhaseSummary? {
        phases.first { $0.period?.contains(date) ?? false }
    }

    /// The outline row for `week` from whichever phase has one.
    public func outlineRow(for week: ISOWeek) -> (phase: PhaseSummary, row: OutlineWeek)? {
        for phase in phases {
            if let row = phase.outlineRow(for: week) { return (phase, row) }
        }
        if let plan, let row = plan.plan.phase.outlineRow(for: week) { return (plan.plan.phase, row) }
        return nil
    }

    /// The span Plan pages across: the season's period, else the plan's,
    /// widened to include every written week.
    public var pagingRange: ClosedRange<ISOWeek>? {
        var low: ISOWeek?
        var high: ISOWeek?
        func include(_ week: ISOWeek) {
            if low.map({ week < $0 }) ?? true { low = week }
            if high.map({ week > $0 }) ?? true { high = week }
        }
        let period = season?.period ?? plan?.plan.period
        if let from = period?.from { include(ISOWeek(containing: from)) }
        if let to = period?.to { include(ISOWeek(containing: to)) }
        for phase in phases {
            for row in phase.outline { include(row.week) }
        }
        for week in plan?.weeks ?? [] { include(week.week) }
        guard let lower = low, let upper = high else { return nil }
        return lower...upper
    }

    public var races: [Race] { season?.races ?? [] }

    public func races(on date: LocalDate) -> [Race] {
        races.filter { $0.date == date }
    }

    public func race(id: String?) -> Race? {
        guard let id else { return nil }
        return races.first { $0.id == id }
    }

    /// The workout an option or session points at.
    public func workout(_ id: String?) -> Workout? {
        guard let id else { return nil }
        return workouts[id]
    }

    public func testHistory(workout id: String?) -> TestHistory? {
        guard let id else { return nil }
        return tests.first { $0.workout == id }
    }
}
