// Theme.swift
//
// A small, fixed set of color/spacing/radius/motion tokens, defined once and
// reused everywhere -- openspec/config.yaml's "Design & UX principles": "A
// small, consistent design system (color, type scale, spacing, component
// set) defined once and reused everywhere, not per-screen improvisation."
//
// add-themes-and-layout (design.md R4): every token name is kept, but the
// colors, the corner radii and the number fonts are now computed from the
// active theme and style in `ThemeRuntime.shared` (ThemeRuntime.swift), so
// views keep writing `Theme.accent` and re-render when the theme changes.
// The theme values themselves live in AppearanceKit (`ThemeCatalog`;
// today's coral look is `ClassicTheme`, pinned by `ClassicIdentityTests`).
// No theme reads as Garmin's own blue UI: the app must never look like an
// official Garmin surface. Text stays on the system `.primary`/`.secondary`
// styles in every theme.
//
// This file is the one place allowed to spell out colors (see
// tools/design-token-allowlist.txt); views use the tokens.
//
// Lives in Shared/ (since 2026-09-16) so the widget extension draws from the
// same tokens as the app, instead of copying the RGB values by hand
// (add-gamification 26.1).

import SwiftUI
import AppearanceKit

enum Theme {
    // MARK: - Color

    private static var palette: ThemePalette { ThemeRuntime.shared.palette }

    static var accent: Color { palette[.accent] }
    /// The darker end of the accent gradient (widget background, rings).
    static var accentDeep: Color { palette[.accentDeep] }
    /// Text and icons drawn on an `accent` fill (white or black per theme).
    static var onAccent: Color { palette[.onAccent] }
    static var accentSecondary: Color { palette[.accentSecondary] }
    static var headerGradientStart: Color { palette[.headerGradientStart] }
    static var headerGradientEnd: Color { palette[.headerGradientEnd] }

    /// One hue per macro, used consistently wherever a macro is drawn, so a
    /// colour always means the same nutrient.
    static var carbs: Color { palette[.carbs] }
    static var protein: Color { palette[.protein] }
    static var fat: Color { palette[.fat] }
    /// Hydration (was drawn in the carbs color before theming).
    static var water: Color { palette[.water] }
    /// Streak calendar: a forgiven day.
    static var grace: Color { palette[.grace] }
    static var success: Color { palette[.success] }
    static var warning: Color { palette[.warning] }
    /// Errors (was SwiftUI `.red`).
    static var danger: Color { palette[.danger] }

    /// The streak flame's colour -- a deeper, more orange ember so the flame
    /// reads as fire, not as another accent-coloured button. Used solid for
    /// "at risk" and as one stop of `flameGradient` when alive.
    static var ember: Color { palette[.ember] }
    /// "Over your goal" -- distinct from `warning` (used for sign-in state)
    /// so the two never get confused; information, not alarm.
    static var over: Color { palette[.over] }

    /// Calorie bands (`CalorieBand.tint`).
    static var bandLow: Color { palette[.bandLow] }
    static var bandBuilding: Color { palette[.bandBuilding] }
    static var bandApproaching: Color { palette[.bandApproaching] }
    static var bandOnTarget: Color { palette[.bandOnTarget] }
    static var bandSlightlyOver: Color { palette[.bandSlightlyOver] }
    static var bandOver: Color { palette[.bandOver] }

    /// Bottom-to-top ember -> flame tip, so a lit flame is brightest at its tip.
    static var flameGradient: LinearGradient {
        LinearGradient(
            colors: [ember, palette[.flameTip]],
            startPoint: .bottom,
            endPoint: .top
        )
    }

    /// Surfaces. Most themes use the system grouped colors; some tint them.
    static var cardBackground: Color { palette[.surfaceRaised] }
    static var groupedBackground: Color { palette[.background] }
    /// The hero card sits one step above the grouped background in both
    /// modes -- a real surface, not a tinted panel, so the big number has
    /// something to sit on without any coloured wash competing with it.
    static var heroBackground: Color { palette[.surface] }
    static var stroke: Color { palette[.stroke] }

    /// The active style options (card style, density, gradient header...).
    static var style: AppearanceStyle { ThemeRuntime.shared.style }

    // MARK: - Spacing

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
    }

    /// Container-level density (design D6): only card padding and the main
    /// screens' stack spacing follow it; `Spacing` inside views stays fixed.
    enum Density {
        static var cardPadding: CGFloat {
            ThemeRuntime.shared.style.density == .compact ? 12 : Spacing.md
        }

        static var stackSpacing: CGFloat {
            ThemeRuntime.shared.style.density == .compact ? 16 : Spacing.lg
        }
    }

    // MARK: - Radius

    /// Scaled by the Corners style option (design D6): Sharp, Standard
    /// (today's values), Round.
    enum Radius {
        static var sm: CGFloat { scale(sharp: 4, standard: 8, round: 12) }
        static var md: CGFloat { scale(sharp: 8, standard: 14, round: 18) }
        static var lg: CGFloat { scale(sharp: 10, standard: 20, round: 26) }
        static var xl: CGFloat { scale(sharp: 14, standard: 28, round: 34) }

        private static func scale(sharp: CGFloat, standard: CGFloat, round: CGFloat) -> CGFloat {
            switch ThemeRuntime.shared.style.cornerShape {
            case .sharp: return sharp
            case .standard: return standard
            case .round: return round
            }
        }
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

    // The hero's type. The number design follows the Number font style
    // option (design D6; Rounded by default -- warmer and friendlier for a
    // number the user is meant to feel good about, while still a system
    // font). Tabular digits in every design so the count never jitters
    // horizontally as it changes.
    static var heroNumber: Font {
        Font.system(size: 72, weight: .bold, design: ThemeRuntime.shared.numberDesign).monospacedDigit()
    }
    static var heroUnit: Font {
        Font.system(.title3, design: ThemeRuntime.shared.numberDesign).weight(.semibold)
    }
    static var streakNumber: Font {
        Font.system(.title2, design: ThemeRuntime.shared.numberDesign).weight(.bold).monospacedDigit()
    }
    static let streakLabel = Font.system(.subheadline, design: .rounded).weight(.medium)
    static var macroValue: Font {
        Font.system(.subheadline, design: ThemeRuntime.shared.numberDesign).weight(.semibold).monospacedDigit()
    }
}
