// SecretCatalog.swift
//
// add-secret-achievements D2: the static badge definitions of the 15 hidden
// achievements plus the visible "Secret Keeper" (all 15 found). Kept apart
// from the rules (`SecretRules.swift`) so adding a secret later is one enum
// case + one definition row + one rule function, and ids are never reused.
//
// Every secret is `.featureEvaluated` + `visibility: .secret`, so the
// foundation's Achievements screen renders it as a "???" tile (title and
// subtitle never shown, not even to VoiceOver) until it is unlocked, and
// `FeatureHost` suppresses the generic achievement moment for it -- the
// feature's own `.secret` reveal names it instead. The keeper is a normal,
// visible badge (legendary) and gets the generic moment.
//
// `featureId` on the definitions is the registered feature id ("secrets"),
// which is what `FeatureHost` matches; the design's `featureId: "secret"`
// predates the stub's id.
//
// Depends on: AchievementDefinition (Achievements.swift), AchievementRarity.
// Depended on by: SecretAchievementsFeature, SecretRules, their tests.

import Foundation

/// The 15 hidden achievements. `rawValue` is the badge id.
public enum SecretAchievementId: String, CaseIterable, Sendable, Hashable {
    case fridgeRaid = "secret.fridge-raid"
    case barista = "secret.barista"
    case pizzaFriday = "secret.pizza-friday"
    case bullseye = "secret.bullseye"
    case palindrome = "secret.palindrome"
    case groundhogBreakfast = "secret.groundhog-breakfast"
    case friday13 = "secret.friday-13"
    case worldTour = "secret.world-tour"
    case piDay = "secret.pi-day"
    case dejaVu = "secret.deja-vu"
    case knedlikMarathon = "secret.knedlik-marathon"
    case goneFishing = "secret.gone-fishing"
    case vodnik = "secret.vodnik"
    case dawnPatrol = "secret.dawn-patrol"
    case answer42 = "secret.answer-42"

    public var badgeId: String { rawValue }
}

public enum SecretCatalog {
    /// The visible completionist badge: every secret found.
    public static let keeperId = "secret.keeper"

    /// The 15 secret definitions, in `SecretAchievementId.allCases` order.
    public static var secrets: [AchievementDefinition] {
        SecretAchievementId.allCases.map { definition(for: $0) }
    }

    public static var keeper: AchievementDefinition {
        AchievementDefinition(
            id: keeperId,
            title: String(localized: "Secret Keeper", bundle: .module, comment: "Achievement title: all secret achievements found."),
            subtitle: String(localized: "Find all 15 secret achievements.", bundle: .module, comment: "Achievement description of Secret Keeper."),
            category: .meta,
            badgeSymbol: "key.fill",
            condition: .featureEvaluated,
            visibility: .normal,
            rarityOverride: .legendary,
            featureId: SecretAchievementsFeature.id
        )
    }

    /// Secrets first, then the keeper.
    public static var all: [AchievementDefinition] { secrets + [keeper] }

    public static func definition(for id: SecretAchievementId) -> AchievementDefinition {
        let text = texts(for: id)
        return AchievementDefinition(
            id: id.badgeId,
            title: text.title,
            subtitle: text.subtitle,
            category: .funnyFacts,
            badgeSymbol: symbol(for: id),
            condition: .featureEvaluated,
            visibility: .secret,
            rarityOverride: rarity(for: id),
            featureId: SecretAchievementsFeature.id
        )
    }

    /// The revealed title only (used by the reveal moment).
    public static func title(for id: SecretAchievementId) -> String {
        texts(for: id).title
    }

    public static func rarity(for id: SecretAchievementId) -> AchievementRarity {
        switch id {
        case .fridgeRaid, .barista, .dejaVu, .knedlikMarathon, .goneFishing:
            return .uncommon
        case .pizzaFriday, .palindrome, .friday13, .piDay, .vodnik, .dawnPatrol, .answer42:
            return .rare
        case .bullseye, .groundhogBreakfast, .worldTour:
            return .epic
        }
    }

    static func symbol(for id: SecretAchievementId) -> String {
        switch id {
        case .fridgeRaid: return "refrigerator.fill"
        case .barista: return "cup.and.saucer.fill"
        case .pizzaFriday: return "fork.knife.circle.fill"
        case .bullseye: return "scope"
        case .palindrome: return "arrow.left.arrow.right"
        case .groundhogBreakfast: return "arrow.triangle.2.circlepath"
        case .friday13: return "13.circle.fill"
        case .worldTour: return "globe.europe.africa.fill"
        case .piDay: return "chart.pie.fill"
        case .dejaVu: return "repeat"
        case .knedlikMarathon: return "fork.knife"
        case .goneFishing: return "fish.fill"
        case .vodnik: return "drop.fill"
        case .dawnPatrol: return "sunrise.fill"
        case .answer42: return "42.circle.fill"
        }
    }

    private static func texts(for id: SecretAchievementId) -> (title: String, subtitle: String) {
        switch id {
        case .fridgeRaid:
            return (
                String(localized: "Midnight Fridge Raid", bundle: .module, comment: "Secret achievement title."),
                String(localized: "Log something between midnight and 4 a.m. for that same day.", bundle: .module, comment: "Secret achievement description (shown only once unlocked).")
            )
        case .barista:
            return (
                String(localized: "Barista Mode", bundle: .module, comment: "Secret achievement title."),
                String(localized: "Log 5 coffees in one day.", bundle: .module, comment: "Secret achievement description (shown only once unlocked).")
            )
        case .pizzaFriday:
            return (
                String(localized: "Pizza Friday", bundle: .module, comment: "Secret achievement title."),
                String(localized: "Have pizza on 4 Fridays in a row.", bundle: .module, comment: "Secret achievement description (shown only once unlocked).")
            )
        case .bullseye:
            return (
                String(localized: "Bullseye", bundle: .module, comment: "Secret achievement title."),
                String(localized: "End a day of 3+ entries exactly on your calorie goal, to the kcal.", bundle: .module, comment: "Secret achievement description (shown only once unlocked).")
            )
        case .palindrome:
            return (
                String(localized: "Palindrome Day", bundle: .module, comment: "Secret achievement title."),
                String(localized: "End a day of 3+ entries on a calorie total that reads the same backwards, like 1221.", bundle: .module, comment: "Secret achievement description (shown only once unlocked).")
            )
        case .groundhogBreakfast:
            return (
                String(localized: "Groundhog Breakfast", bundle: .module, comment: "Secret achievement title (a nod to the film Groundhog Day)."),
                String(localized: "Have the same food for breakfast on 30 of 35 days.", bundle: .module, comment: "Secret achievement description (shown only once unlocked).")
            )
        case .friday13:
            return (
                String(localized: "Friday the 13th", bundle: .module, comment: "Secret achievement title."),
                String(localized: "Log food on a Friday the 13th.", bundle: .module, comment: "Secret achievement description (shown only once unlocked).")
            )
        case .worldTour:
            return (
                String(localized: "World Tour Week", bundle: .module, comment: "Secret achievement title."),
                String(localized: "Eat 7 different cuisines in one week.", bundle: .module, comment: "Secret achievement description (shown only once unlocked).")
            )
        case .piDay:
            return (
                String(localized: "Pi Day", bundle: .module, comment: "Secret achievement title (14 March = 3.14)."),
                String(localized: "Have a pie, tart or strudel on 14 March.", bundle: .module, comment: "Secret achievement description (shown only once unlocked).")
            )
        case .dejaVu:
            return (
                String(localized: "Déjà Vu", bundle: .module, comment: "Secret achievement title."),
                String(localized: "Eat exactly the same foods two days in a row, at least 3 different ones.", bundle: .module, comment: "Secret achievement description (shown only once unlocked).")
            )
        case .knedlikMarathon:
            return (
                String(localized: "Knedlík Marathon", bundle: .module, comment: "Secret achievement title (knedlík = Czech dumpling)."),
                String(localized: "Have knedlíky 3 days in a row.", bundle: .module, comment: "Secret achievement description (shown only once unlocked).")
            )
        case .goneFishing:
            return (
                String(localized: "Gone Fishing", bundle: .module, comment: "Secret achievement title."),
                String(localized: "Eat fish 3 days in a row.", bundle: .module, comment: "Secret achievement description (shown only once unlocked).")
            )
        case .vodnik:
            return (
                String(localized: "Vodník's Apprentice", bundle: .module, comment: "Secret achievement title (vodník = Czech water goblin)."),
                String(localized: "Drink one and a half times your water goal in one day.", bundle: .module, comment: "Secret achievement description (shown only once unlocked).")
            )
        case .dawnPatrol:
            return (
                String(localized: "Dawn Patrol", bundle: .module, comment: "Secret achievement title."),
                String(localized: "Start a workout before 6 a.m. and log food within an hour of finishing it.", bundle: .module, comment: "Secret achievement description (shown only once unlocked).")
            )
        case .answer42:
            return (
                String(localized: "The Answer", bundle: .module, comment: "Secret achievement title (42, the Answer to Life, the Universe and Everything)."),
                String(localized: "Log exactly 42 entries in one week.", bundle: .module, comment: "Secret achievement description (shown only once unlocked).")
            )
        }
    }
}
