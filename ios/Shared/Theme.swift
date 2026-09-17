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
//
// Lives in Shared/ (since 2026-09-16) so the widget extension draws from the
// same tokens as the app, instead of copying the RGB values by hand
// (add-gamification 26.1).

import SwiftUI

enum Theme {
    // MARK: - Color

    static let accent = Color(red: 0.96, green: 0.42, blue: 0.29)
    /// The darker end of the accent gradient (widget background, rings).
    static let accentDeep = Color(red: 0.80, green: 0.27, blue: 0.18)

    /// One hue per macro, used consistently wherever a macro is drawn, so a
    /// colour always means the same nutrient.
    static let carbs = Color(red: 0.29, green: 0.56, blue: 0.89)
    static let protein = Color(red: 0.55, green: 0.40, blue: 0.86)
    static let fat = Color(red: 0.93, green: 0.69, blue: 0.20)
    /// Streak calendar: a forgiven day.
    static let grace = Color(red: 0.55, green: 0.62, blue: 0.70)
    static let success = Color(red: 0.20, green: 0.68, blue: 0.45)
    static let warning = Color(red: 0.90, green: 0.60, blue: 0.13)

    /// The streak flame's colour, and the only genuinely warm hue on the
    /// screen besides the coral accent -- a deeper, more orange ember so the
    /// flame reads as fire, not as another accent-coloured button. Used
    /// solid for "at risk" and as one stop of `flameGradient` when alive.
    static let ember = Color(red: 0.98, green: 0.55, blue: 0.16)
    /// "Over your goal" -- distinct from `warning` (used for sign-in state)
    /// so the two never get confused; a muted red-violet, not alarm red,
    /// because going over is information, not a failure.
    static let over = Color(red: 0.78, green: 0.32, blue: 0.48)

    /// Bottom-to-top ember -> coral, so a lit flame is brightest at its tip.
    static let flameGradient = LinearGradient(
        colors: [ember, accent],
        startPoint: .bottom,
        endPoint: .top
    )

    static var cardBackground: Color { Color(.secondarySystemBackground) }
    static var groupedBackground: Color { Color(.systemGroupedBackground) }
    /// The hero card sits one step above the grouped background in both
    /// modes -- a real surface, not a tinted panel, so the big number has
    /// something to sit on without any coloured wash competing with it.
    static var heroBackground: Color { Color(.secondarySystemGroupedBackground) }

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
        static let xl: CGFloat = 28
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

    // The hero's type. `.rounded` is a deliberate choice over the default
    // system face: warmer and friendlier for a number the user is meant to
    // feel good about, while still a system font -- nothing to bundle, which
    // matters on a no-Mac build pipeline. Tabular digits so the count never
    // jitters horizontally as it changes; tight tracking so 4 digits read as
    // one object rather than four.
    static let heroNumber = Font.system(size: 72, weight: .bold, design: .rounded).monospacedDigit()
    static let heroUnit = Font.system(.title3, design: .rounded).weight(.semibold)
    static let streakNumber = Font.system(.title2, design: .rounded).weight(.bold).monospacedDigit()
    static let streakLabel = Font.system(.subheadline, design: .rounded).weight(.medium)
    static let macroValue = Font.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit()
}
