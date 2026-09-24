// ColorMath — the numeric foundation of the theme system
// (openspec/changes/add-themes-and-layout/design.md D5): sRGB <-> linear,
// WCAG 2.x relative luminance and contrast ratio, OKLab / OKLCH (Björn
// Ottosson's perceptual space, used for "keep the hue, move lightness"
// fitting and for ΔE distinctness), and Machado et al. (2009) colour-vision-
// deficiency simulation.
//
// Why it exists: no Mac means no way to eyeball a palette in a simulator, so
// every "is this readable / are these two bars tellable apart" rule is a
// number checked by `swift test`. Everything here is pure Double math on
// `RGBA` — no UIKit/SwiftUI color types, so the rules run on the CI host.
//
// Depended on by: ThemeCatalog tests (contrast + distinctness), AccentAdjuster
// (OKLCH lightness walk), PaletteResolver (onAccent derivation).

import Foundation

// MARK: - RGBA

/// A gamma-encoded sRGB color with components in 0...1.
///
/// Values outside 0...1 can appear transiently (e.g. an OKLab conversion of
/// an out-of-gamut color); use `clamped` before presenting such a value.
/// `Codable` as a `"#RRGGBB"` / `"#RRGGBBAA"` string — 8 bits per channel,
/// which is what a user-picked custom accent needs. Built-in theme values are
/// Swift literals and are never round-tripped through JSON.
public struct RGBA: Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// `0xRRGGBB`.
    public init(hex: UInt32, alpha: Double = 1) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    /// Parses `"#RRGGBB"`, `"RRGGBB"`, `"#RRGGBBAA"` or `"RRGGBBAA"`
    /// (case-insensitive, surrounding whitespace ignored). Anything else is `nil`.
    public init?(hexString: String) {
        var text = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") {
            text.removeFirst()
        }
        guard text.count == 6 || text.count == 8,
              text.allSatisfy({ $0.isHexDigit }),
              let value = UInt64(text, radix: 16) else {
            return nil
        }
        if text.count == 6 {
            self.init(hex: UInt32(truncatingIfNeeded: value))
        } else {
            self.init(
                red: Double((value >> 24) & 0xFF) / 255,
                green: Double((value >> 16) & 0xFF) / 255,
                blue: Double((value >> 8) & 0xFF) / 255,
                alpha: Double(value & 0xFF) / 255
            )
        }
    }

    public static let white = RGBA(red: 1, green: 1, blue: 1)
    public static let black = RGBA(red: 0, green: 0, blue: 0)

    /// Each component clamped to 0...1.
    public var clamped: RGBA {
        RGBA(
            red: RGBA.clamp01(red),
            green: RGBA.clamp01(green),
            blue: RGBA.clamp01(blue),
            alpha: RGBA.clamp01(alpha)
        )
    }

    /// `"#RRGGBB"`, or `"#RRGGBBAA"` when the color is not fully opaque.
    public var hexString: String {
        let r = RGBA.byte(red), g = RGBA.byte(green), b = RGBA.byte(blue), a = RGBA.byte(alpha)
        if a == 255 {
            return String(format: "#%02X%02X%02X", r, g, b)
        }
        return String(format: "#%02X%02X%02X%02X", r, g, b, a)
    }

    public func withAlpha(_ alpha: Double) -> RGBA {
        RGBA(red: red, green: green, blue: blue, alpha: alpha)
    }

    static func clamp01(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    static func byte(_ value: Double) -> Int {
        Int((clamp01(value) * 255).rounded())
    }
}

extension RGBA: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let parsed = RGBA(hexString: text) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Not a #RRGGBB or #RRGGBBAA color: \(text)"
            )
        }
        self = parsed
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hexString)
    }
}

// MARK: - OKLab / OKLCH

/// A color in Björn Ottosson's OKLab space. `lightness` is 0 (black) ... 1 (white).
public struct OKLab: Hashable, Sendable {
    public var lightness: Double
    public var a: Double
    public var b: Double

    public init(lightness: Double, a: Double, b: Double) {
        self.lightness = lightness
        self.a = a
        self.b = b
    }
}

/// OKLab in polar form. `hue` is in degrees, 0..<360.
public struct OKLCH: Hashable, Sendable {
    public var lightness: Double
    public var chroma: Double
    public var hue: Double

    public init(lightness: Double, chroma: Double, hue: Double) {
        self.lightness = lightness
        self.chroma = chroma
        self.hue = hue
    }
}

// MARK: - Colour-vision deficiency

/// The three dichromacies simulated at full severity (Machado, Oliveira &
/// Fernandes 2009, severity 1.0), applied in linear sRGB.
public enum ColorVisionDeficiency: String, CaseIterable, Sendable {
    case protan
    case deutan
    case tritan

    /// Row-major 3×3 matrix acting on linear RGB.
    var machadoMatrix: [[Double]] {
        switch self {
        case .protan:
            return [
                [0.152286, 1.052583, -0.204868],
                [0.114503, 0.786281, 0.099216],
                [-0.003882, -0.048116, 1.051998]
            ]
        case .deutan:
            return [
                [0.367322, 0.860646, -0.227968],
                [0.280085, 0.672501, 0.047413],
                [-0.011820, 0.042940, 0.968881]
            ]
        case .tritan:
            return [
                [1.255528, -0.076749, -0.178779],
                [-0.078411, 0.930809, 0.147602],
                [0.004733, 0.691367, 0.303900]
            ]
        }
    }
}

// MARK: - ColorMath

public enum ColorMath {

    // MARK: sRGB transfer

    /// sRGB-encoded channel -> linear light. Odd-symmetric so transient
    /// negative values (out-of-gamut conversions) stay well defined.
    public static func linearize(_ channel: Double) -> Double {
        let magnitude = abs(channel)
        let linear = magnitude <= 0.04045
            ? magnitude / 12.92
            : pow((magnitude + 0.055) / 1.055, 2.4)
        return channel < 0 ? -linear : linear
    }

    /// Linear light -> sRGB-encoded channel. Odd-symmetric, like `linearize`.
    public static func delinearize(_ linear: Double) -> Double {
        let magnitude = abs(linear)
        let encoded = magnitude <= 0.0031308
            ? 12.92 * magnitude
            : 1.055 * pow(magnitude, 1 / 2.4) - 0.055
        return linear < 0 ? -encoded : encoded
    }

    // MARK: WCAG

    /// WCAG 2.x relative luminance (alpha ignored).
    public static func relativeLuminance(_ color: RGBA) -> Double {
        let c = color.clamped
        return 0.2126 * linearize(c.red) + 0.7152 * linearize(c.green) + 0.0722 * linearize(c.blue)
    }

    /// WCAG 2.x contrast ratio, 1...21, symmetric in its arguments (alpha
    /// ignored — composite translucent colors first with `composite(_:over:)`).
    public static func contrastRatio(_ first: RGBA, _ second: RGBA) -> Double {
        let l1 = relativeLuminance(first)
        let l2 = relativeLuminance(second)
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    /// Source-over compositing in gamma-encoded space (what UIKit does for a
    /// translucent fill over an opaque one). The result is opaque when
    /// `bottom` is.
    public static func composite(_ top: RGBA, over bottom: RGBA) -> RGBA {
        let a = RGBA.clamp01(top.alpha)
        let outAlpha = a + RGBA.clamp01(bottom.alpha) * (1 - a)
        guard outAlpha > 0 else { return RGBA(red: 0, green: 0, blue: 0, alpha: 0) }
        func mix(_ t: Double, _ b: Double) -> Double {
            (t * a + b * RGBA.clamp01(bottom.alpha) * (1 - a)) / outAlpha
        }
        return RGBA(
            red: mix(top.red, bottom.red),
            green: mix(top.green, bottom.green),
            blue: mix(top.blue, bottom.blue),
            alpha: outAlpha
        )
    }

    // MARK: OKLab

    public static func oklab(_ color: RGBA) -> OKLab {
        let r = linearize(color.red), g = linearize(color.green), b = linearize(color.blue)
        let l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
        let m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
        let s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b
        let lRoot = cbrt(l), mRoot = cbrt(m), sRoot = cbrt(s)
        return OKLab(
            lightness: 0.2104542553 * lRoot + 0.7936177850 * mRoot - 0.0040720468 * sRoot,
            a: 1.9779984951 * lRoot - 2.4285922050 * mRoot + 0.4505937099 * sRoot,
            b: 0.0259040371 * lRoot + 0.7827717662 * mRoot - 0.8086757660 * sRoot
        )
    }

    /// OKLab -> sRGB, **unclamped** (check `isInGamut` or use `gamutMapped`).
    public static func rgba(fromOKLab lab: OKLab, alpha: Double = 1) -> RGBA {
        let lRoot = lab.lightness + 0.3963377774 * lab.a + 0.2158037573 * lab.b
        let mRoot = lab.lightness - 0.1055613458 * lab.a - 0.0638541728 * lab.b
        let sRoot = lab.lightness - 0.0894841775 * lab.a - 1.2914855480 * lab.b
        let l = lRoot * lRoot * lRoot
        let m = mRoot * mRoot * mRoot
        let s = sRoot * sRoot * sRoot
        let r = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
        let g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
        let b = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
        return RGBA(red: delinearize(r), green: delinearize(g), blue: delinearize(b), alpha: alpha)
    }

    public static func oklch(_ color: RGBA) -> OKLCH {
        let lab = oklab(color)
        var hue = atan2(lab.b, lab.a) * 180 / Double.pi
        if hue < 0 { hue += 360 }
        return OKLCH(lightness: lab.lightness, chroma: (lab.a * lab.a + lab.b * lab.b).squareRoot(), hue: hue)
    }

    /// OKLCH -> sRGB, **unclamped**.
    public static func rgba(fromOKLCH lch: OKLCH, alpha: Double = 1) -> RGBA {
        let radians = lch.hue * Double.pi / 180
        return rgba(
            fromOKLab: OKLab(lightness: lch.lightness, a: lch.chroma * cos(radians), b: lch.chroma * sin(radians)),
            alpha: alpha
        )
    }

    /// Whether every channel is within 0...1 (± `tolerance`).
    public static func isInGamut(_ color: RGBA, tolerance: Double = 1e-6) -> Bool {
        [color.red, color.green, color.blue].allSatisfy { $0 >= -tolerance && $0 <= 1 + tolerance }
    }

    /// The sRGB color for `lch`, reducing chroma in 0.002 steps (hue and
    /// lightness kept) until it fits the sRGB gamut; the result is clamped.
    public static func gamutMapped(_ lch: OKLCH, alpha: Double = 1) -> RGBA {
        var chroma = max(lch.chroma, 0)
        // OKLab chroma of any sRGB color is < 0.33, so 500 steps of 0.002
        // always reach 0 for sane input; the bound only guards against NaN.
        for _ in 0..<500 where chroma > 0 {
            let candidate = rgba(fromOKLCH: OKLCH(lightness: lch.lightness, chroma: chroma, hue: lch.hue), alpha: alpha)
            if isInGamut(candidate) {
                return candidate.clamped
            }
            chroma -= 0.002
        }
        return rgba(fromOKLCH: OKLCH(lightness: lch.lightness, chroma: 0, hue: lch.hue), alpha: alpha).clamped
    }

    /// Euclidean distance in OKLab ("ΔE_OK"). 0 = identical; white vs black ≈ 1.
    public static func deltaEOK(_ first: RGBA, _ second: RGBA) -> Double {
        let x = oklab(first), y = oklab(second)
        let dl = x.lightness - y.lightness, da = x.a - y.a, db = x.b - y.b
        return (dl * dl + da * da + db * db).squareRoot()
    }

    // MARK: CVD

    /// How `color` appears to a viewer with the given dichromacy (Machado
    /// 2009, severity 1.0). Alpha is preserved; the result is clamped.
    public static func simulate(_ color: RGBA, _ deficiency: ColorVisionDeficiency) -> RGBA {
        let input = [linearize(color.red), linearize(color.green), linearize(color.blue)]
        let matrix = deficiency.machadoMatrix
        var output = [0.0, 0.0, 0.0]
        for row in 0..<3 {
            var sum = 0.0
            for column in 0..<3 {
                sum += matrix[row][column] * input[column]
            }
            output[row] = delinearize(RGBA.clamp01(sum))
        }
        return RGBA(red: output[0], green: output[1], blue: output[2], alpha: color.alpha)
    }
}
