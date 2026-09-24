// AccentAdjuster — fits a color to a contrast requirement while keeping its
// hue (design.md D5): walk OKLCH lightness in 0.01 steps (darker for a
// light scheme, lighter for a dark one), reducing chroma only when a step
// leaves the sRGB gamut, and stop at the first candidate that passes. After
// 100 steps it gives up and returns the best candidate, flagged.
//
// Used by PaletteResolver for increased contrast (D4 step 4) and for the
// user's custom accent (step 3). The user's raw pick is what gets stored;
// fitting happens at resolve time, so one pick works in light and dark.

import Foundation

/// "`color` must reach `minimumRatio` against `against`."
public struct ContrastRequirement: Hashable, Sendable {
    public var against: RGBA
    public var minimumRatio: Double

    public init(against: RGBA, minimumRatio: Double) {
        self.against = against
        self.minimumRatio = minimumRatio
    }

    func isMet(by color: RGBA) -> Bool {
        ColorMath.contrastRatio(color, against) >= minimumRatio
    }

    /// ≥ 1 when met; used to rank failing candidates.
    func score(_ color: RGBA) -> Double {
        ColorMath.contrastRatio(color, against) / minimumRatio
    }
}

public enum AccentAdjuster {

    public enum Direction: Sendable {
        case darken
        case lighten

        /// Darker on light surfaces, lighter on dark ones.
        public init(for scheme: ThemeColorScheme) {
            switch scheme {
            case .light: self = .darken
            case .dark: self = .lighten
            }
        }

        var sign: Double {
            switch self {
            case .darken: return -1
            case .lighten: return 1
            }
        }
    }

    public struct FitResult: Hashable, Sendable {
        /// The fitted color (or the input, if it already passed).
        public let color: RGBA
        /// Whether `color` differs from the input.
        public let wasAdjusted: Bool
        /// The walk ran out (100 steps, or lightness hit 0/1) without
        /// passing; `color` is the best candidate found.
        public let gaveUp: Bool
    }

    public static let lightnessStep = 0.01
    public static let maximumSteps = 100

    /// Fit `color` so every requirement is met, walking lightness in `direction`.
    public static func fit(
        _ color: RGBA,
        requirements: [ContrastRequirement],
        direction: Direction
    ) -> FitResult {
        func passes(_ candidate: RGBA) -> Bool {
            requirements.allSatisfy { $0.isMet(by: candidate) }
        }
        func score(_ candidate: RGBA) -> Double {
            requirements.map { $0.score(candidate) }.min() ?? Double.infinity
        }

        if passes(color) {
            return FitResult(color: color, wasAdjusted: false, gaveUp: false)
        }

        let start = ColorMath.oklch(color)
        var best = color
        var bestScore = score(color)
        for step in 1...maximumSteps {
            let lightness = min(max(start.lightness + direction.sign * lightnessStep * Double(step), 0), 1)
            let candidate = ColorMath.gamutMapped(
                OKLCH(lightness: lightness, chroma: start.chroma, hue: start.hue),
                alpha: color.alpha
            )
            if passes(candidate) {
                return FitResult(color: candidate, wasAdjusted: true, gaveUp: false)
            }
            let candidateScore = score(candidate)
            if candidateScore > bestScore {
                best = candidate
                bestScore = candidateScore
            }
            if lightness <= 0 || lightness >= 1 {
                break
            }
        }
        return FitResult(color: best, wasAdjusted: best != color, gaveUp: true)
    }

    /// The `accentDeep` companion of a custom accent: same hue, 0.12 darker
    /// in OKLCH lightness (the gradient end, rings, widget background).
    public static func deepened(_ accent: RGBA) -> RGBA {
        let lch = ColorMath.oklch(accent)
        return ColorMath.gamutMapped(
            OKLCH(lightness: max(lch.lightness - 0.12, 0), chroma: lch.chroma, hue: lch.hue),
            alpha: accent.alpha
        )
    }

    // MARK: - Collision warning

    /// The macro color `accent` is too close to (OKLab ΔE below
    /// `ContrastPolicy.minimumAccentMacroDistance`), or `nil`. When several
    /// are, the closest wins. The accent picker shows "Looks like the
    /// protein color…" for the returned role.
    public static func collidingMacro(_ accent: RGBA, macros: [ThemeRole: RGBA]) -> ThemeRole? {
        var closest: (role: ThemeRole, distance: Double)?
        for role in ThemeRole.comparedMacros + [.water] {
            guard let macro = macros[role] else { continue }
            let distance = ColorMath.deltaEOK(accent, macro)
            guard distance < ContrastPolicy.minimumAccentMacroDistance else { continue }
            if closest.map({ distance < $0.distance }) ?? true {
                closest = (role, distance)
            }
        }
        return closest?.role
    }

    /// `collidingMacro(_:macros:)` for a resolved palette's (fitted) accent
    /// against its own macro colors.
    public static func collidingMacro(in palette: ResolvedPalette) -> ThemeRole? {
        var macros: [ThemeRole: RGBA] = [:]
        for role in ThemeRole.comparedMacros + [.water] {
            macros[role] = palette.referenceValue(role)
        }
        return collidingMacro(palette.referenceValue(.accent), macros: macros)
    }

    /// Convenience for the D5 signature: `color` against each of `surfaces`
    /// at `minRatio`, in the direction that suits `scheme`.
    public static func fit(
        _ color: RGBA,
        against surfaces: [RGBA],
        minRatio: Double,
        scheme: ThemeColorScheme
    ) -> FitResult {
        fit(
            color,
            requirements: surfaces.map { ContrastRequirement(against: $0, minimumRatio: minRatio) },
            direction: Direction(for: scheme)
        )
    }
}
