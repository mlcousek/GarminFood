// BadgeArtCatalog.swift
//
// Which picture a badge gets (redesign-badge-art design D2, D4). A badge is
// drawn as a FRAME, whose shape is the badge's family and whose trim is its
// rarity, with a MOTIF on top. This file is the one place that decides both:
//
//   family  from the badge id's namespace (`bingo.`, `journey.`, ...; see
//           BadgeRegistry's header), else from its `AchievementCategory`;
//   motif   from the badge's existing `badgeSymbol`. Every badge already
//           names an SF Symbol, and several symbols share one drawing
//           (`trophy`, `trophy.fill` and `rosette` are all the trophy), so
//           no per-badge table is needed and a new badge with a known
//           symbol gets art without touching this file.
//
// A symbol with no motif here returns `nil`, and the app then draws the
// previous disc with the SF Symbol (design D5): never an empty badge.
//
// The three tables are also read, as text, by tools/docs/check-badge-art.mjs
// (CI: every motif and frame named here has an SVG file under ios/BadgeArt,
// and no file is unused) and by tools/docs/build-badge-gallery.mjs. Keep
// each entry on its own line between the `badge-art:` markers.
//
// Depended on by: the app's BadgeMedallion (wave 3). Tests:
// BadgeArtCatalogTests.

import Foundation

/// The frame shape. Raw values are the SVG file and asset name parts.
public enum BadgeFamily: String, Sendable, Equatable, CaseIterable {
    case streak, logging, macros, levels, boss, bingo, journeys, records, collections, seasonal, sportBody, supplements, secrets
}

public enum BadgeArtCatalog {
    /// Badge id namespace -> family. Checked before the category.
    static let familyByIDPrefix: [String: BadgeFamily] = [
        // badge-art:prefixes:begin
        "bingo.": .bingo,
        "boss.": .boss,
        "freeze.": .boss,
        "journey.": .journeys,
        "record.": .records,
        "collection.": .collections,
        "event.": .seasonal,
        "secret.": .secrets,
        "sport.": .sportBody,
        "body.": .sportBody,
        "training.": .sportBody,
        "supplements.": .supplements,
        // badge-art:prefixes:end
    ]

    /// Category -> family, for the core `achv-*` badges.
    static let familyByCategory: [AchievementCategory: BadgeFamily] = [
        // badge-art:categories:begin
        .streak: .streak,
        .level: .levels,
        .volume: .logging,
        .variety: .collections,
        .challenges: .bingo,
        .dailyChallenges: .bingo,
        .goalHitting: .macros,
        .extreme: .records,
        .funnyFacts: .journeys,
        .calendar: .seasonal,
        .supplements: .supplements,
        .meta: .levels,
        // badge-art:categories:end
    ]

    /// SF Symbol name -> motif name.
    static let motifBySymbol: [String: String] = [
        // badge-art:motifs:begin
        "flame.fill": "flame",
        "star.fill": "star",
        "star.circle.fill": "star",
        "fork.knife": "forkKnife",
        "fork.knife.circle.fill": "plate",
        "leaf.fill": "leaf",
        "target": "target",
        "scope": "target",
        "checkmark.circle.fill": "check",
        "checkmark.seal.fill": "check",
        "checklist": "check",
        "checklist.checked": "check",
        "bolt.fill": "bolt",
        "bolt.circle.fill": "bolt",
        "party.popper.fill": "party",
        "figure.dance": "party",
        "calendar": "calendar",
        "calendar.badge.checkmark": "calendar",
        "moon.stars.fill": "moon",
        "moon.fill": "moon",
        "gift.fill": "gift",
        "crown.fill": "crown",
        "line.diagonal": "grid",
        "square.dashed": "grid",
        "square.grid.3x3.fill": "grid",
        "xmark": "cross",
        "suit.spade.fill": "spade",
        "figure.hiking": "figure",
        "figure.run": "figure",
        "figure.strengthtraining.traditional": "figure",
        "shield.lefthalf.filled": "shield",
        "shield.fill": "shield",
        "books.vertical.fill": "book",
        "book.closed.fill": "book",
        "character.book.closed.fill": "book",
        "snowflake": "snowflake",
        "snowflake.circle.fill": "snowflake",
        "mountain.2.fill": "mountain",
        "globe.europe.africa.fill": "globe",
        "globe": "globe",
        "sparkles": "sparkles",
        "bathtub.fill": "waves",
        "water.waves": "waves",
        "drop.fill": "drop",
        "drop.circle.fill": "drop",
        "car.fill": "gauge",
        "fuelpump.fill": "gauge",
        "speedometer": "gauge",
        "building.columns.fill": "house",
        "house.fill": "house",
        "trophy": "trophy",
        "trophy.fill": "trophy",
        "trophy.circle.fill": "trophy",
        "rosette": "trophy",
        "hourglass": "timer",
        "timer": "timer",
        "stopwatch.fill": "timer",
        "paintpalette.fill": "rainbow",
        "rainbow": "rainbow",
        "cart.fill": "box",
        "cart.badge.plus": "box",
        "shippingbox.fill": "box",
        "theatermasks.fill": "mask",
        "hare.fill": "egg",
        "tree.fill": "tree",
        "bird.fill": "bird",
        "fish.fill": "fish",
        "refrigerator.fill": "fridge",
        "cup.and.saucer.fill": "cup",
        "arrow.left.arrow.right": "arrows",
        "arrow.triangle.2.circlepath": "arrows",
        "repeat": "arrows",
        "13.circle.fill": "hash",
        "42.circle.fill": "hash",
        "2.circle.fill": "hash",
        "textformat.abc": "hash",
        "chart.pie.fill": "pie",
        "chart.bar.fill": "bars",
        "sunrise.fill": "sun",
        "sun.max.fill": "sun",
        "sun.horizon.fill": "sun",
        "key.fill": "key",
        "wrench.and.screwdriver.fill": "gear",
        "gearshape.2.fill": "gear",
        "heart.circle.fill": "heart",
        "ear.fill": "heart",
        "brain.head.profile": "heart",
        "scalemass.fill": "scale",
        "scalemass": "scale",
        "flag.checkered": "flag",
        "flag.fill": "flag",
        "pills.fill": "capsule",
        "dumbbell.fill": "dumbbell",
        "questionmark": "question",
        // badge-art:motifs:end
    ]

    /// The frame shape for a badge.
    public static func family(for definition: AchievementDefinition) -> BadgeFamily {
        family(id: definition.id, category: definition.category)
    }

    public static func family(id: String, category: AchievementCategory) -> BadgeFamily {
        if let dot = id.firstIndex(of: "."), let family = familyByIDPrefix[String(id[...dot])] {
            return family
        }
        return familyByCategory[category] ?? .logging
    }

    /// The motif for an SF Symbol name, or `nil` when none is drawn (the
    /// caller then falls back to the symbol itself).
    public static func motif(forSymbol symbol: String) -> String? {
        motifBySymbol[symbol]
    }

    /// Every motif name the tables use.
    public static var motifNames: Set<String> {
        Set(motifBySymbol.values)
    }

    /// Asset names, shared with the SVG files (`frame-streak-rare.svg`).
    public static func frameAssetName(family: BadgeFamily, rarity: AchievementRarity) -> String {
        "badge-frame-\(family.rawValue)-\(rarityName(rarity))"
    }

    public static func motifAssetName(_ motif: String) -> String {
        "badge-motif-\(motif)"
    }

    /// `AchievementRarity` is `Int`-backed; the art files use words.
    public static func rarityName(_ rarity: AchievementRarity) -> String {
        switch rarity {
        case .common: return "common"
        case .uncommon: return "uncommon"
        case .rare: return "rare"
        case .epic: return "epic"
        case .legendary: return "legendary"
        }
    }
}
