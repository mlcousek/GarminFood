// ColorMathTests — pins the color math every theme rule rests on (task 1.2):
// WCAG contrast against known reference values, hex parsing, OKLab against
// Ottosson's published reference, round trips, and Machado CVD behavior on
// the primaries. If these drift, every contrast/distinctness test downstream
// is meaningless.

import XCTest
@testable import AppearanceKit

final class ColorMathTests: XCTestCase {

    // MARK: WCAG

    func testWhiteOnBlackIs21To1() {
        XCTAssertEqual(ColorMath.contrastRatio(.white, .black), 21, accuracy: 1e-9)
    }

    func testIdenticalColorsAre1To1() {
        let color = RGBA(hex: 0x4A8FE3)
        XCTAssertEqual(ColorMath.contrastRatio(color, color), 1, accuracy: 1e-12)
    }

    func testGrey777777OnWhiteIsAbout4Point48() {
        let grey = RGBA(hex: 0x777777)
        XCTAssertEqual(ColorMath.contrastRatio(grey, .white), 4.48, accuracy: 0.01)
    }

    func testContrastIsSymmetric() {
        let a = RGBA(hex: 0xF56B4A), b = RGBA(hex: 0x1C1C1E)
        XCTAssertEqual(ColorMath.contrastRatio(a, b), ColorMath.contrastRatio(b, a), accuracy: 1e-12)
    }

    func testLinearizeRoundTrip() {
        for value in stride(from: 0.0, through: 1.0, by: 0.05) {
            XCTAssertEqual(ColorMath.delinearize(ColorMath.linearize(value)), value, accuracy: 1e-12)
        }
    }

    func testCompositeOpaqueTopWins() {
        let top = RGBA(hex: 0x123456)
        XCTAssertEqual(ColorMath.composite(top, over: .white), top)
    }

    func testCompositeHalfBlackOverWhiteIsMidGrey() {
        let result = ColorMath.composite(RGBA.black.withAlpha(0.5), over: .white)
        XCTAssertEqual(result.red, 0.5, accuracy: 1e-12)
        XCTAssertEqual(result.alpha, 1, accuracy: 1e-12)
    }

    // MARK: Hex

    func testHexParsing() {
        XCTAssertEqual(RGBA(hexString: "#F56B4A"), RGBA(hex: 0xF56B4A))
        XCTAssertEqual(RGBA(hexString: "f56b4a"), RGBA(hex: 0xF56B4A))
        XCTAssertEqual(RGBA(hexString: "  #F56B4A \n"), RGBA(hex: 0xF56B4A))
        XCTAssertEqual(RGBA(hexString: "#00000080")?.alpha ?? -1, 128.0 / 255, accuracy: 1e-12)
        XCTAssertNil(RGBA(hexString: ""))
        XCTAssertNil(RGBA(hexString: "#12"))
        XCTAssertNil(RGBA(hexString: "#GGGGGG"))
        XCTAssertNil(RGBA(hexString: "+12345"))
        XCTAssertNil(RGBA(hexString: "#1234567"))
    }

    func testHexStringRoundTrip() {
        XCTAssertEqual(RGBA(hex: 0xF56B4A).hexString, "#F56B4A")
        XCTAssertEqual(RGBA(hex: 0x000000, alpha: 128.0 / 255).hexString, "#00000080")
        for hex in ["#0072B2", "#FFFFFF", "#000000", "#C62828"] {
            XCTAssertEqual(RGBA(hexString: hex)?.hexString, hex)
        }
    }

    func testCodableUsesHexString() throws {
        let data = try JSONEncoder().encode([RGBA(hex: 0x15808C)])
        XCTAssertEqual(String(data: data, encoding: .utf8), "[\"#15808C\"]")
        let decoded = try JSONDecoder().decode([RGBA].self, from: data)
        XCTAssertEqual(decoded, [RGBA(hex: 0x15808C)])
        XCTAssertThrowsError(try JSONDecoder().decode([RGBA].self, from: Data("[\"nope\"]".utf8)))
    }

    // MARK: OKLab / OKLCH

    func testOKLabOfWhiteAndBlack() {
        let white = ColorMath.oklab(.white)
        XCTAssertEqual(white.lightness, 1, accuracy: 1e-4)
        XCTAssertEqual(white.a, 0, accuracy: 1e-4)
        XCTAssertEqual(white.b, 0, accuracy: 1e-4)
        XCTAssertEqual(ColorMath.oklab(.black).lightness, 0, accuracy: 1e-9)
    }

    func testOKLabOfRedMatchesReference() {
        // Ottosson's reference value for sRGB red.
        let red = ColorMath.oklab(RGBA(red: 1, green: 0, blue: 0))
        XCTAssertEqual(red.lightness, 0.62796, accuracy: 1e-4)
        XCTAssertEqual(red.a, 0.22486, accuracy: 1e-4)
        XCTAssertEqual(red.b, 0.12585, accuracy: 1e-4)
    }

    func testOKLabRoundTrip() {
        for hex: UInt32 in [0xF56B4A, 0x0072B2, 0x8A6D00, 0xFFFF00, 0x1C1C1E, 0x7F7F7F, 0x00FF00] {
            let color = RGBA(hex: hex)
            let back = ColorMath.rgba(fromOKLab: ColorMath.oklab(color))
            XCTAssertEqual(back.red, color.red, accuracy: 1e-6, "\(color.hexString)")
            XCTAssertEqual(back.green, color.green, accuracy: 1e-6, "\(color.hexString)")
            XCTAssertEqual(back.blue, color.blue, accuracy: 1e-6, "\(color.hexString)")
        }
    }

    func testOKLCHRoundTrip() {
        for hex: UInt32 in [0xF56B4A, 0x0072B2, 0xC62828, 0x5AC8FA] {
            let color = RGBA(hex: hex)
            let lch = ColorMath.oklch(color)
            XCTAssertGreaterThanOrEqual(lch.hue, 0)
            XCTAssertLessThan(lch.hue, 360)
            let back = ColorMath.rgba(fromOKLCH: lch)
            XCTAssertEqual(back.red, color.red, accuracy: 1e-6)
            XCTAssertEqual(back.green, color.green, accuracy: 1e-6)
            XCTAssertEqual(back.blue, color.blue, accuracy: 1e-6)
        }
    }

    func testGamutMappedIsInGamutAndKeepsLightness() {
        // Very high chroma at mid lightness is far outside sRGB.
        let lch = OKLCH(lightness: 0.6, chroma: 0.4, hue: 140)
        XCTAssertFalse(ColorMath.isInGamut(ColorMath.rgba(fromOKLCH: lch)))
        let mapped = ColorMath.gamutMapped(lch)
        XCTAssertTrue(ColorMath.isInGamut(mapped))
        XCTAssertEqual(ColorMath.oklch(mapped).lightness, 0.6, accuracy: 0.01)
    }

    func testDeltaE() {
        let color = RGBA(hex: 0x4A8FE3)
        XCTAssertEqual(ColorMath.deltaEOK(color, color), 0, accuracy: 1e-12)
        XCTAssertEqual(ColorMath.deltaEOK(.white, .black), 1, accuracy: 1e-3)
        XCTAssertEqual(ColorMath.deltaEOK(.white, .black), ColorMath.deltaEOK(.black, .white), accuracy: 1e-12)
    }

    // MARK: CVD

    func testGreyIsInvariantUnderEverySimulation() {
        let grey = RGBA(red: 0.5, green: 0.5, blue: 0.5)
        for deficiency in ColorVisionDeficiency.allCases {
            let simulated = ColorMath.simulate(grey, deficiency)
            XCTAssertEqual(ColorMath.deltaEOK(simulated, grey), 0, accuracy: 0.005, "\(deficiency)")
        }
    }

    func testRedAndGreenCollapseToTheSameHueForProtanAndDeutan() {
        let red = RGBA(red: 1, green: 0, blue: 0)
        let green = RGBA(red: 0, green: 1, blue: 0)
        for deficiency in [ColorVisionDeficiency.protan, .deutan] {
            let redHue = ColorMath.oklch(ColorMath.simulate(red, deficiency)).hue
            let greenHue = ColorMath.oklch(ColorMath.simulate(green, deficiency)).hue
            XCTAssertEqual(redHue, greenHue, accuracy: 15, "\(deficiency)")
            // Both read as yellow-ish (OKLCH hue ~100°), not as red / green.
            XCTAssertEqual(redHue, 100, accuracy: 15, "\(deficiency)")
        }
    }

    func testTritanBlueMatchesMatrix() {
        let simulated = ColorMath.simulate(RGBA(red: 0, green: 0, blue: 1), .tritan)
        XCTAssertEqual(simulated.red, 0, accuracy: 1e-9) // -0.178779 clamps to 0
        XCTAssertEqual(simulated.green, ColorMath.delinearize(0.147602), accuracy: 1e-9)
        XCTAssertEqual(simulated.blue, ColorMath.delinearize(0.303900), accuracy: 1e-9)
    }

    func testSimulationPreservesAlpha() {
        let color = RGBA(red: 1, green: 0, blue: 0, alpha: 0.4)
        XCTAssertEqual(ColorMath.simulate(color, .deutan).alpha, 0.4, accuracy: 1e-12)
    }
}
