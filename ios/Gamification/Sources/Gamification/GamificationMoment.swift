import Foundation

// GamificationMoment.swift
//
// design.md D5 / levels spec's "Leveling up is a visible, animated moment"
// / challenges spec's "Completing a challenge is a rewarded, visible
// moment" requirements: a plain, UI-framework-free value describing WHAT
// happened after a log, so the app layer can decide HOW to show it
// (animation + haptic, or a Reduce-Motion-respecting equivalent -- that
// decision lives entirely in the GarminFood app target's SwiftUI views,
// never here).
public enum GamificationMoment: Sendable, Equatable {
    case levelUp(newLevel: Int)
    case challengeCompleted(title: String, xpAwarded: Int)
    /// Tasks 23.4's "a subtle celebratory moment... the first time a new
    /// streak milestone is reached in a session" -- `days` is the
    /// milestone reached (a multiple of `StreakMilestones.interval`).
    case streakMilestone(days: Int)
    /// daily-challenges spec's "completing a daily challenge is a
    /// rewarded, visible moment" requirement.
    case dailyChallengeCompleted(title: String, xpAwarded: Int)
    /// achievements spec's "unlocking an achievement is a rewarded,
    /// visible moment" requirement.
    case achievementUnlocked(title: String, badgeSymbol: String)
}

/// Tasks 23.4: "every 7 days" is the one concrete example given; kept as a
/// named constant rather than a magic number so a future change to the
/// cadence is a one-line edit.
public enum StreakMilestones {
    public static let interval = 7

    public static func isMilestone(_ length: Int) -> Bool {
        length > 0 && length % interval == 0
    }
}
