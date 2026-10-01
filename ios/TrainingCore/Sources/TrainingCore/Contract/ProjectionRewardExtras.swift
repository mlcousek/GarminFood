// ProjectionRewardExtras.swift
//
// add-training-gamification-and-150-levels (design D6): the few projection
// fields the training rewards need that the shared `Projection` model does
// not carry yet, read straight from the cached bytes:
//
//   - `athlete.gate.date` / `.stale` -- the weekly gate test (the vault's
//     2026-10-01 addition);
//   - per week `actual.unplannedRunKm` / `actual.overPlanKm` -- "the plan is
//     the ceiling" (same addition);
//   - `outcomes[]` -- the ids of plan commands the vault applied or absorbed;
//   - per race `result` -- NOT published by the vault yet (an open question
//     of this change): `{ outcome: "finished" | "dnf" | "dns", goalReached,
//     pr, stopRule, fuelPlanFollowed }`. Until it is, every race reads as
//     "no result" and the rewards that need it stay dormant.
//
// WHY A SIDECAR AND NOT FIELDS ON `Projection`: two other changes are
// extending `Projection.swift` at the same time (the daily check-in with
// pain mode and the interactive habits), and some of these fields are
// theirs to model. Decoding them here, from the raw JSON, keeps this change
// out of that file. When the shared model carries a field, the matching
// lines here can go and `TrainingPlanFacts` can read the model instead;
// nothing else changes.
//
// Tolerant by construction (the contract's consumer rules): the bytes are
// walked as plain JSON, so an absent key, a `null`, a wrong type, an unknown
// enum value or a document that is not JSON at all reads as "absent" --
// `ProjectionRewardExtras.empty` in the worst case. It never throws and
// never invents a value: a missing number is `nil`, never 0.
//
// Depended on by: ProjectionStore.cachedRewardExtras(), TrainingPlanFacts.
// Tests: TrainingPlanFactsTests.

import Foundation

/// How a race ended, when the vault says so.
public enum RaceOutcome: String, OpenEnumValue {
    case finished
    case dnf
    case dns
}

public struct ProjectionRewardExtras: Equatable, Sendable {
    /// The load fields of one week's `actual`.
    public struct WeekLoad: Equatable, Sendable {
        public var unplannedRunKm: Double?
        public var overPlanKm: Double?

        public init(unplannedRunKm: Double? = nil, overPlanKm: Double? = nil) {
            self.unplannedRunKm = unplannedRunKm
            self.overPlanKm = overPlanKm
        }
    }

    /// A race's machine-readable result (not published yet).
    public struct RaceResult: Equatable, Sendable {
        public var outcome: OpenEnum<RaceOutcome>?
        public var goalReached: Bool?
        public var pr: Bool?
        /// A stop rule ended the race (or kept the athlete from starting).
        public var stopRule: Bool?
        public var fuelPlanFollowed: Bool?

        public init(
            outcome: OpenEnum<RaceOutcome>? = nil,
            goalReached: Bool? = nil,
            pr: Bool? = nil,
            stopRule: Bool? = nil,
            fuelPlanFollowed: Bool? = nil
        ) {
            self.outcome = outcome
            self.goalReached = goalReached
            self.pr = pr
            self.stopRule = stopRule
            self.fuelPlanFollowed = fuelPlanFollowed
        }
    }

    /// The date of the last gate test, `nil` when never tested.
    public var gateDate: LocalDate?
    /// The vault says that test is more than 14 days old.
    public var gateIsStale: Bool
    /// Keyed by the week as written (`YYYY-Www`).
    public var weekLoads: [String: WeekLoad]
    /// Keyed by race id.
    public var raceResults: [String: RaceResult]
    /// Event ids of plan commands with status `applied` or `absorbed`.
    public var appliedPlanEditIds: [String]

    public init(
        gateDate: LocalDate? = nil,
        gateIsStale: Bool = false,
        weekLoads: [String: WeekLoad] = [:],
        raceResults: [String: RaceResult] = [:],
        appliedPlanEditIds: [String] = []
    ) {
        self.gateDate = gateDate
        self.gateIsStale = gateIsStale
        self.weekLoads = weekLoads
        self.raceResults = raceResults
        self.appliedPlanEditIds = appliedPlanEditIds
    }

    public static let empty = ProjectionRewardExtras()

    /// Reads the extras from a projection's bytes; `.empty` for anything
    /// that is not a JSON object.
    public static func decode(_ bytes: Data) -> ProjectionRewardExtras {
        guard let root = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any] else { return .empty }
        var extras = ProjectionRewardExtras()

        if let athlete = root["athlete"] as? [String: Any], let gate = athlete["gate"] as? [String: Any] {
            extras.gateDate = (gate["date"] as? String).flatMap { LocalDate($0) }
            extras.gateIsStale = bool(gate["stale"]) ?? false
        }

        if let plan = root["plan"] as? [String: Any], let weeks = plan["weeks"] as? [Any] {
            for case let week as [String: Any] in weeks {
                guard let name = week["week"] as? String, let actual = week["actual"] as? [String: Any] else { continue }
                let load = WeekLoad(unplannedRunKm: number(actual["unplannedRunKm"]), overPlanKm: number(actual["overPlanKm"]))
                if load.unplannedRunKm != nil || load.overPlanKm != nil {
                    extras.weekLoads[name] = load
                }
            }
        }

        if let season = root["season"] as? [String: Any], let races = season["races"] as? [Any] {
            for case let race as [String: Any] in races {
                guard let id = race["id"] as? String, let result = race["result"] as? [String: Any] else { continue }
                extras.raceResults[id] = RaceResult(
                    outcome: (result["outcome"] as? String).map { OpenEnum<RaceOutcome>(rawValue: $0) },
                    goalReached: bool(result["goalReached"]),
                    pr: bool(result["pr"]),
                    stopRule: bool(result["stopRule"]),
                    fuelPlanFollowed: bool(result["fuelPlanFollowed"])
                )
            }
        }

        if let outcomes = root["outcomes"] as? [Any] {
            var ids: [String] = []
            for case let outcome as [String: Any] in outcomes {
                guard let event = outcome["event"] as? String,
                      let type = outcome["type"] as? String, type.hasPrefix("plan."),
                      let status = outcome["status"] as? String, status == "applied" || status == "absorbed",
                      !ids.contains(event)
                else { continue }
                ids.append(event)
            }
            extras.appliedPlanEditIds = ids
        }
        return extras
    }

    /// A JSON number (never a Boolean, never a string); `nil` otherwise.
    private static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, !isBoolean(number) else { return nil }
        let double = number.doubleValue
        return double.isFinite ? double : nil
    }

    /// A JSON `true` / `false`; `nil` for anything else (a number is not a
    /// Boolean here).
    private static func bool(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, isBoolean(number) else { return nil }
        return number.boolValue
    }

    private static func isBoolean(_ number: NSNumber) -> Bool {
        CFGetTypeID(number as CFTypeRef) == CFBooleanGetTypeID()
    }
}
