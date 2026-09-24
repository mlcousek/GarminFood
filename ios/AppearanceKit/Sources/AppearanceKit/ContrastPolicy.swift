// ContrastPolicy — the thresholds of design.md D5 in one place, shared by
// PaletteResolver (increased-contrast fitting, custom-accent fitting,
// onAccent derivation) and the catalog tests that hold every built-in theme
// to them. Changing a number here changes both what the app enforces at
// runtime and what CI accepts for the built-in themes.

import Foundation

public enum ContrastLevel: String, CaseIterable, Sendable {
    case normal
    /// The system's Increase Contrast setting, or a High Contrast theme.
    case increased
}

public enum ContrastPolicy {

    /// Button label (`onAccent`) on `accent`.
    public static func minimumOnAccent(_ level: ContrastLevel) -> Double {
        level == .increased ? 7.0 : 4.5
    }

    /// `accent` on `surface` and on `background`.
    public static func minimumAccentOnSurface(_ level: ContrastLevel) -> Double {
        level == .increased ? 4.5 : 3.0
    }

    /// Each macro, `water`, state and calorie-band role on `surface`.
    public static func minimumGraphicOnSurface(_ level: ContrastLevel) -> Double {
        level == .increased ? 4.5 : 3.0
    }

    /// System secondary label on a theme-tinted (`.rgb`) surface or background.
    public static func minimumSecondaryLabelOnTintedSurface(_ level: ContrastLevel) -> Double {
        level == .increased ? 4.5 : 3.0
    }

    /// Approximate iOS 17 `secondaryLabel`, composited on white/black
    /// (normal: #8A8A8E / #98989F; Increase Contrast: #6C6C70 / #AEAEB2).
    public static func secondaryLabelReference(_ scheme: ThemeColorScheme, _ level: ContrastLevel) -> RGBA {
        switch (scheme, level) {
        case (.light, .normal): return RGBA(hex: 0x8A8A8E)
        case (.dark, .normal): return RGBA(hex: 0x98989F)
        case (.light, .increased): return RGBA(hex: 0x6C6C70)
        case (.dark, .increased): return RGBA(hex: 0xAEAEB2)
        }
    }

    /// Minimum OKLab ΔE between any two of carbs / protein / fat — also
    /// after protan, deutan and tritan simulation for the colour-blind-safe set.
    public static let minimumMacroDistance = 0.10

    /// Minimum OKLab ΔE between the accent and each macro (incl. water).
    /// Also the custom-accent collision warning threshold.
    public static let minimumAccentMacroDistance = 0.06

    /// White or black, whichever contrasts more with `accent` (D4 step 5).
    /// Ties go to white.
    public static func preferredOnAccent(for accent: RGBA) -> RGBA {
        ColorMath.contrastRatio(.white, accent) >= ColorMath.contrastRatio(.black, accent) ? .white : .black
    }
}
