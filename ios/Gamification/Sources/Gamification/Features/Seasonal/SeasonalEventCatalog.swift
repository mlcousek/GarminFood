// SeasonalEventCatalog.swift
//
// add-seasonal-events design D2: the 12 Czech seasonal and holiday food
// events -- window rule, quests (required + bonus), symbol and the
// limited-edition badge each one unlocks -- plus the collector badges.
// Pure data; `SeasonalEvaluator` turns it into per-year state and
// `SeasonalEventsFeature` into rewards.
//
// Windows never cross a year boundary, so an event instance is identified
// by (eventId, year). Quests match on seasonal tags (`FoodTag+Seasonal`)
// plus a few core tags (egg, fish, nuts, sweets, colour.green). Display
// text is localized here at first use (like `AchievementCatalog`); nothing
// persisted ever contains it -- stores keep ids only.
//
// Depends on: SeasonalCalendar, CzechNameDays, FoodLogCore.FoodTag (+Seasonal),
// AchievementDefinition. Depended on by: SeasonalEvaluator,
// SeasonalEventsFeature, the app's seasonal slot views.

import Foundation
import FoodLogCore

/// Where a single day sits in a year.
public enum SeasonalDayRef: Sendable, Equatable, Hashable {
    case monthDay(SeasonalCalendar.MonthDay)
    /// Days from Western Easter Sunday (negative = before).
    case easterOffset(Int)

    public func resolve(year: Int) -> SeasonalDate {
        switch self {
        case .monthDay(let monthDay):
            return monthDay.date(in: year)
        case .easterOffset(let offset):
            return SeasonalCalendar.easter(offset: offset, year: year)
        }
    }
}

/// How an event's window is placed in a year.
public enum SeasonalWindowRule: Sendable, Equatable, Hashable {
    case fixed(start: SeasonalDayRef, end: SeasonalDayRef)
    /// The owner's name day (a one-day window); absent when unknown.
    case ownerNameDay
}

public struct SeasonalQuest: Sendable, Equatable, Identifiable {
    public enum Rule: Sendable, Equatable {
        /// An entry tagged with any of `tags` on at least `days` distinct
        /// days of the window.
        case tagOnDays(anyOf: Set<FoodTag>, days: Int)
        /// Every group matched by some entry somewhere in the window
        /// ("eggs AND ham over Easter").
        case allOfTags([Set<FoodTag>])
        /// An entry tagged with any of `tags` on one specific day.
        case tagOnDate(anyOf: Set<FoodTag>, on: SeasonalDayRef)
        /// Any entry at all, on at least `days` days of the window.
        case anyEntry(days: Int)
    }

    public let id: String
    public let title: String
    public let rule: Rule
    public let isBonus: Bool

    public init(id: String, title: String, rule: Rule, isBonus: Bool = false) {
        self.id = id
        self.title = title
        self.rule = rule
        self.isBonus = isBonus
    }

    /// How many marks complete the quest (see `SeasonalEvaluator`).
    public var target: Int {
        switch rule {
        case .tagOnDays(_, let days): return max(days, 1)
        case .allOfTags(let groups): return max(groups.count, 1)
        case .tagOnDate: return 1
        case .anyEntry(let days): return max(days, 1)
        }
    }
}

public struct SeasonalEvent: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    /// One playful line under the title.
    public let subtitle: String
    public let symbol: String
    public let windowRule: SeasonalWindowRule
    public let quests: [SeasonalQuest]
    public let badgeRarity: AchievementRarity
    /// Shown in the "coming soon" teaser.
    public let teaser: String

    public init(
        id: String,
        title: String,
        subtitle: String,
        symbol: String,
        windowRule: SeasonalWindowRule,
        quests: [SeasonalQuest],
        badgeRarity: AchievementRarity,
        teaser: String
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.windowRule = windowRule
        self.quests = quests
        self.badgeRarity = badgeRarity
        self.teaser = teaser
    }

    public var requiredQuests: [SeasonalQuest] { quests.filter { !$0.isBonus } }
    public var bonusQuests: [SeasonalQuest] { quests.filter(\.isBonus) }
    public var badgeId: String { SeasonalEventCatalog.badgeId(forEvent: id) }

    /// The window in `year`, or `nil` when the event does not happen that
    /// year (the name day with no known name, or 29 February off a leap year).
    public func window(year: Int, nameDay: SeasonalCalendar.MonthDay?) -> ClosedRange<SeasonalDate>? {
        switch windowRule {
        case .fixed(let start, let end):
            let startDate = start.resolve(year: year)
            let endDate = end.resolve(year: year)
            guard startDate <= endDate else { return nil }
            return startDate...endDate
        case .ownerNameDay:
            guard let nameDay, nameDay.exists(in: year) else { return nil }
            let day = nameDay.date(in: year)
            return day...day
        }
    }

    /// The title with the owner's name where it applies ("Jiří's Name Day").
    public func displayTitle(firstName: String?) -> String {
        guard windowRule == .ownerNameDay, let firstName, !firstName.isEmpty else { return title }
        return String(
            format: String(localized: "%@'s Name Day", bundle: .module, comment: "Seasonal event title: the owner's name day. %@ = first name (Czech: 'Svátek má Jiří')."),
            firstName
        )
    }
}

public enum SeasonalEventCatalog {
    /// Bonus quests: +25 XP each, once per event per year (design D2/D6).
    public static let bonusQuestXP = 25
    /// Teaser lead time before a window opens (design D5).
    public static let teaserDays = 3

    public static let nameDayEventId = "name-day"
    public static let collector4BadgeId = "event.collector-4"
    public static let collector8BadgeId = "event.collector-8"
    public static let fullYearBadgeId = "event.full-year"

    public static func badgeId(forEvent eventId: String) -> String { "event.\(eventId)" }

    private static func md(_ month: Int, _ day: Int) -> SeasonalDayRef {
        .monthDay(SeasonalCalendar.MonthDay(month: month, day: day))
    }

    // MARK: - The 12 events (design D2)

    public static let all: [SeasonalEvent] = [
        SeasonalEvent(
            id: "masopust",
            title: String(localized: "Masopust", bundle: .module, comment: "Seasonal event: Czech carnival before Lent."),
            subtitle: String(localized: "Carnival feast before Lent: doughnuts and pig-slaughter treats.", bundle: .module, comment: "Seasonal event description (Masopust)."),
            symbol: "theatermasks.fill",
            windowRule: .fixed(start: .easterOffset(-52), end: .easterOffset(-47)),
            quests: [
                SeasonalQuest(
                    id: "treat",
                    title: String(localized: "A Masopust treat (koblihy, jitrnice, tlačenka…)", bundle: .module, comment: "Seasonal quest (Masopust)."),
                    rule: .tagOnDays(anyOf: [.seasonMasopust], days: 1)
                )
            ],
            badgeRarity: .uncommon,
            teaser: String(localized: "Masks on, doughnuts ready.", bundle: .module, comment: "Seasonal event teaser (Masopust).")
        ),
        SeasonalEvent(
            id: "easter",
            title: String(localized: "Easter", bundle: .module, comment: "Seasonal event: Easter (Velikonoce)."),
            subtitle: String(localized: "Eggs, ham and something green for Maundy Thursday.", bundle: .module, comment: "Seasonal event description (Easter)."),
            symbol: "hare.fill",
            windowRule: .fixed(start: .easterOffset(-3), end: .easterOffset(1)),
            quests: [
                SeasonalQuest(
                    id: "eggs-and-ham",
                    title: String(localized: "Eggs and ham", bundle: .module, comment: "Seasonal quest (Easter): log eggs and ham during Easter."),
                    rule: .allOfTags([[.egg], [.seasonHam]])
                ),
                SeasonalQuest(
                    id: "green-thursday",
                    title: String(localized: "Something green on Maundy Thursday", bundle: .module, comment: "Seasonal bonus quest (Easter). Czech: Zelený čtvrtek."),
                    rule: .tagOnDate(anyOf: [.seasonGreenThursday, .colourGreen], on: .easterOffset(-3)),
                    isBonus: true
                ),
                SeasonalQuest(
                    id: "mazanec",
                    title: String(localized: "Mazanec or an Easter lamb cake", bundle: .module, comment: "Seasonal bonus quest (Easter). Czech: mazanec nebo beránek."),
                    rule: .tagOnDays(anyOf: [.seasonMazanec], days: 1),
                    isBonus: true
                )
            ],
            badgeRarity: .rare,
            teaser: String(localized: "Time to find the eggs and the ham.", bundle: .module, comment: "Seasonal event teaser (Easter).")
        ),
        SeasonalEvent(
            id: nameDayEventId,
            title: String(localized: "Name Day", bundle: .module, comment: "Seasonal event: the owner's name day (svátek), when no name is known."),
            subtitle: String(localized: "It's your svátek! Log something to celebrate.", bundle: .module, comment: "Seasonal event description (name day)."),
            symbol: "gift.fill",
            windowRule: .ownerNameDay,
            quests: [
                SeasonalQuest(
                    id: "log",
                    title: String(localized: "Log anything on your name day", bundle: .module, comment: "Seasonal quest (name day)."),
                    rule: .anyEntry(days: 1)
                ),
                SeasonalQuest(
                    id: "sweet",
                    title: String(localized: "Something sweet to celebrate", bundle: .module, comment: "Seasonal bonus quest (name day): a cake or sweets."),
                    rule: .tagOnDays(anyOf: [.seasonCake, .sweets], days: 1),
                    isBonus: true
                )
            ],
            badgeRarity: .uncommon,
            teaser: String(localized: "Your name day is coming. Cake?", bundle: .module, comment: "Seasonal event teaser (name day).")
        ),
        SeasonalEvent(
            id: "strawberries",
            title: String(localized: "Strawberry Season", bundle: .module, comment: "Seasonal event (June). Czech: Jahodová sezóna."),
            subtitle: String(localized: "June means Czech strawberries. Eat them while they last.", bundle: .module, comment: "Seasonal event description (strawberries)."),
            symbol: "leaf.fill",
            windowRule: .fixed(start: md(6, 1), end: md(6, 30)),
            quests: [
                SeasonalQuest(
                    id: "five-days",
                    title: String(localized: "Strawberries on 5 days", bundle: .module, comment: "Seasonal quest (strawberries)."),
                    rule: .tagOnDays(anyOf: [.seasonStrawberry], days: 5)
                )
            ],
            badgeRarity: .uncommon,
            teaser: String(localized: "The first strawberries are almost here.", bundle: .module, comment: "Seasonal event teaser (strawberries).")
        ),
        SeasonalEvent(
            id: "grill",
            title: String(localized: "Grill Season", bundle: .module, comment: "Seasonal event (summer). Czech: Grilovací sezóna."),
            subtitle: String(localized: "Klobása, špekáček or a steak: fire up the grill.", bundle: .module, comment: "Seasonal event description (grill)."),
            symbol: "flame.fill",
            windowRule: .fixed(start: md(6, 21), end: md(8, 31)),
            quests: [
                SeasonalQuest(
                    id: "four-days",
                    title: String(localized: "Something from the grill on 4 days", bundle: .module, comment: "Seasonal quest (grill)."),
                    rule: .tagOnDays(anyOf: [.seasonGrill], days: 4)
                )
            ],
            badgeRarity: .rare,
            teaser: String(localized: "Summer is coming. Charcoal ready?", bundle: .module, comment: "Seasonal event teaser (grill).")
        ),
        SeasonalEvent(
            id: "mushrooms",
            title: String(localized: "Mushroom Season", bundle: .module, comment: "Seasonal event (autumn). Czech: Houbařská sezóna."),
            subtitle: String(localized: "Into the woods: hříbky, smaženice, kulajda.", bundle: .module, comment: "Seasonal event description (mushrooms)."),
            symbol: "tree.fill",
            windowRule: .fixed(start: md(9, 1), end: md(10, 31)),
            quests: [
                SeasonalQuest(
                    id: "three-days",
                    title: String(localized: "Mushrooms on 3 days", bundle: .module, comment: "Seasonal quest (mushrooms)."),
                    rule: .tagOnDays(anyOf: [.seasonMushroom], days: 3)
                )
            ],
            badgeRarity: .uncommon,
            teaser: String(localized: "Grab a basket, the mushrooms are coming.", bundle: .module, comment: "Seasonal event teaser (mushrooms).")
        ),
        SeasonalEvent(
            id: "st-martin",
            title: String(localized: "St. Martin's Day", bundle: .module, comment: "Seasonal event (11 November). Czech: Svatý Martin."),
            subtitle: String(localized: "Martin rides in on a white horse, and the goose goes in the oven.", bundle: .module, comment: "Seasonal event description (St. Martin)."),
            symbol: "bird.fill",
            windowRule: .fixed(start: md(11, 8), end: md(11, 16)),
            quests: [
                SeasonalQuest(
                    id: "goose",
                    title: String(localized: "Goose", bundle: .module, comment: "Seasonal quest (St. Martin): eat goose."),
                    rule: .tagOnDays(anyOf: [.seasonGoose], days: 1)
                ),
                SeasonalQuest(
                    id: "goose-on-the-day",
                    title: String(localized: "Goose on 11 November itself", bundle: .module, comment: "Seasonal bonus quest (St. Martin)."),
                    rule: .tagOnDate(anyOf: [.seasonGoose], on: md(11, 11)),
                    isBonus: true
                ),
                SeasonalQuest(
                    id: "rohlicek",
                    title: String(localized: "A St. Martin's croissant", bundle: .module, comment: "Seasonal bonus quest (St. Martin). Czech: svatomartinský rohlíček."),
                    rule: .tagOnDays(anyOf: [.seasonMartinRohlicek], days: 1),
                    isBonus: true
                )
            ],
            badgeRarity: .uncommon,
            teaser: String(localized: "St. Martin is coming. Goose incoming.", bundle: .module, comment: "Seasonal event teaser (St. Martin).")
        ),
        SeasonalEvent(
            id: "mikulas",
            title: String(localized: "St. Nicholas", bundle: .module, comment: "Seasonal event (5–6 December). Czech: Mikuláš."),
            subtitle: String(localized: "Mikuláš fills the stocking: a mandarin and nuts or chocolate.", bundle: .module, comment: "Seasonal event description (Mikuláš)."),
            symbol: "star.fill",
            windowRule: .fixed(start: md(12, 5), end: md(12, 6)),
            quests: [
                SeasonalQuest(
                    id: "stocking",
                    title: String(localized: "A mandarin and nuts or chocolate", bundle: .module, comment: "Seasonal quest (Mikuláš)."),
                    rule: .allOfTags([[.seasonCitrus], [.nuts, .seasonChocolate]])
                )
            ],
            badgeRarity: .common,
            teaser: String(localized: "Were you good this year? Mikuláš is coming.", bundle: .module, comment: "Seasonal event teaser (Mikuláš).")
        ),
        SeasonalEvent(
            id: "cukrovi",
            title: String(localized: "Advent Cookies", bundle: .module, comment: "Seasonal event (1–23 December). Czech: Adventní cukroví."),
            subtitle: String(localized: "Vanilkové rohlíčky, linecké, vosí hnízda: the tins are full.", bundle: .module, comment: "Seasonal event description (cukroví)."),
            symbol: "snowflake",
            windowRule: .fixed(start: md(12, 1), end: md(12, 23)),
            quests: [
                SeasonalQuest(
                    id: "three-days",
                    title: String(localized: "Christmas cookies on 3 days", bundle: .module, comment: "Seasonal quest (cukroví)."),
                    rule: .tagOnDays(anyOf: [.seasonCukrovi], days: 3)
                )
            ],
            badgeRarity: .uncommon,
            teaser: String(localized: "Advent is near. Time to bake.", bundle: .module, comment: "Seasonal event teaser (cukroví).")
        ),
        SeasonalEvent(
            id: "stedry-den",
            title: String(localized: "Christmas Eve", bundle: .module, comment: "Seasonal event (24 December). Czech: Štědrý den."),
            subtitle: String(localized: "Potato salad with carp or řízek: both traditions count.", bundle: .module, comment: "Seasonal event description (Christmas Eve)."),
            symbol: "fish.fill",
            windowRule: .fixed(start: md(12, 24), end: md(12, 24)),
            quests: [
                SeasonalQuest(
                    id: "dinner",
                    title: String(localized: "Potato salad with carp, fish or schnitzel", bundle: .module, comment: "Seasonal quest (Christmas Eve). Czech: bramborový salát s kaprem, rybou nebo řízkem."),
                    rule: .allOfTags([[.seasonPotatoSalad], [.seasonCarp, .fish, .seasonRizek]])
                ),
                SeasonalQuest(
                    id: "fish-soup",
                    title: String(localized: "Fish soup", bundle: .module, comment: "Seasonal bonus quest (Christmas Eve)."),
                    rule: .tagOnDays(anyOf: [.seasonFishSoup], days: 1),
                    isBonus: true
                ),
                SeasonalQuest(
                    id: "vanocka",
                    title: String(localized: "Vánočka", bundle: .module, comment: "Seasonal bonus quest (Christmas Eve): the Czech Christmas braided loaf."),
                    rule: .tagOnDays(anyOf: [.seasonVanocka], days: 1),
                    isBonus: true
                )
            ],
            badgeRarity: .rare,
            teaser: String(localized: "Christmas Eve is coming. Carp or řízek?", bundle: .module, comment: "Seasonal event teaser (Christmas Eve).")
        ),
        SeasonalEvent(
            id: "silvestr",
            title: String(localized: "New Year's Eve", bundle: .module, comment: "Seasonal event (31 December). Czech: Silvestr."),
            subtitle: String(localized: "Chlebíčky and canapés until midnight.", bundle: .module, comment: "Seasonal event description (Silvestr)."),
            symbol: "sparkles",
            windowRule: .fixed(start: md(12, 31), end: md(12, 31)),
            quests: [
                SeasonalQuest(
                    id: "chlebicek",
                    title: String(localized: "A chlebíček", bundle: .module, comment: "Seasonal quest (Silvestr): the Czech open sandwich."),
                    rule: .tagOnDays(anyOf: [.seasonChlebicek], days: 1)
                ),
                SeasonalQuest(
                    id: "jednohubky",
                    title: String(localized: "Canapés", bundle: .module, comment: "Seasonal bonus quest (Silvestr). Czech: jednohubky."),
                    rule: .tagOnDays(anyOf: [.seasonJednohubky], days: 1),
                    isBonus: true
                )
            ],
            badgeRarity: .common,
            teaser: String(localized: "The party is coming. Chlebíčky first.", bundle: .module, comment: "Seasonal event teaser (Silvestr).")
        ),
        SeasonalEvent(
            id: "novy-rok",
            title: String(localized: "New Year's Day", bundle: .module, comment: "Seasonal event (1 January). Czech: Nový rok."),
            subtitle: String(localized: "Lentils on New Year's Day bring money all year.", bundle: .module, comment: "Seasonal event description (New Year)."),
            symbol: "calendar",
            windowRule: .fixed(start: md(1, 1), end: md(1, 1)),
            quests: [
                SeasonalQuest(
                    id: "lentils",
                    title: String(localized: "Lentils for luck", bundle: .module, comment: "Seasonal quest (New Year): eat lentils."),
                    rule: .tagOnDays(anyOf: [.seasonLentils], days: 1)
                )
            ],
            badgeRarity: .common,
            teaser: String(localized: "A new year is coming. Lentils for luck?", bundle: .module, comment: "Seasonal event teaser (New Year).")
        )
    ]

    public static func event(id: String) -> SeasonalEvent? {
        all.first { $0.id == id }
    }

    /// The events that happen in `year` for an owner whose name day is
    /// `nameDay` (every fixed event; the name day only when known).
    public static func events(inYear year: Int, nameDay: SeasonalCalendar.MonthDay?) -> [SeasonalEvent] {
        all.filter { $0.window(year: year, nameDay: nameDay) != nil }
    }

    // MARK: - Badges (design D6)

    public static let eventBadges: [AchievementDefinition] = all.map { event in
        AchievementDefinition(
            id: event.badgeId,
            title: event.title,
            subtitle: String(
                format: String(localized: "Limited edition: complete %@ in its season.", bundle: .module, comment: "Limited-edition badge description. %@ = seasonal event title."),
                event.title
            ),
            category: .calendar,
            badgeSymbol: event.symbol,
            condition: .featureEvaluated,
            edition: .limited(eventId: event.id),
            rarityOverride: event.badgeRarity,
            featureId: SeasonalEventsFeature.id
        )
    }

    public static let collectorBadges: [AchievementDefinition] = [
        AchievementDefinition(
            id: collector4BadgeId,
            title: String(localized: "Seasonal Regular", bundle: .module, comment: "Collector badge title: 4 different seasonal events completed."),
            subtitle: String(localized: "Complete 4 different seasonal events.", bundle: .module, comment: "Collector badge description."),
            category: .calendar,
            badgeSymbol: "calendar.badge.checkmark",
            condition: .featureEvaluated,
            rarityOverride: .rare,
            featureId: SeasonalEventsFeature.id
        ),
        AchievementDefinition(
            id: collector8BadgeId,
            title: String(localized: "Keeper of Traditions", bundle: .module, comment: "Collector badge title: 8 different seasonal events completed."),
            subtitle: String(localized: "Complete 8 different seasonal events.", bundle: .module, comment: "Collector badge description."),
            category: .calendar,
            badgeSymbol: "books.vertical.fill",
            condition: .featureEvaluated,
            rarityOverride: .epic,
            featureId: SeasonalEventsFeature.id
        ),
        AchievementDefinition(
            id: fullYearBadgeId,
            title: String(localized: "A Full Czech Year", bundle: .module, comment: "Collector badge title: every seasonal event in one calendar year."),
            subtitle: String(localized: "Complete every seasonal event of one calendar year.", bundle: .module, comment: "Collector badge description."),
            category: .calendar,
            badgeSymbol: "crown.fill",
            condition: .featureEvaluated,
            rarityOverride: .legendary,
            featureId: SeasonalEventsFeature.id
        )
    ]

    public static let badges: [AchievementDefinition] = eventBadges + collectorBadges
}
