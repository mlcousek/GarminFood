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
        localized("Newcomer", "Everyone starts somewhere.", 1...5),
        localized("Rookie", "The habit is forming.", 6...10),
        localized("Apprentice", "You know your way around now.", 11...15),
        localized("Regular", "This is just what you do now.", 16...20),
        localized("Steady Hand", "Consistency is becoming your thing.", 21...27),
        localized("Dedicated", "Missing a day feels wrong now.", 28...35),
        localized("Committed", "Months in, still showing up.", 36...44),
        localized("Seasoned", "You've seen every kind of day.", 45...54),
        localized("Veteran", "A full year, easy.", 55...65),
        localized("Expert", "You could teach this.", 66...77),
        localized("Elite", "Top of the leaderboard, if there were one.", 78...90),
        localized("Master", "Multi-year discipline.", 91...104),
        localized("Grandmaster", "Genuinely rare territory.", 105...119),
        localized("Champion", "Years of unbroken effort.", 120...135),
        localized("Luminary", "An inspiration, if anyone was watching.", 136...152),
        localized("Mythic", "The stuff of legend.", 153...170),
        localized("Immortal", "Time itself is starting to notice.", 171...185),
        localized("Transcendent", "Beyond the curve's original design.", 186...195),
        localized("Ascendant", "One step from the summit.", 196...199),
        localized("Legend", "You reached the ceiling. Actually reached it.", 200...200)
    ]

    /// add-localization 4.1: a tier's Czech title/flavor live in
    /// cs.lproj/Catalog.strings keyed by its first level ("tier.21.title"),
    /// English stays here -- see CatalogL10n.swift.
    private static func localized(_ title: String, _ flavor: String, _ levelRange: ClosedRange<Int>) -> LevelTier {
        let key = "tier.\(levelRange.lowerBound)"
        return LevelTier(
            title: CatalogL10n.text("\(key).title", english: title),
            flavor: CatalogL10n.text("\(key).flavor", english: flavor),
            levelRange: levelRange
        )
    }

    /// Falls back to the last tier for any level past `LevelCurve.maxLevel`
    /// (should not happen, since level is always clamped there, but keeps
    /// this total rather than partial).
    public static func tier(forLevel level: Int) -> LevelTier {
        all.first { $0.levelRange.contains(level) } ?? all[all.count - 1]
    }
}
