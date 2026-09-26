// LayoutCardInfo.swift
//
// The user-facing side of AppearanceKit's card registry (add-themes-and-
// layout design.md D8, D9): localized titles and SF Symbols for each card,
// names for variants and presets (Czech in Resources/Localizable.xcstrings),
// and `CardAvailability` -- whether a card can show right now, which is
// separate from the user's visibility choice.
//
// AppearanceKit keeps ids only (no user-facing text); this file maps them.
// Availability lives here, not in the package, because it reads app state
// (fasting preferences, loaded shelves); the kit's resolver never needs it.
//
// Depended on by: LayoutEditorSheet, TodayView (its `availability(_:)`),
// the Appearance page's Layout section (Today, Log Food and Progress rows).

import SwiftUI
import AppearanceKit

// MARK: - Availability

/// Whether a card has something to show right now (D8). Rendering shows a
/// card only when it is visible **and** available; the editor lists every
/// card and explains the others with their caption.
enum CardAvailability: Equatable {
    case available
    /// Nothing to show yet; the hint says when it appears.
    case empty(String)
    /// Can't show in the current setup (e.g. fasting off); the reason says
    /// how to change that. The editor greys the row out.
    case unavailable(String)

    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    var isUnavailable: Bool {
        if case .unavailable = self { return true }
        return false
    }

    var caption: String? {
        switch self {
        case .available: return nil
        case .empty(let hint): return hint
        case .unavailable(let reason): return reason
        }
    }
}

extension TodayCardID {
    /// The part of a Today card's availability that doesn't depend on the
    /// Today screen's own loaded shelves -- all the Settings entry point can
    /// know. `TodayView.availability(_:)` adds the shelf rules on top.
    @MainActor
    static func baseAvailability(_ card: TodayCardID, preferences: AppPreferences) -> CardAvailability {
        switch card {
        case .fasting:
            return preferences.activeFastingSchedule == nil
                ? .unavailable(String(localized: "Turn on fasting in Settings", comment: "Layout editor: why the Fasting card isn't shown."))
                : .available
        case .supplements:
            // add-supplements D4. TodayView adds "at least one product".
            return preferences.supplementsEnabled
                ? .available
                : .unavailable(String(localized: "Turn on supplements in Settings", comment: "Layout editor: why the Supplements card isn't shown."))
        default:
            return .available
        }
    }
}

// MARK: - Titles and symbols

extension LayoutScreen {
    var title: String {
        switch self {
        case .today: return String(localized: "Today")
        case .logFood: return String(localized: "Log Food")
        case .progress: return String(localized: "Progress")
        }
    }
}

/// A card's editor row title and symbol, for any screen.
enum LayoutCardInfo {
    static func title(_ id: String, on screen: LayoutScreen) -> String {
        switch screen {
        case .today:
            return TodayCardID(rawValue: id)?.title ?? id
        case .logFood:
            return LogFoodShelfID(rawValue: id)?.title ?? id
        case .progress:
            return ProgressCardID(rawValue: id)?.title ?? id
        }
    }

    static func systemImage(_ id: String, on screen: LayoutScreen) -> String {
        switch screen {
        case .today:
            return TodayCardID(rawValue: id)?.systemImage ?? "square"
        case .logFood:
            return LogFoodShelfID(rawValue: id)?.systemImage ?? "square"
        case .progress:
            return ProgressCardID(rawValue: id)?.systemImage ?? "square"
        }
    }

    /// A variant's name in the editor's menu.
    static func variantName(_ variant: String) -> String {
        if let summary = SummaryVariant(rawValue: variant) {
            switch summary {
            case .ring: return String(localized: "Ring", comment: "Layout editor: Day summary variant with the calorie ring.")
            case .compact: return String(localized: "Compact")
            case .hero: return String(localized: "Big number", comment: "Layout editor: Day summary variant showing calories as one big number.")
            }
        }
        if let meals = MealsVariant(rawValue: variant) {
            switch meals {
            case .expanded: return String(localized: "Expanded", comment: "Layout editor: meal cards showing their entries.")
            case .collapsed: return String(localized: "Collapsed", comment: "Layout editor: meal cards showing only header and macro bars.")
            }
        }
        if let supplements = SupplementsVariant(rawValue: variant) {
            switch supplements {
            case .slot: return String(localized: "Current slot", comment: "Layout editor: Supplements card variant showing the slot due now with its checklist.")
            case .day: return String(localized: "Whole day", comment: "Layout editor: Supplements card variant showing all of today's slots as pills.")
            }
        }
        if let weightWater = WeightWaterVariant(rawValue: variant) {
            switch weightWater {
            case .both: return String(localized: "Both", comment: "Layout editor: Weight & Water shows both cards.")
            case .weight: return String(localized: "Weight only", comment: "Layout editor: Weight & Water variant.")
            case .water: return String(localized: "Water only", comment: "Layout editor: Weight & Water variant.")
            }
        }
        return variant
    }
}

extension TodayCardID {
    var title: String {
        switch self {
        case .daySwitcher: return String(localized: "Day switcher", comment: "Layout editor row: the date bar at the top of Today.")
        case .summary: return String(localized: "Day summary", comment: "Layout editor row: calories ring and macro bars.")
        case .progressStrip: return String(localized: "Streak & level", comment: "Layout editor row: Today's streak and level strip.")
        case .fasting: return String(localized: "Fasting")
        case .banners: return String(localized: "Event banners", comment: "Layout editor row: seasonal event and weekly boss banners on Today.")
        case .meals: return String(localized: "Meals")
        case .supplements: return String(localized: "Supplements")
        case .logAgain: return String(localized: "Log again")
        case .logMeal: return String(localized: "Log a meal")
        case .weightWater: return String(localized: "Weight & Water")
        case .dayNote: return String(localized: "Day note", comment: "Layout editor row: the note and tags card for the day.")
        case .signature: return String(localized: "Signature", comment: "Layout editor row: the GF by Jirka signature at the bottom of Today.")
        }
    }

    var systemImage: String {
        switch self {
        case .daySwitcher: return "calendar"
        case .summary: return "chart.pie"
        case .progressStrip: return "flame"
        case .fasting: return "moon.stars"
        case .banners: return "flag"
        case .meals: return "fork.knife"
        case .supplements: return "pills"
        case .logAgain: return "arrow.counterclockwise"
        case .logMeal: return "takeoutbag.and.cup.and.straw"
        case .weightWater: return "scalemass"
        case .dayNote: return "note.text"
        case .signature: return "signature"
        }
    }
}

extension LogFoodShelfID {
    var title: String {
        switch self {
        case .quickPick: return String(localized: "Quick pick")
        case .favorites: return String(localized: "Favorites")
        case .usual: return String(localized: "Usual for this meal", comment: "Layout editor row: the Log Food shelf of foods usually logged for the current meal.")
        case .meals: return String(localized: "Meals")
        case .recent: return String(localized: "Recent")
        case .customFoods: return String(localized: "Your custom foods")
        }
    }

    var systemImage: String {
        switch self {
        case .quickPick: return "bolt"
        case .favorites: return "star"
        case .usual: return "clock.arrow.circlepath"
        case .meals: return "square.stack.3d.up"
        case .recent: return "clock"
        case .customFoods: return "square.and.pencil"
        }
    }
}

extension ProgressCardID {
    var title: String {
        switch self {
        case .streak: return String(localized: "Streak")
        case .level: return String(localized: "Level")
        case .boss: return String(localized: "Weekly boss", comment: "Layout editor row: the weekly boss card on Progress.")
        case .bingo: return String(localized: "Weekly bingo", comment: "Layout editor row: the weekly bingo card on Progress.")
        case .seasonal: return String(localized: "Seasonal event", comment: "Layout editor row: the seasonal event card on Progress.")
        case .journeys: return String(localized: "Journeys", comment: "Layout editor row: the journeys card on Progress.")
        case .records: return String(localized: "Records", comment: "Layout editor row: the personal records card on Progress.")
        case .collections: return String(localized: "Collections", comment: "Layout editor row: the collections card on Progress.")
        case .sportBody: return String(localized: "Sport & Body", comment: "Layout editor row: the sport and body card on Progress.")
        case .secrets: return String(localized: "Secrets", comment: "Layout editor row: the secret achievements card on Progress.")
        case .challenges: return String(localized: "Challenges")
        case .achievements: return String(localized: "Achievements")
        case .weight: return String(localized: "Weight")
        case .hydration: return String(localized: "Hydration")
        case .trends: return String(localized: "Trends")
        case .goalHistory: return String(localized: "Goals, last 14 days")
        case .supplements: return String(localized: "Supplements")
        }
    }

    var systemImage: String {
        switch self {
        case .streak: return "flame"
        case .level: return "star.circle"
        case .boss: return "shield"
        case .bingo: return "square.grid.3x3"
        case .seasonal: return "leaf"
        case .journeys: return "map"
        case .records: return "trophy"
        case .collections: return "square.grid.2x2"
        case .sportBody: return "figure.run"
        case .secrets: return "questionmark.circle"
        case .challenges: return "target"
        case .achievements: return "rosette"
        case .weight: return "scalemass"
        case .hydration: return "drop"
        case .trends: return "chart.xyaxis.line"
        case .goalHistory: return "checklist"
        case .supplements: return "pills"
        }
    }
}

extension LayoutPreset {
    var displayName: String {
        switch self {
        case .full: return String(localized: "Full", comment: "Layout preset: everything on Today, as by default.")
        case .minimal: return String(localized: "Minimal", comment: "Layout preset: only the essentials on Today.")
        case .athlete: return String(localized: "Athlete", comment: "Layout preset: weight and water moved up on Today.")
        }
    }
}
