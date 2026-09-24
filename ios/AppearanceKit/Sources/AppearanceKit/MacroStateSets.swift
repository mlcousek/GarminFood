// MacroStateSets — the two shared macro/state/band color sets of design.md
// D3, as role overrides on top of a theme table. Themes build on "Legible";
// the user's Colour-blind-safe choice (or the system's Differentiate Without
// Color) swaps in "Colour-blind safe" at resolve time (D4 step 2).
//
// Values nudged from the design table to pass the D5 tests (recorded here as
// the design asks):
//   - Colour-blind-safe light `fat`: #8A6D00 -> #4F3E00. Under protan
//     simulation #8A6D00 and the vermillion protein collapse to ΔE 0.017;
//     the darker olive keeps ≥ 0.10 even after increased-contrast fitting
//     darkens protein.
//   - Colour-blind-safe bands: building = sky blue, approaching = yellow,
//     on target = blue, slightly over = orange, over = vermillion (light
//     values darkened to ≥ 3:1 on white).
//
// Depended on by: ThemeCatalog (Legible as the base of most themes),
// PaletteResolver (step 2).

import Foundation

public enum MacroStateSets {

    /// Classic's hues, darkened in light mode to ≥ 3:1 on white and #F2F2F7.
    /// Dark mode keeps Classic's values except water and danger/over-band.
    public static func legible(_ scheme: ThemeColorScheme) -> [ThemeRole: TokenValue] {
        switch scheme {
        case .light:
            let grace = RGBA(hex: 0x6B7C90)
            let ember = RGBA(hex: 0xC75A00)
            let success = RGBA(hex: 0x1F8A57)
            let red = RGBA(hex: 0xC62828)
            return [
                .carbs: .rgb(RGBA(hex: 0x2F74C8)),
                .protein: .rgb(RGBA(hex: 0x7A52C7)),
                .fat: .rgb(RGBA(hex: 0xA86F00)),
                .water: .rgb(RGBA(hex: 0x1C7FB8)),
                .success: .rgb(success),
                .warning: .rgb(RGBA(hex: 0xB36B00)),
                .ember: .rgb(ember),
                .grace: .rgb(grace),
                .danger: .rgb(red),
                .over: .rgb(RGBA(hex: 0xB0406A)),
                .bandLow: .rgb(grace),
                .bandBuilding: .rgb(ember),
                .bandApproaching: .rgb(RGBA(hex: 0x9A7400)),
                .bandOnTarget: .rgb(success),
                .bandSlightlyOver: .rgb(ember),
                .bandOver: .rgb(red)
            ]
        case .dark:
            let red = RGBA(hex: 0xFF6B6B)
            return [
                .water: .rgb(RGBA(hex: 0x5AC8FA)),
                .danger: .rgb(red),
                .bandOver: .rgb(red)
            ]
        }
    }

    /// Okabe-Ito hues: blue / vermillion / yellow for carbs / protein / fat,
    /// and the bands on the same logic. States are left to the theme.
    public static func colorBlindSafe(_ scheme: ThemeColorScheme) -> [ThemeRole: TokenValue] {
        switch scheme {
        case .light:
            return [
                .carbs: .rgb(RGBA(hex: 0x0072B2)),
                .protein: .rgb(RGBA(hex: 0xD55E00)),
                .fat: .rgb(RGBA(hex: 0x4F3E00)),
                .bandBuilding: .rgb(RGBA(hex: 0x2F80B5)),
                .bandApproaching: .rgb(RGBA(hex: 0x8A6D00)),
                .bandOnTarget: .rgb(RGBA(hex: 0x0072B2)),
                .bandSlightlyOver: .rgb(RGBA(hex: 0xA86F00)),
                .bandOver: .rgb(RGBA(hex: 0xD55E00))
            ]
        case .dark:
            return [
                .carbs: .rgb(RGBA(hex: 0x56B4E9)),
                .protein: .rgb(RGBA(hex: 0xF28A3C)),
                .fat: .rgb(RGBA(hex: 0xF0E442)),
                .bandBuilding: .rgb(RGBA(hex: 0x56B4E9)),
                .bandApproaching: .rgb(RGBA(hex: 0xF0E442)),
                .bandOnTarget: .rgb(RGBA(hex: 0x3D9BE0)),
                .bandSlightlyOver: .rgb(RGBA(hex: 0xE69F00)),
                .bandOver: .rgb(RGBA(hex: 0xF28A3C))
            ]
        }
    }
}
