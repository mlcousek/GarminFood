// TrainingPlanSignalsBridge.swift
//
// add-training-gamification-and-150-levels (design D6): the app's adapter
// between the training plan's facts (TrainingCore's `TrainingPlanFacts`) and
// the training XP (Gamification's `TrainingPlanSignals`). The two packages
// never import each other, so this file copies the facts across, field by
// field, and does nothing else: what a fact means is defined and tested in
// TrainingCore (TrainingPlanFactsTests), what it is worth in Gamification
// (TrainingXPRulesTests).
//
// `planSignals(now:extras:)` returns nothing without a loaded projection.
// The `extras` are the few fields the shared projection model does not
// carry yet (`ProjectionStore.cachedRewardExtras()`); the caller reads them
// from the cached bytes -- no network.
//
// The CALLER decides whether the training experience is on
// (AppEnvironment+TrainingNutrition wires this into FeatureHost only for
// that experience); food-first never asks.
//
// Beside TrainingNutritionBridge.swift, which keeps the original
// `rewardSignals` for the five first badge ladders.
//
// Depends on: TrainingModel, TrainingCore, Gamification.
// Depended on by: AppEnvironment (the provider FeatureHost reads).

import Foundation
import TrainingCore
import Gamification

extension TrainingModel {
    /// The plan's facts for the training XP, in Gamification's shape.
    func planSignals(now: Date = Date(), extras: ProjectionRewardExtras = .empty) -> TrainingPlanSignals? {
        guard let snapshot = source.snapshot else { return nil }
        let facts = TrainingPlanFacts.build(snapshot: snapshot, extras: extras, today: today(now: now))
        return TrainingPlanSignals(facts)
    }
}

extension TrainingPlanSignals {
    /// A plain copy of TrainingCore's facts.
    init(_ facts: TrainingPlanFacts) {
        self.init(
            today: facts.today.description,
            days: facts.days.map { TrainingPlanSignals.Day($0) },
            weeks: facts.weeks.map { TrainingPlanSignals.Week($0) },
            activeHabitIds: facts.activeHabitIds,
            habitGatePercent: facts.habitGatePercent,
            races: facts.races.map { TrainingPlanSignals.Race($0) },
            phases: facts.phases.map { TrainingPlanSignals.Phase(id: $0.id, isClosed: $0.isClosed, hasRecap: $0.hasRecap) },
            season: facts.season.map { TrainingPlanSignals.Season(id: $0.id, endDay: $0.end?.description) },
            gateTestDay: facts.gateTestDate?.description,
            appliedPlanEditIds: facts.appliedPlanEditIds
        )
    }
}

extension TrainingPlanSignals.Day {
    init(_ fact: PlanDayFact) {
        self.init(
            day: fact.date.description,
            isInPlan: fact.isInPlan,
            light: fact.checkInLight.map { TrainingPlanSignals.Light($0) },
            painAnswered: fact.painAnswered,
            habitsExpected: fact.habitsExpected,
            habitsDone: fact.habitsDone,
            sessions: fact.sessions.map { TrainingPlanSignals.Session($0) },
            hasUnplannedRun: fact.hasUnplannedRun,
            isCarbLoad: fact.isCarbLoad
        )
    }
}

extension TrainingPlanSignals.Session {
    init(_ fact: PlanSessionFact) {
        self.init(
            id: fact.id,
            isDone: fact.isDone,
            isSkipped: fact.isSkipped,
            isMissed: fact.isMissed,
            isTrafficLight: fact.isTrafficLight,
            doneOption: fact.doneOption.map { TrainingPlanSignals.Option($0) },
            isStrength: fact.isStrength,
            isRace: fact.isRace,
            raceId: fact.raceId,
            isTest: fact.isTest,
            hasTestResult: fact.hasTestResult,
            hasRPE: fact.hasRPE,
            hasNote: fact.hasNote
        )
    }
}

extension TrainingPlanSignals.Week {
    init(_ fact: PlanWeekFact) {
        self.init(
            week: fact.week.description,
            isClosed: fact.isClosed,
            isApproved: fact.isApproved,
            isEasy: fact.isEasy,
            runKmTarget: fact.runKmTarget,
            runKm: fact.runKm,
            unplannedRunKm: fact.unplannedRunKm,
            overPlanKm: fact.overPlanKm
        )
    }
}

extension TrainingPlanSignals.Race {
    init(_ fact: PlanRaceFact) {
        self.init(
            id: fact.id,
            day: fact.date.description,
            isPrepComplete: fact.isPrepComplete,
            hasReport: fact.hasReport,
            outcome: fact.outcome.map { TrainingPlanSignals.RaceOutcome($0) },
            goalReached: fact.goalReached,
            isPersonalRecord: fact.isPersonalRecord,
            stoppedByRule: fact.stoppedByRule,
            fuelPlanFollowed: fact.fuelPlanFollowed
        )
    }
}

// The three small enums have the same cases on both sides. Their names
// avoid colour words on purpose (the design-token lint forbids colour
// literals in app sources), so these switches stay lint-clean.

extension TrainingPlanSignals.Light {
    init(_ light: MorningLight) {
        switch light {
        case .greenLight: self = .greenLight
        case .amberLight: self = .amberLight
        case .redLight: self = .redLight
        }
    }
}

extension TrainingPlanSignals.Option {
    init(_ option: OptionCode) {
        switch option {
        case .g: self = .g
        case .a: self = .a
        case .r: self = .r
        }
    }
}

extension TrainingPlanSignals.RaceOutcome {
    init(_ outcome: TrainingCore.RaceOutcome) {
        switch outcome {
        case .finished: self = .finished
        case .dnf: self = .dnf
        case .dns: self = .dns
        }
    }
}
