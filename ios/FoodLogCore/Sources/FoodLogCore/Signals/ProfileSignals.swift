// ProfileSignals.swift
//
// The few facts about the OWNER (not about a day) that gamification rules
// need: a first name for personal touches (seasonal name-day events) and
// the weight goal in plain kilograms (sport & body badges). Plain values
// so Gamification never names a GarminKit type (design D5).
//
// The first name comes from Garmin's `socialProfile.fullName`, cached in
// AppPreferences by the app's `GamificationSignalsSync` (so it survives
// offline launches); the weight goal is the app's effective goal (local
// override, else Garmin's nutrition settings), passed in by the app.

import Foundation

public struct WeightGoalSignal: Sendable, Equatable, Codable {
    public let startKg: Double?
    public let targetKg: Double?

    public init(startKg: Double?, targetKg: Double?) {
        self.startKg = startKg
        self.targetKg = targetKg
    }
}

public struct ProfileSignals: Sendable, Equatable {
    public let firstName: String?
    public let weightGoal: WeightGoalSignal?

    public init(firstName: String? = nil, weightGoal: WeightGoalSignal? = nil) {
        self.firstName = firstName
        self.weightGoal = weightGoal
    }

    /// The first whitespace-separated token of a full name: "Jiří
    /// Mlčoušek" -> "Jiří". `nil` for a blank name.
    public static func firstName(fromFullName fullName: String?) -> String? {
        guard let fullName else { return nil }
        let first = fullName
            .split(whereSeparator: { $0.isWhitespace })
            .first
            .map(String.init)
        guard let first, !first.isEmpty else { return nil }
        return first
    }
}
