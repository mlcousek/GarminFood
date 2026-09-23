// LogQuantity.swift
//
// The one rule for what quantity (number of servings, sent to Garmin as
// `servingQty`) may be logged or edited. Before this, the confirm screen
// only checked `quantity > 0`: a typed "99999999999999999999" was accepted,
// durably queued, and then crashed every launch in the UI's `Int(_:)`-based
// formatting (see NumberDisplay.swift). Enforced inside `LogEntryCoordinator`
// (every confirm/edit/duplicate/copy path), so no entry point -- a screen,
// Siri, a Control -- can get around it; the screens also read it to disable
// their confirm button and say why.
//
// Pure, Foundation-only; tested in LogQuantityTests and
// LogEntryCoordinatorTests.

import Foundation

public enum LogQuantity {
    /// The most servings one entry may carry. Generous on purpose: a
    /// "1 g" serving logged by weight needs thousands (5 kg is 5 000), but
    /// nobody eats 10 000 servings of anything in one entry, and it keeps
    /// every derived number (calories, totals) far inside what any display
    /// or Garmin can handle.
    public static let maximum: Double = 10_000

    /// Finite, greater than zero and at most `maximum`.
    public static func isValid(_ quantity: Double) -> Bool {
        quantity.isFinite && quantity > 0 && quantity <= maximum
    }

    /// What a screen shows when `isValid` fails for a quantity the user
    /// typed.
    public static var invalidMessage: String {
        "Enter an amount greater than zero and at most \(NumberDisplay.quantity(maximum))."
    }
}

/// Thrown by `LogEntryCoordinator`'s confirm paths for a quantity outside
/// `LogQuantity.isValid`. Nothing is enqueued when it's thrown.
public enum LogQuantityError: Error, Sendable, Equatable, LocalizedError {
    case outOfRange

    public var errorDescription: String? {
        LogQuantity.invalidMessage
    }
}
