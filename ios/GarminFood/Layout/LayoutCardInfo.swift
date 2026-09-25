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
// the Appearance page's Layout section.

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
        case .logFood, .progress:
            // Wave 4 gives these screens an editor; until then nothing
            // lists their cards.
            return id
        }
    }

    static func systemImage(_ id: String, on screen: LayoutScreen) -> String {
        switch screen {
        case .today:
            return TodayCardID(rawValue: id)?.systemImage ?? "square"
        case .logFood, .progress:
            return "square"
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
        case .logAgain: return "arrow.counterclockwise"
        case .logMeal: return "takeoutbag.and.cup.and.straw"
        case .weightWater: return "scalemass"
        case .dayNote: return "note.text"
        case .signature: return "signature"
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
