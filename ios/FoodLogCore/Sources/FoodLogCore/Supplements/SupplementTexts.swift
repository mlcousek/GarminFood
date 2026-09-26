// SupplementTexts.swift
//
// Display text that more than one supplement surface needs and that must be
// built OUTSIDE SwiftUI (add-supplements D5/D12): the slot names and the
// "5 g" / "1000 IU" dose text are used by the app's screens AND by the
// reminder copy `NotificationPlanning` writes (a notification's words are
// frozen when it is scheduled, so they are built here, in the app's current
// language, and compared by the scheduler's title/body diff).
//
// Numbers go through `NumberDisplay`, so decimals follow the locale ("2,5 g"
// in Czech, D12). Unit symbols are the same in English and Czech; VoiceOver
// spelling is the app's job (its `SpokenUnits`).
//
// Depends on: SupplementModels (TimeSlot, IngredientAmount, DoseUnit),
// NumberDisplay, EvidenceCatalog (ingredient names).
// Depended on by: SupplementReminderPlanning, the app's supplements screens.

import Foundation

extension TimeSlot {
    /// "Morning" / "Ráno"; a custom slot shows the name the user gave it.
    public var displayName: String {
        switch self {
        case .morning:
            return String(localized: "Morning", bundle: .module, comment: "Supplement time slot name.")
        case .withBreakfast:
            return String(localized: "With breakfast", bundle: .module, comment: "Supplement time slot name: taken together with breakfast.")
        case .preWorkout:
            return String(localized: "Pre-workout", bundle: .module, comment: "Supplement time slot name: before a training session.")
        case .evening:
            return String(localized: "Evening", bundle: .module, comment: "Supplement time slot name.")
        case .custom(let name, _):
            return name
        }
    }

    /// An SF Symbol for the slot.
    public var symbolName: String {
        switch self {
        case .morning: return "sunrise"
        case .withBreakfast: return "cup.and.saucer"
        case .preWorkout: return "figure.run"
        case .evening: return "moon"
        case .custom: return "clock"
        }
    }
}

public enum SupplementFormat {
    /// "5 g", "2,5 g", "1000 IU", "75 µg" -- up to two decimals, trailing
    /// zeros dropped.
    public static func amount(_ value: Double, unit: DoseUnit, locale: Locale = .current) -> String {
        NumberDisplay.trimmed(value, maxFractionDigits: 2, locale: locale) + " " + unit.symbol
    }

    /// One label row: "Creatine 5 g", or just the name when the label
    /// states no amount.
    public static func ingredientLine(_ row: IngredientAmount, locale: Locale = .current) -> String {
        let name = row.customName ?? EvidenceCatalog.name(of: row.ingredient)
        guard let value = row.amount else { return name }
        return name + " " + amount(value, unit: row.unit, locale: locale)
    }

    /// "2 × Creatine monohydrate" style count, trimmed ("1,5").
    public static func servings(_ value: Double, locale: Locale = .current) -> String {
        NumberDisplay.trimmed(value, maxFractionDigits: 2, locale: locale)
    }

    /// `HH:mm`, 24-hour, for a minute of the day.
    public static func clock(minute: Int) -> String {
        let value = ((minute % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}
