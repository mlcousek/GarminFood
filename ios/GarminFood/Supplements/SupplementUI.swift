// SupplementUI.swift
//
// add-supplements wave 3: small display helpers every supplement view
// shares -- turning the stores' `yyyy-MM-dd` day keys into dates and
// titles for the date picker, and a product's planned dose as text. Kept in
// one place so the screen, the Today card and the insights say things the
// same way. Numbers and units come from FoodLogCore's `SupplementFormat`
// (locale decimals, design D12); nothing here decides anything.
//
// Depends on: FoodLogCore (SupplementFormat, SupplementProduct).
// Depended on by: GarminFood/Supplements/*.

import Foundation
import FoodLogCore

enum SupplementDay {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// Noon of `day` in the current time zone (noon, so a DST change never
    /// moves it to another day).
    static func date(_ day: String) -> Date? {
        guard let start = formatter.date(from: day) else { return nil }
        return Calendar.current.date(byAdding: .hour, value: 12, to: start)
    }

    static func key(_ date: Date) -> String {
        NutritionDate.string(from: date)
    }

    /// "Today", "Yesterday", or "Mon 21 Sep".
    static func title(_ day: String, today: String) -> String {
        if day == today {
            return String(localized: "Today")
        }
        if SupplementDate.adding(1, to: day) == today {
            return String(localized: "Yesterday")
        }
        guard let date = date(day) else { return day }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }
}

extension SupplementProduct {
    /// "2 capsules · Magnesium 200 mg" style subtitle: the serving, then
    /// the label's first ingredients.
    var summaryLine: String {
        let ingredients = ingredients.prefix(2).map { SupplementFormat.ingredientLine($0) }.joined(separator: ", ")
        return [servingDescription, ingredients.isEmpty ? nil : ingredients]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

extension DueItem {
    /// "× 2" when the slot plans anything other than one serving (a
    /// multiplier, not a plural).
    var servingsSuffix: String? {
        guard servings != 1 else { return nil }
        return "× " + SupplementFormat.servings(servings)
    }
}
