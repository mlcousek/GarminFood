// SportActivityClass.swift
//
// add-sport-and-body-achievements design D1: which cached Garmin activities
// the sport badges count at all. Garmin's `activityType.typeKey` is a free
// snake_case string ("running", "trail_running", "indoor_cycling",
// "mountain_biking", "lap_swimming", "strength_training", "mobility",
// "yoga", ...), so classification is by keyword, not an exhaustive list:
//
//   - endurance: the key contains running / cycling / biking / hiking /
//     swimming / skiing / rowing, is one of the few run/ride keys without
//     that spelling (ultra_run, virtual_run, obstacle_run, virtual_ride,
//     cyclocross), or it is a walk of >= 45 minutes;
//   - strength: `strength_training` -- counts for Recovery Window only;
//   - other: everything else (mobility, yoga, breathwork, short walks...).
//
// Anything shorter than 20 minutes is `.other` whatever its type.
//
// Pure; tested in SportActivityClassTests.
//
// Depends on: FoodLogCore (ActivitySummary). Depended on by: SportRules,
// SportAndBodyFeature.

import Foundation
import FoodLogCore

public enum SportActivityClass: String, Sendable, Equatable, CaseIterable {
    case endurance
    case strength
    case other

    /// Below this nothing counts.
    public static let minimumMinutes: Double = 20
    /// A walk counts as endurance only from this long.
    public static let minimumWalkMinutes: Double = 45

    static let enduranceKeywords = ["running", "cycling", "biking", "hiking", "swimming", "skiing", "rowing"]
    /// Garmin run/ride keys the keywords above miss (not "-ing" spelled).
    static let runKeys: Set<String> = ["ultra_run", "virtual_run", "obstacle_run"]
    static let rideKeys: Set<String> = ["virtual_ride", "cyclocross"]
    static let strengthKeys: Set<String> = ["strength_training"]

    public static func classify(typeKey: String, durationMinutes: Double) -> SportActivityClass {
        guard durationMinutes >= minimumMinutes else { return .other }
        let key = typeKey.lowercased()
        if strengthKeys.contains(key) { return .strength }
        if enduranceKeywords.contains(where: { key.contains($0) }) { return .endurance }
        if runKeys.contains(key) || rideKeys.contains(key) { return .endurance }
        if key.contains("walking") {
            return durationMinutes >= minimumWalkMinutes ? .endurance : .other
        }
        return .other
    }

    public static func classify(_ activity: ActivitySummary) -> SportActivityClass {
        classify(typeKey: activity.typeKey, durationMinutes: activity.durationMinutes)
    }

    /// Counts toward Recovery Window.
    public var countsForRecovery: Bool { self == .endurance || self == .strength }
}

/// What kind of activity a typeKey is, for display only (the Sport & Body
/// screen's name and symbol per row). Order matters: "trail_running" is a
/// run, "mountain_biking" a ride.
public enum SportActivityKind: String, Sendable, Equatable, CaseIterable {
    case run, ride, hike, swim, walk, ski, row, strength, other

    public init(typeKey: String) {
        let key = typeKey.lowercased()
        if key.contains("running") || SportActivityClass.runKeys.contains(key) {
            self = .run
        } else if key.contains("cycling") || key.contains("biking") || SportActivityClass.rideKeys.contains(key) {
            self = .ride
        } else if key.contains("hiking") {
            self = .hike
        } else if key.contains("swimming") {
            self = .swim
        } else if key.contains("walking") {
            self = .walk
        } else if key.contains("skiing") {
            self = .ski
        } else if key.contains("rowing") {
            self = .row
        } else if SportActivityClass.strengthKeys.contains(key) {
            self = .strength
        } else {
            self = .other
        }
    }
}
