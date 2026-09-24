// JourneysEvaluator.swift
//
// add-journeys-and-records design D1-D5: the pure step behind
// `JourneysFeature` -- given the stored state and one signals snapshot, it
// (1) advances each cumulative journey's `DailyLedger` (open days
// recomputed, older days folded into `sealedTotal` exactly once), (2) grows
// the passport's food-id set, and (3) reports every milestone the new totals
// crossed that wasn't reached before (several per journey and per day are
// fine -- each is reported once).
//
// Per-day values (days without the data contribute nothing):
//   - protein: `totals.protein` of a day with entries or a Garmin log,
//     converted at 0.5 m per gram;
//   - water: `waterML` in litres;
//   - road: `activeKcal` / the weight known ON THAT DAY (latest weigh-in in
//     the window on or before it, else the weight stored as of the last
//     sealed day, else 70 kg) -- so past distance never shifts when weight
//     changes later (design "Risks").
//
// `progress` turns a state into what the UI shows (position, last and next
// milestone, remaining distance, Podolí percentage).
//
// Depends on: DailyLedger, JourneyCatalog, JourneysState, FoodLogCore
// (SignalsSnapshot/DaySignals).
// Depended on by: JourneysFeature, JourneysTests.

import Foundation
import FoodLogCore

/// What one journey looks like right now (for the UI and the summary card).
public struct JourneyProgress: Sendable, Equatable, Identifiable {
    public let kind: JourneyKind
    public var id: String { kind.rawValue }
    public let definition: JourneyDefinition
    /// Cumulative total in the journey's unit.
    public let total: Double
    /// The furthest milestone at or below `total`.
    public let lastReached: JourneyMilestone?
    /// The first milestone above `total`; `nil` once every milestone is reached.
    public let next: JourneyMilestone?
    /// 0...1 from `lastReached` (or the start) to `next`; 1 when complete.
    public let fractionToNext: Double
    /// Distance left to `next`, in the journey's unit.
    public let remainingToNext: Double?
    /// The stage the owner is currently in (the next milestone's stage, or
    /// the last stage once complete).
    public let stageIndex: Int
    /// Position within the current stage (stage 2 starts at 0 m).
    public let positionInStage: Double
    /// Percent of the endless goal filled (Podolí), once past every finite
    /// milestone; `nil` otherwise.
    public let endlessPercent: Double?
    /// `false` when the data source this journey needs is unavailable
    /// (e.g. no active kcal in standalone mode) -- the UI hides it.
    public let isAvailable: Bool

    public var isComplete: Bool { next == nil }
    public var stage: JourneyStage? {
        definition.stages.indices.contains(stageIndex) ? definition.stages[stageIndex] : nil
    }
}

public enum JourneysEvaluator {
    public struct ReachedMilestone: Sendable, Equatable {
        public let kind: JourneyKind
        public let milestone: JourneyMilestone
    }

    public struct Result: Sendable, Equatable {
        public let state: JourneysState
        /// Milestones reached for the first time in this run, journey order
        /// then threshold order.
        public let newlyReached: [ReachedMilestone]
        /// `true` when this was the first run (the 42-day back-fill).
        public let wasFirstRun: Bool
    }

    // MARK: - Per-day values

    /// Metres climbed on `day`, `nil` when its protein is unknown.
    public static func proteinMetres(_ day: DaySignals) -> Double? {
        guard day.hasEntries || day.availability.hasGarminLog, let grams = day.totals.protein else { return nil }
        return JourneyCatalog.metres(proteinGrams: grams)
    }

    public static func waterLitres(_ day: DaySignals) -> Double? {
        day.waterML.map { JourneyCatalog.litres(waterML: $0) }
    }

    public static func roadKilometres(_ day: DaySignals, weightKg: Double?) -> Double? {
        day.activeKcal.map { JourneyCatalog.kilometres(activeKcal: $0, weightKg: weightKg) }
    }

    /// Whether `kind`'s data source exists in any of `days`: its declared
    /// `DataRequirement`, or -- for the road trip -- a cached active-kcal
    /// value (Garmin's daily summary is cached separately from the activity
    /// list, so either one proves the source exists).
    public static func isAvailable(_ kind: JourneyKind, days: [DaySignals]) -> Bool {
        if JourneyCatalog.definition(kind).requirement.isSatisfied(byAnyOf: days) { return true }
        return kind == .road && days.contains { $0.activeKcal != nil }
    }

    /// The weight known on each window day: the latest weigh-in in the
    /// window on or before it, else `stored` (known as of the last sealed
    /// day, which is older than every day still to be counted).
    static func weightsByDay(_ snapshot: SignalsSnapshot, stored: Double?) -> [String: Double] {
        var latest: Double?
        var result: [String: Double] = [:]
        for key in snapshot.windowDays {
            if let kg = snapshot.days[key]?.weighInKg, kg > 0 {
                latest = kg
            }
            if let weight = latest ?? stored {
                result[key] = weight
            }
        }
        return result
    }

    // MARK: - Evaluation

    public static func evaluate(state: JourneysState, snapshot: SignalsSnapshot) -> Result {
        var next = state
        let wasFirstRun = state.isFirstRun

        next.protein = advance(state.protein ?? CumulativeJourneyState(), snapshot: snapshot) { day in
            snapshot.days[day].flatMap(proteinMetres)
        }
        next.water = advance(state.water ?? CumulativeJourneyState(), snapshot: snapshot) { day in
            snapshot.days[day].flatMap(waterLitres)
        }

        var road = state.road ?? CumulativeJourneyState()
        let weights = weightsByDay(snapshot, stored: road.lastKnownWeightKg)
        road = advance(road, snapshot: snapshot) { day in
            snapshot.days[day].flatMap { roadKilometres($0, weightKg: weights[day]) }
        }
        if let sealedThrough = road.ledger?.sealedThrough,
           let lastSealedWeighIn = snapshot.windowDays
               .filter({ $0 <= sealedThrough })
               .compactMap({ key in snapshot.days[key]?.weighInKg.flatMap { $0 > 0 ? $0 : nil } })
               .last {
            road.lastKnownWeightKg = lastSealedWeighIn
        }
        next.road = road

        var passport = state.passport ?? PassportJourneyState()
        var ids = Set(passport.foodIds ?? [])
        for day in snapshot.days.values {
            for entry in day.entries where !entry.foodId.isEmpty {
                ids.insert(entry.foodId)
            }
        }
        for foodId in snapshot.firstSeenDayByFood.keys where !foodId.isEmpty {
            ids.insert(foodId)
        }
        passport.foodIds = ids.sorted()
        next.passport = passport

        // Milestones.
        var newlyReached: [ReachedMilestone] = []
        for kind in JourneyKind.allCases {
            let definition = JourneyCatalog.definition(kind)
            let total = next.total(kind)
            var reached = next.reachedMilestones(kind)
            for milestone in definition.milestones where milestone.threshold <= total && !reached.contains(milestone.id) {
                reached.insert(milestone.id)
                newlyReached.append(ReachedMilestone(kind: kind, milestone: milestone))
            }
            let ordered = definition.milestones.map(\.id).filter { reached.contains($0) }
            switch kind {
            case .protein: next.protein?.reachedMilestones = ordered
            case .water: next.water?.reachedMilestones = ordered
            case .road: next.road?.reachedMilestones = ordered
            case .passport: next.passport?.reachedMilestones = ordered
            }
        }

        if next.startedOn == nil {
            next.startedOn = snapshot.today.isEmpty ? nil : snapshot.today
        }
        return Result(state: next, newlyReached: newlyReached, wasFirstRun: wasFirstRun)
    }

    private static func advance(
        _ journey: CumulativeJourneyState,
        snapshot: SignalsSnapshot,
        value: (String) -> Double?
    ) -> CumulativeJourneyState {
        var journey = journey
        var ledger = journey.ledger ?? DailyLedger<Double>()
        let sealed = ledger.advance(windowDays: snapshot.windowDays, value: value)
        journey.sealedTotal = (journey.sealedTotal ?? 0) + sealed.reduce(0) { $0 + $1.value }
        journey.ledger = ledger
        return journey
    }

    // MARK: - Progress

    public static func progress(
        state: JourneysState,
        kind: JourneyKind,
        isAvailable: Bool = true
    ) -> JourneyProgress {
        let definition = JourneyCatalog.definition(kind)
        let total = state.total(kind)
        let lastReached = definition.milestones.last { $0.threshold <= total }
        let next = definition.milestones.first { $0.threshold > total }
        let from = lastReached?.threshold ?? 0
        let fraction: Double
        let remaining: Double?
        if let next {
            let span = next.threshold - from
            fraction = span > 0 ? min(max((total - from) / span, 0), 1) : 1
            remaining = max(0, next.threshold - total)
        } else {
            fraction = 1
            remaining = nil
        }
        let stageIndex = next?.stageIndex ?? max(0, definition.stages.count - 1)
        let stageStart = definition.stages.indices.contains(stageIndex) ? definition.stages[stageIndex].start : 0
        var endlessPercent: Double?
        if next == nil, let endless = definition.endless, endless.capacity > 0 {
            endlessPercent = total / endless.capacity * 100
        }
        return JourneyProgress(
            kind: kind,
            definition: definition,
            total: total,
            lastReached: lastReached,
            next: next,
            fractionToNext: fraction,
            remainingToNext: remaining,
            stageIndex: stageIndex,
            positionInStage: max(0, total - stageStart),
            endlessPercent: endlessPercent,
            isAvailable: isAvailable
        )
    }
}
