// GradientHeaderContrastTests — task 2.6 (design D6): with the optional
// Today gradient header on, text stays the system `.primary` label, so it
// must stay readable on each gradient stop blended over the background at
// 22% (and at the 12% flat tint used under Reduce Transparency), for every
// built-in theme and supported scheme.

import XCTest
@testable import AppearanceKit

final class GradientHeaderContrastTests: XCTestCase {

    func testPrimaryLabelReadsOnTheBlendedStops() {
        for theme in ThemeCatalog.all {
            for scheme in theme.supportedSchemes {
                let palette = PaletteResolver.resolve(theme: theme, requestedScheme: scheme)
                let background = palette.referenceValue(.background)
                // System .primary label: black in light, white in dark.
                let label: RGBA = scheme == .light ? .black : .white
                for stop in [ThemeRole.headerGradientStart, .headerGradientEnd] {
                    for opacity in [0.22, 0.12] {
                        let blended = ColorMath.composite(palette.referenceValue(stop).withAlpha(opacity), over: background)
                        let ratio = ColorMath.contrastRatio(label, blended)
                        XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(theme.id) \(scheme) \(stop) @\(opacity)")
                    }
                }
            }
        }
    }
}
