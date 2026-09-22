import Foundation

// LevelTier.swift
//
// expand-gamification-depth design.md D1's "levels also gain a tier/title"
// decision: a small, hand-written table of ~20 named bands spanning the
// full 1-200 level range, so level progress reads as more than a bare
// number without inventing 200 individually distinct names (D1's own
// framing: a tier name + "Level 47" beats a thin per-level reskin).
public struct LevelTier: Sendable, Equatable {
    public let title: String
    public let flavor: String
    public let levelRange: ClosedRange<Int>

    public init(title: String, flavor: String, levelRange: ClosedRange<Int>) {
        self.title = title
        self.flavor = flavor
        self.levelRange = levelRange
    }

    /// Reuses `AchievementRarity`'s same bucketing as level-based
    /// achievements (`AchievementCondition.levelAtLeast`), evaluated at this
    /// tier's lower bound, so the level-up moment and the achievements
    /// screen agree on what "epic" or "legendary" progress looks like
    /// instead of maintaining two separate notions of "how far along".
    public var rarity: AchievementRarity {
        AchievementRarity.derive(from: .levelAtLeast(level: levelRange.lowerBound))
    }

    /// A glyph that escalates with `rarity`, for `BadgeMedallion` display in
    /// the level-up moment -- all five symbols are already used elsewhere in
    /// this catalog/app (see `AchievementCatalog`'s level and meta families,
    /// and `StreakDot`), so nothing new needs verifying at the glyph-name
    /// level.
    public var badgeSymbol: String {
        switch rarity {
        case .common: return "star.fill"
        case .uncommon: return "sparkles"
        case .rare: return "shield.fill"
        case .epic: return "flame.fill"
        case .legendary: return "crown.fill"
        }
    }
}

public enum LevelTiers {
    /// Contiguous, gap-free, covering exactly 1...200 (`LevelCurve.maxLevel`)
    /// -- verified by `LevelTierTests`.
    public static let all: [LevelTier] = [
        LevelTier(title: "Newcomer", flavor: "Everyone starts somewhere.", levelRange: 1...5),
        LevelTier(title: "Rookie", flavor: "The habit is forming.", levelRange: 6...10),
        LevelTier(title: "Apprentice", flavor: "You know your way around now.", levelRange: 11...15),
        LevelTier(title: "Regular", flavor: "This is just what you do now.", levelRange: 16...20),
        LevelTier(title: "Steady Hand", flavor: "Consistency is becoming your thing.", levelRange: 21...27),
        LevelTier(title: "Dedicated", flavor: "Missing a day feels wrong now.", levelRange: 28...35),
        LevelTier(title: "Committed", flavor: "Months in, still showing up.", levelRange: 36...44),
        LevelTier(title: "Seasoned", flavor: "You've seen every kind of day.", levelRange: 45...54),
        LevelTier(title: "Veteran", flavor: "A full year, easy.", levelRange: 55...65),
        LevelTier(title: "Expert", flavor: "You could teach this.", levelRange: 66...77),
        LevelTier(title: "Elite", flavor: "Top of the leaderboard, if there were one.", levelRange: 78...90),
        LevelTier(title: "Master", flavor: "Multi-year discipline.", levelRange: 91...104),
        LevelTier(title: "Grandmaster", flavor: "Genuinely rare territory.", levelRange: 105...119),
        LevelTier(title: "Champion", flavor: "Years of unbroken effort.", levelRange: 120...135),
        LevelTier(title: "Luminary", flavor: "An inspiration, if anyone was watching.", levelRange: 136...152),
        LevelTier(title: "Mythic", flavor: "The stuff of legend.", levelRange: 153...170),
        LevelTier(title: "Immortal", flavor: "Time itself is starting to notice.", levelRange: 171...185),
        LevelTier(title: "Transcendent", flavor: "Beyond the curve's original design.", levelRange: 186...195),
        LevelTier(title: "Ascendant", flavor: "One step from the summit.", levelRange: 196...199),
        LevelTier(title: "Legend", flavor: "You reached the ceiling. Actually reached it.", levelRange: 200...200)
    ]

    /// Falls back to the last tier for any level past `LevelCurve.maxLevel`
    /// (should not happen, since level is always clamped there, but keeps
    /// this total rather than partial).
    public static func tier(forLevel level: Int) -> LevelTier {
        all.first { $0.levelRange.contains(level) } ?? all[all.count - 1]
    }
}
