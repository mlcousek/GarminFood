// Theme.swift
//
// A small, fixed set of color/spacing/radius/motion tokens, defined once and
// reused everywhere -- openspec/config.yaml's "Design & UX principles": "A
// small, consistent design system (color, type scale, spacing, component
// set) defined once and reused everywhere, not per-screen improvisation."
//
// The accent is a fixed brand hue (a warm coral, deliberately NOT Garmin's
// own blue, so this app never reads as an official Garmin surface); every
// other color rides SwiftUI's semantic system colors (`.primary`,
// `.secondary`, `Color(.secondarySystemBackground)`) so Dynamic Type,
// light/dark mode, and contrast support are automatic rather than
// hand-maintained token-by-token here.

import SwiftUI

enum Theme {
    // MARK: - Color

    static let accent = Color(red: 0.96, green: 0.42, blue: 0.29)
    static let success = Color(red: 0.20, green: 0.68, blue: 0.45)
    static let warning = Color(red: 0.90, green: 0.60, blue: 0.13)

    static var cardBackground: Color { Color(.secondarySystemBackground) }
    static var groupedBackground: Color { Color(.systemGroupedBackground) }

    // MARK: - Spacing

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
    }

    // MARK: - Radius

    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 14
        static let lg: CGFloat = 20
    }

    // MARK: - Motion

    /// A deliberate, springy confirm/success motion -- config.yaml: "Motion
    /// and feedback are not an afterthought." Collapses to a near-instant
    /// fade when Reduce Motion is on, per "Reduce Motion respected": the
    /// user still sees the state change, just without the bounce.
    static func confirmAnimation(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.12) : .spring(response: 0.4, dampingFraction: 0.72)
    }
}

// MARK: - Type scale

extension Font {
    /// The handful of text styles this app actually uses, named for their
    /// job rather than their size -- so a future tweak happens once, here.
    static let foodTitle = Font.headline
    static let foodSubtitle = Font.subheadline
    static let macroBadge = Font.caption.monospacedDigit()
    static let sectionHeader = Font.subheadline.weight(.semibold)
}
