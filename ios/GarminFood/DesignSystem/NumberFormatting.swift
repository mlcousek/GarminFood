// NumberFormatting.swift
//
// The app target's one `Double` -> text helper for quantities and rounded
// whole numbers. Replaces five identical `private extension Double {
// var formattedQuantity }` copies (TodayView, LogEntryConfirmView,
// EntryEditing, MealPresetConfirmView, MealPresetEditorView) and the
// scattered `Int(value.rounded())` interpolations, all of which TRAPPED
// (crashed the app) for a non-finite value or one past ~9.2e18 -- a single
// huge typed quantity crashed the Today screen on every launch.
//
// Both delegate to FoodLogCore's `NumberDisplay`, where the formatting is
// unit-tested (NumberDisplayTests); output for ordinary values is exactly
// what the old helpers printed ("2", "0.70", "290"). The input side of the
// same bug -- refusing such a quantity in the first place -- is
// `LogQuantity` (FoodLogCore), enforced by `LogEntryCoordinator`.

import FoodLogCore

extension Double {
    /// A logged quantity: "2" for a whole number, "0.70" otherwise.
    var formattedQuantity: String {
        NumberDisplay.quantity(self)
    }

    /// Rounded to the nearest whole number ("290" for 289.6) -- what
    /// `Int(value.rounded())` printed, without its crash.
    var wholeNumberText: String {
        NumberDisplay.whole(self)
    }
}
