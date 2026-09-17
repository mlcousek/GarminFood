// Haptics.swift
//
// One place that decides whether to buzz, so the haptics preference is
// honoured everywhere. Views that react to a value change use
// `.sensoryFeedback(_:trigger:condition:)` with `Haptics.isEnabled` as the
// condition; imperative call sites use the helpers below.

import UIKit

@MainActor
enum Haptics {
    /// Mirrors `AppPreferences.hapticsEnabled`; kept in sync by
    /// `AppEnvironment`.
    static var isEnabled = true

    static func success() {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func selection() {
        guard isEnabled else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
