// PolicyChecker — test-side evaluation of the D5 contrast and distinctness
// policy for one table. Shared by BuiltInThemeContrastTests,
// DistinctnessTests and the resolver tests, so every suite applies the
// exact same rules (thresholds come from ContrastPolicy in the library).

import Foundation
@testable import AppearanceKit

struct PolicyFailure: Hashable, CustomStringConvertible {
    let role: ThemeRole
    let check: String
    let value: Double
    let minimum: Double

    var description: String {
        "\(role) \(check): \(String(format: "%.2f", value)) < \(minimum)"
    }
}

enum PolicyChecker {

    /// Contrast failures of `table` in `scheme` at `level`.
    ///
    /// At `.increased`, roles that are dynamic system colors are skipped:
    /// iOS itself swaps in their increased-contrast variants, which the
    /// reference approximations here don't model.
    static func contrastFailures(
        _ table: ThemeTable,
        scheme: ThemeColorScheme,
        level: ContrastLevel
    ) -> [PolicyFailure] {
        var failures: [PolicyFailure] = []
        func value(_ role: ThemeRole) -> RGBA { table.referenceValue(role, in: scheme) }
        func require(_ role: ThemeRole, _ check: String, _ ratio: Double, _ minimum: Double) {
            if ratio < minimum {
                failures.append(PolicyFailure(role: role, check: check, value: ratio, minimum: minimum))
            }
        }

        let accent = value(.accent)
        require(.onAccent, "on accent", ColorMath.contrastRatio(value(.onAccent), accent),
                ContrastPolicy.minimumOnAccent(level))
        for surface in [ThemeRole.surface, .background] {
            require(.accent, "on \(surface)", ColorMath.contrastRatio(accent, value(surface)),
                    ContrastPolicy.minimumAccentOnSurface(level))
        }

        let surface = value(.surface)
        for role in ThemeRole.graphicRoles {
            if level == .increased, table[role].rgbValue == nil {
                continue
            }
            require(role, "on surface", ColorMath.contrastRatio(value(role), surface),
                    ContrastPolicy.minimumGraphicOnSurface(level))
        }

        let secondary = ContrastPolicy.secondaryLabelReference(scheme, level)
        for tinted in [ThemeRole.surface, .background] where table[tinted].rgbValue != nil {
            require(tinted, "secondary label on it", ColorMath.contrastRatio(secondary, value(tinted)),
                    ContrastPolicy.minimumSecondaryLabelOnTintedSurface(level))
        }
        return failures
    }

    /// Distinctness failures: carbs/protein/fat pairwise, and the accent
    /// against each macro including water.
    static func distinctnessFailures(_ table: ThemeTable, scheme: ThemeColorScheme) -> [String] {
        var failures: [String] = []
        func value(_ role: ThemeRole) -> RGBA { table.referenceValue(role, in: scheme) }
        failures += pairwiseFailures(ThemeRole.comparedMacros.map { ($0, value($0)) }, label: "normal vision")
        let accent = value(.accent)
        for role in ThemeRole.comparedMacros + [.water] {
            let distance = ColorMath.deltaEOK(accent, value(role))
            if distance < ContrastPolicy.minimumAccentMacroDistance {
                failures.append("accent vs \(role): ΔE \(String(format: "%.3f", distance))")
            }
        }
        return failures
    }

    /// carbs/protein/fat pairwise after each CVD simulation.
    static func cvdFailures(_ table: ThemeTable, scheme: ThemeColorScheme) -> [String] {
        var failures: [String] = []
        for deficiency in ColorVisionDeficiency.allCases {
            let simulated = ThemeRole.comparedMacros.map {
                ($0, ColorMath.simulate(table.referenceValue($0, in: scheme), deficiency))
            }
            failures += pairwiseFailures(simulated, label: deficiency.rawValue)
        }
        return failures
    }

    private static func pairwiseFailures(_ colors: [(ThemeRole, RGBA)], label: String) -> [String] {
        var failures: [String] = []
        for i in colors.indices {
            for j in colors.indices where j > i {
                let distance = ColorMath.deltaEOK(colors[i].1, colors[j].1)
                if distance < ContrastPolicy.minimumMacroDistance {
                    failures.append("\(label): \(colors[i].0) vs \(colors[j].0) ΔE \(String(format: "%.3f", distance))")
                }
            }
        }
        return failures
    }
}
