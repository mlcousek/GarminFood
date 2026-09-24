// SportActivityClass.swift
//
// add-sport-and-body-achievements design D1: which cached Garmin activities
// the sport badges count at all. Garmin's `activityType.typeKey` is a free
// snake_case string ("running", "trail_running", "indoor_cycling",
// "mountain_biking", "lap_swimming", "strength_training", "mobility",
// "yoga", ...), so classification is by keyword, not an exhaustive list:
//
//   - endurance: the key contains running / cycling / biking / hiking /
//     swimming / skiing / rowing, or it is a walk of >= 45 minutes;
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
    static let strengthKeys: Set<String> = ["strength_training"]

    public static func classify(typeKey: String, durationMinutes: Double) -> SportActivityClass {
        guard durationMinutes >= minimumMinutes else { return .other }
        let key = typeKey.lowercased()
        if strengthKeys.contains(key) { return .strength }
        if enduranceKeywords.contains(where: { key.contains($0) }) { return .endurance }
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
