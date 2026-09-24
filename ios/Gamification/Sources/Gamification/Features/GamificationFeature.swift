// GamificationFeature.swift
//
// The plug-in seam (design D7) every wave-2 gamification feature (bingo,
// seasonal events, collections, journeys, records, secrets, sport & body,
// boss) implements, so each ships as its own files without editing the
// engine: the app's `FeatureHost` builds one `FeatureContext` per refresh /
// confirm, calls `update` on every registered feature, and applies the
// returned `FeatureUpdate` -- idempotent grants via `RewardLedger`, badge
// unlocks via `AchievementStore`, moments into the celebration queue.
//
// Features are actors (own JSON stores under
// `GamificationStorage.directory()/features/<featureId>/`), hence
// `AnyObject, Sendable` and an `async` update. `featureId`/`badges` are
// static facts a conforming actor declares `nonisolated`, so the
// Achievements screen can list badges without awaiting anything.
//
// Display text inside `FeatureMoment`/`FeatureSummary` is produced by the
// feature itself (already localized); nothing here persists it.
//
// Depends on: FoodLogCore (SignalsSnapshot), StreakEngine.Status,
// AchievementDefinition.
// Depended on by: GamificationFeatureRegistry, RewardLedger, the app's
// FeatureHost/MomentOverlay, every wave-2 feature.

import Foundation
import FoodLogCore

public protocol GamificationFeature: AnyObject, Sendable {
    /// "bingo", "seasonal", ... -- also the store subdirectory name and the
    /// `RewardGrant.key` namespace.
    var featureId: String { get }
    /// Static badge definitions this feature can unlock (for the
    /// Achievements screen and `BadgeRegistry`).
    var badges: [AchievementDefinition] { get }
    /// Local reads only -- never the network.
    func update(_ context: FeatureContext) async -> FeatureUpdate
}

/// Everything a feature may read for one run.
public struct FeatureContext: Sendable {
    public let snapshot: SignalsSnapshot
    public let now: Date
    public let calendar: Calendar
    public let streak: StreakEngine.Status
    public let level: Int
    public let unlockedBadgeIds: Set<String>
    /// `true` when called right after a log confirm (keep work minimal).
    public let isConfirmPath: Bool

    public init(
        snapshot: SignalsSnapshot,
        now: Date,
        calendar: Calendar,
        streak: StreakEngine.Status,
        level: Int,
        unlockedBadgeIds: Set<String>,
        isConfirmPath: Bool
    ) {
        self.snapshot = snapshot
        self.now = now
        self.calendar = calendar
        self.streak = streak
        self.level = level
        self.unlockedBadgeIds = unlockedBadgeIds
        self.isConfirmPath = isConfirmPath
    }
}

/// A reward, applied at most once per `key` (see `RewardLedger`). Keys are
/// namespaced `"<featureId>.<what>.<period>"`, e.g.
/// `bingo.line.2026-W39.row0`.
public struct RewardGrant: Sendable, Equatable, Hashable {
    public enum Kind: Sendable, Equatable, Hashable {
        case xp(Int)
        /// Recorded only; `add-weekly-boss-and-streak-freezes` turns these
        /// into a freeze balance.
        case streakFreeze
    }

    public let key: String
    public let kind: Kind

    public init(key: String, kind: Kind) {
        self.key = key
        self.kind = kind
    }
}

/// A feature's celebration, rendered generically by the app's
/// `MomentOverlay` (symbol, title, message, XP, style colour + haptic).
public struct FeatureMoment: Sendable, Equatable {
    public enum Style: String, Sendable, Equatable, Codable, CaseIterable {
        case celebration, record, secret, event, boss, freeze
    }

    public let featureId: String
    public let title: String
    public let message: String
    /// An SF Symbol name.
    public let symbol: String
    public let style: Style
    public let xpAwarded: Int

    public init(featureId: String, title: String, message: String, symbol: String, style: Style, xpAwarded: Int = 0) {
        self.featureId = featureId
        self.title = title
        self.message = message
        self.symbol = symbol
        self.style = style
        self.xpAwarded = xpAwarded
    }
}

/// What a feature shows on a generic hub card.
public struct FeatureSummary: Sendable, Equatable {
    public let title: String
    public let subtitle: String
    /// 0...1 progress, `nil` when the feature has no single progress value.
    public let fraction: Double?
    public let symbol: String

    public init(title: String, subtitle: String, fraction: Double? = nil, symbol: String) {
        self.title = title
        self.subtitle = subtitle
        self.fraction = fraction.map { min(max($0, 0), 1) }
        self.symbol = symbol
    }
}

/// The result of one feature run. Empty = nothing happened.
public struct FeatureUpdate: Sendable, Equatable {
    public var grants: [RewardGrant]
    public var unlockBadgeIds: [String]
    public var moments: [FeatureMoment]
    public var summary: FeatureSummary?

    public init(
        grants: [RewardGrant] = [],
        unlockBadgeIds: [String] = [],
        moments: [FeatureMoment] = [],
        summary: FeatureSummary? = nil
    ) {
        self.grants = grants
        self.unlockBadgeIds = unlockBadgeIds
        self.moments = moments
        self.summary = summary
    }

    public static let empty = FeatureUpdate()
}
