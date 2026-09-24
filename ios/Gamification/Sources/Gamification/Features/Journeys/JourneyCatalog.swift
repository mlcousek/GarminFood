// JourneyCatalog.swift
//
// add-journeys-and-records design D2-D5: the four real-world journeys, their
// stages, milestones, badges and -- the part that must never pretend to be
// science -- their conversions, stated on screen by `conversionLine`:
//
//   - Protein climb ("Výstup"): 1 g protein = 0.5 vertical metre (owner
//     decision 2026-09-24: a slower, more epic climb; a playful unit, not
//     physiology). Stage 1 Petřín -> Everest (8,849 m), stage 2 the Seven
//     Summits (running sum 43,313 m), stage 3 the Kármán line (100 km).
//     Stages run one after another: stage 2 starts at 0 m when Everest is
//     reached, so milestone thresholds here are ABSOLUTE (stage start +
//     height within the stage). At ~130 g/day: Everest ~20 weeks.
//   - Water ("Vodník", the Czech water goblin): litres (max(local, Garmin)
//     per day, as in DaySignals). Finite milestones up to a fire-engine tank
//     (2,500 L), then the Podolí 50 m pool (50 x 21 x 2 m ~ 2,100,000 L,
//     an estimate) shown as a percentage -- honest about scale.
//   - Road trip ("Na cestě"): km = active kcal / body weight in kg (latest
//     known weigh-in, else 70 kg): the ~1 kcal per kg per km rule of thumb
//     for walking/running, an approximation. Approximate road distances,
//     cumulative from Praha, then stage 2 "Cesta domů" Lisabon -> Paříž ->
//     Praha (+2,800 km).
//   - Food passport: one stamp per distinct food id ever logged.
//
// Each journey declares the `DataRequirement` it needs, so a mode without
// that source (standalone mode has no active kcal) hides it rather than
// showing a journey that can never move.
//
// Names are localized (Gamification .lproj) and computed on access, never
// persisted: the stores keep only ids.
//
// Depends on: DataRequirement, AchievementDefinition/Rarity.
// Depended on by: JourneysEvaluator, JourneysFeature, the app's Journeys UI.

import Foundation

public enum JourneyKind: String, Sendable, Equatable, Hashable, Codable, CaseIterable {
    case protein, water, road, passport
}

public enum JourneyUnit: String, Sendable, Equatable, Codable {
    case metres, litres, kilometres, stamps
}

public struct JourneyMilestone: Sendable, Equatable, Identifiable {
    /// Unique within its journey ("snezka", "seven-denali").
    public let id: String
    public let name: String
    public let stageIndex: Int
    /// Position within its stage (what the design tables list).
    public let stageValue: Double
    /// Cumulative position over the whole journey (stage start + `stageValue`).
    public let threshold: Double
    /// The badge unlocked when this milestone is reached, if any.
    public let badgeId: String?
}

public struct JourneyStage: Sendable, Equatable {
    public let name: String
    /// Cumulative journey value where this stage starts.
    public let start: Double
    /// The stage's length (its last milestone's `stageValue`).
    public let length: Double
}

/// After the last finite milestone, an "endless" goal shown as a percentage.
public struct JourneyEndlessGoal: Sendable, Equatable {
    public let name: String
    public let capacity: Double
}

public struct JourneyDefinition: Sendable, Equatable, Identifiable {
    public let kind: JourneyKind
    public var id: String { kind.rawValue }
    public let name: String
    /// An SF Symbol name.
    public let symbol: String
    public let unit: JourneyUnit
    public let stages: [JourneyStage]
    /// Every milestone, ascending by `threshold`.
    public let milestones: [JourneyMilestone]
    public let endless: JourneyEndlessGoal?
    public let requirement: DataRequirement
    /// The one-line conversion shown on screen.
    public let conversionLine: String
}

public enum JourneyCatalog {
    /// Design D2: 1 g protein = 0.5 vertical metre.
    public static let metresPerGramOfProtein = 0.5
    /// Design D4: used when no weigh-in is known.
    public static let fallbackWeightKg = 70.0
    /// Design D3: 50 m x 21 m x 2 m, an estimate.
    public static let podoliPoolLitres = 2_100_000.0

    // MARK: - Conversions (design D2-D4)

    public static func metres(proteinGrams: Double) -> Double {
        max(0, proteinGrams) * metresPerGramOfProtein
    }

    public static func litres(waterML: Double) -> Double {
        max(0, waterML) / 1000
    }

    /// ~1 kcal per kg of body weight per km (walking/running rule of thumb).
    public static func kilometres(activeKcal: Double, weightKg: Double?) -> Double {
        let weight = weightKg.flatMap { $0 > 0 ? $0 : nil } ?? fallbackWeightKg
        return max(0, activeKcal) / weight
    }

    // MARK: - Definitions

    public static var all: [JourneyDefinition] { [protein, water, road, passport] }

    public static func definition(_ kind: JourneyKind) -> JourneyDefinition {
        switch kind {
        case .protein: return protein
        case .water: return water
        case .road: return road
        case .passport: return passport
        }
    }

    private struct Spec {
        let id: String
        let name: String
        let value: Double
        let badgeId: String?

        init(_ id: String, _ name: String, _ value: Double, badge: String? = nil) {
            self.id = id
            self.name = name
            self.value = value
            self.badgeId = badge
        }
    }

    /// Lays stages end to end: each stage starts where the previous ended.
    private static func build(
        kind: JourneyKind,
        name: String,
        symbol: String,
        unit: JourneyUnit,
        stages: [(name: String, milestones: [Spec])],
        endless: JourneyEndlessGoal? = nil,
        requirement: DataRequirement,
        conversionLine: String
    ) -> JourneyDefinition {
        var start = 0.0
        var builtStages: [JourneyStage] = []
        var milestones: [JourneyMilestone] = []
        for (index, stage) in stages.enumerated() {
            let length = stage.milestones.map(\.value).max() ?? 0
            builtStages.append(JourneyStage(name: stage.name, start: start, length: length))
            for spec in stage.milestones {
                milestones.append(JourneyMilestone(
                    id: spec.id,
                    name: spec.name,
                    stageIndex: index,
                    stageValue: spec.value,
                    threshold: start + spec.value,
                    badgeId: spec.badgeId
                ))
            }
            start += length
        }
        return JourneyDefinition(
            kind: kind,
            name: name,
            symbol: symbol,
            unit: unit,
            stages: builtStages,
            milestones: milestones.sorted { $0.threshold < $1.threshold },
            endless: endless,
            requirement: requirement,
            conversionLine: conversionLine
        )
    }

    public static var protein: JourneyDefinition {
        build(
            kind: .protein,
            name: String(localized: "Protein climb", bundle: .module, comment: "Journey name: protein eaten climbs mountains."),
            symbol: "mountain.2.fill",
            unit: .metres,
            stages: [
                (
                    name: String(localized: "Summits", bundle: .module, comment: "Protein climb stage 1: famous mountains up to Everest."),
                    milestones: [
                        Spec("petrin", String(localized: "Petřín", bundle: .module, comment: "Hill in Prague (milestone)."), 327),
                        Spec("lysa-hora", String(localized: "Lysá hora", bundle: .module, comment: "Mountain in the Beskydy (milestone)."), 1_323),
                        Spec("snezka", String(localized: "Sněžka", bundle: .module, comment: "Highest Czech mountain (milestone)."), 1_603),
                        Spec("gerlach", String(localized: "Gerlachovský štít", bundle: .module, comment: "Highest Slovak mountain (milestone)."), 2_655),
                        Spec("grossglockner", String(localized: "Grossglockner", bundle: .module, comment: "Highest Austrian mountain (milestone)."), 3_798),
                        Spec("mont-blanc", String(localized: "Mont Blanc", bundle: .module, comment: "Highest Alpine mountain (milestone)."), 4_808),
                        Spec("kilimanjaro", String(localized: "Kilimanjaro", bundle: .module, comment: "Mountain (milestone)."), 5_895),
                        Spec("aconcagua", String(localized: "Aconcagua", bundle: .module, comment: "Mountain (milestone)."), 6_961),
                        Spec("everest", String(localized: "Everest", bundle: .module, comment: "Mountain (milestone)."), 8_849, badge: "journey.everest"),
                    ]
                ),
                (
                    name: String(localized: "Seven Summits", bundle: .module, comment: "Protein climb stage 2: the highest peak of every continent."),
                    milestones: [
                        Spec("seven-everest", String(localized: "Everest", bundle: .module, comment: "Mountain (milestone)."), 8_849),
                        Spec("seven-aconcagua", String(localized: "Aconcagua", bundle: .module, comment: "Mountain (milestone)."), 15_810),
                        Spec("seven-denali", String(localized: "Denali", bundle: .module, comment: "Mountain (milestone)."), 22_000),
                        Spec("seven-kilimanjaro", String(localized: "Kilimanjaro", bundle: .module, comment: "Mountain (milestone)."), 27_895),
                        Spec("seven-elbrus", String(localized: "Elbrus", bundle: .module, comment: "Mountain (milestone)."), 33_537),
                        Spec("seven-vinson", String(localized: "Vinson", bundle: .module, comment: "Mountain (milestone)."), 38_429),
                        Spec("seven-puncak-jaya", String(localized: "Puncak Jaya", bundle: .module, comment: "Mountain (milestone)."), 43_313, badge: "journey.seven-summits"),
                    ]
                ),
                (
                    name: String(localized: "To space", bundle: .module, comment: "Protein climb stage 3: up to the edge of space."),
                    milestones: [
                        Spec("karman", String(localized: "Kármán line", bundle: .module, comment: "The edge of space, 100 km up (milestone)."), 100_000, badge: "journey.karman"),
                    ]
                ),
            ],
            requirement: .macros,
            conversionLine: String(localized: "1 g of protein = 0.5 m of climbing. A playful unit, not physiology.", bundle: .module, comment: "Protein climb conversion line.")
        )
    }

    public static var water: JourneyDefinition {
        build(
            kind: .water,
            name: String(localized: "Vodník", bundle: .module, comment: "Journey name: water drunk fills ever bigger containers (the Czech water goblin)."),
            symbol: "drop.fill",
            unit: .litres,
            stages: [
                (
                    name: String(localized: "Filling up", bundle: .module, comment: "Water journey stage name."),
                    milestones: [
                        Spec("bucket", String(localized: "Bucket", bundle: .module, comment: "Water milestone: a 10 L bucket."), 10),
                        Spec("beer-keg", String(localized: "Beer keg", bundle: .module, comment: "Water milestone: a 50 L beer keg."), 50),
                        Spec("bathtub", String(localized: "Bathtub", bundle: .module, comment: "Water milestone: a 150 L bathtub."), 150, badge: "journey.bathtub"),
                        Spec("rain-barrel", String(localized: "Rain barrel", bundle: .module, comment: "Water milestone: a 300 L rain barrel."), 300),
                        Spec("hot-tub", String(localized: "Hot tub", bundle: .module, comment: "Water milestone: a hot tub (~1,000 L, estimate)."), 1_000, badge: "journey.hot-tub"),
                        Spec("fire-engine", String(localized: "Fire-engine tank", bundle: .module, comment: "Water milestone: a fire engine's tank (~2,500 L, estimate)."), 2_500, badge: "journey.fire-engine"),
                    ]
                ),
            ],
            endless: JourneyEndlessGoal(
                name: String(localized: "Podolí 50 m pool", bundle: .module, comment: "The Prague Podolí swimming pool, the endless water goal."),
                capacity: podoliPoolLitres
            ),
            requirement: .water,
            conversionLine: String(localized: "Every litre you drink counts. Pool size is an estimate.", bundle: .module, comment: "Water journey conversion line.")
        )
    }

    public static var road: JourneyDefinition {
        build(
            kind: .road,
            name: String(localized: "Road trip", bundle: .module, comment: "Journey name: active calories walk you across Europe from Prague."),
            symbol: "car.fill",
            unit: .kilometres,
            stages: [
                (
                    name: String(localized: "Praha to Lisbon", bundle: .module, comment: "Road trip stage 1 name."),
                    milestones: [
                        Spec("brno", String(localized: "Brno", bundle: .module, comment: "City (road trip milestone)."), 205),
                        Spec("vienna", String(localized: "Vienna", bundle: .module, comment: "City (road trip milestone)."), 350, badge: "journey.vienna"),
                        Spec("bratislava", String(localized: "Bratislava", bundle: .module, comment: "City (road trip milestone)."), 430),
                        Spec("budapest", String(localized: "Budapest", bundle: .module, comment: "City (road trip milestone)."), 630),
                        Spec("zagreb", String(localized: "Zagreb", bundle: .module, comment: "City (road trip milestone)."), 975),
                        Spec("ljubljana", String(localized: "Ljubljana", bundle: .module, comment: "City (road trip milestone)."), 1_115),
                        Spec("venice", String(localized: "Venice", bundle: .module, comment: "City (road trip milestone)."), 1_350),
                        Spec("florence", String(localized: "Florence", bundle: .module, comment: "City (road trip milestone)."), 1_610),
                        Spec("rome", String(localized: "Rome", bundle: .module, comment: "City (road trip milestone)."), 1_890, badge: "journey.rome"),
                        Spec("nice", String(localized: "Nice", bundle: .module, comment: "City (road trip milestone)."), 2_590),
                        Spec("barcelona", String(localized: "Barcelona", bundle: .module, comment: "City (road trip milestone)."), 3_250),
                        Spec("madrid", String(localized: "Madrid", bundle: .module, comment: "City (road trip milestone)."), 3_870),
                        Spec("lisbon", String(localized: "Lisbon", bundle: .module, comment: "City (road trip milestone)."), 4_495, badge: "journey.lisbon"),
                    ]
                ),
                (
                    name: String(localized: "The way home", bundle: .module, comment: "Road trip stage 2 name: Lisbon back to Prague via Paris."),
                    milestones: [
                        Spec("paris", String(localized: "Paris", bundle: .module, comment: "City (road trip milestone)."), 1_750),
                        Spec("home", String(localized: "Praha", bundle: .module, comment: "Prague, the road trip's final milestone (home again)."), 2_800, badge: "journey.home-again"),
                    ]
                ),
            ],
            requirement: .activities,
            conversionLine: String(localized: "Active kcal ÷ your weight in kg = km (about 1 kcal per kg per km; 70 kg if no weigh-in).", bundle: .module, comment: "Road trip conversion line.")
        )
    }

    /// Design D5: milestone names reuse "N stamps" (Czech genitive plural
    /// "razítek" fits every milestone count, all >= 5).
    public static var passport: JourneyDefinition {
        func stamps(_ count: Int, badge: String? = nil) -> Spec {
            let number = String(count)
            return Spec("stamps-\(count)", String(localized: "\(number) stamps", bundle: .module, comment: "Food passport milestone: N distinct foods (N is always 10 or more)."), Double(count), badge: badge)
        }
        return build(
            kind: .passport,
            name: String(localized: "Food passport", bundle: .module, comment: "Journey name: one stamp per distinct food ever logged."),
            symbol: "book.closed.fill",
            unit: .stamps,
            stages: [
                (
                    name: String(localized: "Stamps", bundle: .module, comment: "Food passport stage name."),
                    milestones: [
                        stamps(10),
                        stamps(25),
                        stamps(50),
                        stamps(100, badge: "journey.passport-100"),
                        stamps(250),
                        stamps(500, badge: "journey.passport-500"),
                    ]
                ),
            ],
            requirement: [],
            conversionLine: String(localized: "One stamp for every different food you have ever logged.", bundle: .module, comment: "Food passport conversion line.")
        )
    }

    // MARK: - Badges (design D7)

    public static var badges: [AchievementDefinition] {
        func badge(_ id: String, _ title: String, _ subtitle: String, _ symbol: String, _ rarity: AchievementRarity) -> AchievementDefinition {
            AchievementDefinition(
                id: id,
                title: title,
                subtitle: subtitle,
                category: id.hasPrefix("journey.passport") ? .variety : .volume,
                badgeSymbol: symbol,
                condition: .featureEvaluated,
                rarityOverride: rarity,
                featureId: JourneysFeature.id
            )
        }
        return [
            badge("journey.everest", String(localized: "Top of the World", bundle: .module, comment: "Badge title: protein climb reached Everest."),
                  String(localized: "Climb Everest on protein.", bundle: .module, comment: "Badge subtitle."), "mountain.2.fill", .rare),
            badge("journey.seven-summits", String(localized: "Seven Summits", bundle: .module, comment: "Protein climb stage 2: the highest peak of every continent."),
                  String(localized: "Climb all Seven Summits on protein.", bundle: .module, comment: "Badge subtitle."), "globe.europe.africa.fill", .epic),
            badge("journey.karman", String(localized: "Protein Astronaut", bundle: .module, comment: "Badge title: protein climb reached the edge of space."),
                  String(localized: "Climb to the Kármán line, 100 km up.", bundle: .module, comment: "Badge subtitle."), "sparkles", .legendary),
            badge("journey.bathtub", String(localized: "Bath Time", bundle: .module, comment: "Badge title: drank a bathtub of water."),
                  String(localized: "Drink a whole bathtub of water.", bundle: .module, comment: "Badge subtitle."), "bathtub.fill", .uncommon),
            badge("journey.hot-tub", String(localized: "Hot Tub Party", bundle: .module, comment: "Badge title: drank a hot tub of water."),
                  String(localized: "Drink a whole hot tub of water.", bundle: .module, comment: "Badge subtitle."), "drop.circle.fill", .rare),
            badge("journey.fire-engine", String(localized: "Fire Brigade", bundle: .module, comment: "Badge title: drank a fire engine's tank of water."),
                  String(localized: "Drink a fire engine's whole tank.", bundle: .module, comment: "Badge subtitle."), "flame.fill", .epic),
            badge("journey.vienna", String(localized: "Off to Vienna", bundle: .module, comment: "Badge title: road trip reached Vienna."),
                  String(localized: "Walk off active kcal all the way to Vienna.", bundle: .module, comment: "Badge subtitle."), "car.fill", .uncommon),
            badge("journey.rome", String(localized: "All Roads Lead to Rome", bundle: .module, comment: "Badge title: road trip reached Rome."),
                  String(localized: "Reach Rome on the road trip.", bundle: .module, comment: "Badge subtitle."), "building.columns.fill", .rare),
            badge("journey.lisbon", String(localized: "Atlantic Coast", bundle: .module, comment: "Badge title: road trip reached Lisbon."),
                  String(localized: "Reach Lisbon on the road trip.", bundle: .module, comment: "Badge subtitle."), "water.waves", .epic),
            badge("journey.home-again", String(localized: "Home Again", bundle: .module, comment: "Badge title: road trip came back to Prague."),
                  String(localized: "Make it all the way back home to Praha.", bundle: .module, comment: "Badge subtitle."), "house.fill", .legendary),
            badge("journey.passport-100", String(localized: "Seasoned Traveller", bundle: .module, comment: "Badge title: 100 distinct foods logged."),
                  String(localized: "Collect 100 food passport stamps.", bundle: .module, comment: "Badge subtitle."), "book.closed.fill", .epic),
            badge("journey.passport-500", String(localized: "Citizen of the World", bundle: .module, comment: "Badge title: 500 distinct foods logged."),
                  String(localized: "Collect 500 food passport stamps.", bundle: .module, comment: "Badge subtitle."), "globe", .legendary),
        ]
    }
}
