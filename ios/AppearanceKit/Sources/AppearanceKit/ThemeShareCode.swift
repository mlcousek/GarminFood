// ThemeShareCode — the text code a look is shared as (add-themes-and-layout
// design.md D11, task 5.4): the owner's phone exports its theme, custom
// accent, style options, macro set and Light/Dark choice; another phone
// pastes the code (or opens its `garminfood://theme?c=…` link / QR code),
// sees a preview and only then applies it.
//
// Format: `GFT1.<payload>.<checksum>`
//   - `GFT1` — prefix plus format version. Any other version is rejected
//     as such (a newer build's code), never guessed at.
//   - payload — base64url (no padding) of minified JSON with short keys:
//     `t` theme id, `p` appearance, `m` macro set, `a` custom accent hex
//     (optional), `s` style {`c` card, `r` corners, `d` density,
//     `n` number font, `g` gradient header}. Typically ~170 characters.
//   - checksum — FNV-1a 32 of the payload text, 8 lowercase hex digits, so
//     a truncated or hand-mangled code is reported as unreadable instead
//     of silently applying something half-decoded.
// A code longer than `maximumLength` (2 KB) is rejected before parsing.
//
// Decoding never throws into the UI: `.success(Import)` with warnings, or
// `.failure(Failure)`. Within a checksum-valid payload it is lenient, like
// `AppearanceSettings`' own decoding (D7): an unknown theme id falls back
// to Classic with a warning (spec "Code from a newer build"), an unknown
// enum value falls back to the default with a warning, unknown keys are
// ignored. A custom accent travels raw; `PaletteResolver` re-fits it to
// the contrast policy on the receiving phone, per scheme (D5).
//
// Appearance only, never personal or food data. Today's layout (`l`) joins
// the payload with wave 3's layout model; this build ignores it.
//
// Pure Foundation; tested in ThemeShareCodeTests. Used by the app's
// Appearance page (share / import) and AppRouter (the link).

import Foundation

public enum ThemeShareCode {
    public static let prefix = "GFT"
    public static let currentVersion = 1
    /// Codes longer than this are rejected before any parsing.
    public static let maximumLength = 2048
    /// `garminfood://theme?c=<code>`.
    public static let linkHost = "theme"
    public static let linkQueryName = "c"

    public enum Failure: Error, Equatable, Hashable, Sendable {
        /// Doesn't start with `GFT<number>.`.
        case notAShareCode
        /// A `GFT<n>.` code from a build with another format version.
        case unsupportedVersion(Int)
        /// Longer than `maximumLength`.
        case tooLong
        /// Right prefix, but truncated, tampered with or unreadable.
        case corrupted
    }

    public enum Warning: Equatable, Hashable, Sendable {
        /// The code names a theme this build doesn't have; Classic is used.
        case unknownTheme(String)
        /// Some values weren't recognised and were left at their defaults.
        case ignoredUnknownValues
    }

    /// A decoded code: the settings to preview/apply, and what didn't carry over.
    public struct Import: Equatable, Sendable {
        public let settings: AppearanceSettings
        public let warnings: [Warning]

        public init(settings: AppearanceSettings, warnings: [Warning]) {
            self.settings = settings
            self.warnings = warnings
        }
    }

    // MARK: - Encoding

    /// The share code for `settings` (its theme, accent, style, macro set
    /// and appearance; `version` is not part of the code).
    public static func encode(_ settings: AppearanceSettings) -> String {
        let payload = Payload(
            t: settings.themeID,
            p: settings.appearance.rawValue,
            m: settings.macroSet.rawValue,
            a: settings.customAccent.map { $0.withAlpha(1).hexString },
            s: Payload.Style(
                c: settings.style.cardStyle.rawValue,
                r: settings.style.cornerShape.rawValue,
                d: settings.style.density.rawValue,
                n: settings.style.numberFont.rawValue,
                g: settings.style.gradientHeader
            )
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        // Encoding plain strings and a Bool cannot fail.
        let json = (try? encoder.encode(payload)) ?? Data("{}".utf8)
        return wrap(json: json)
    }

    /// `GFT1.<base64url(json)>.<checksum>`. Internal so tests can build
    /// codes around hand-written JSON.
    static func wrap(json: Data) -> String {
        let payload = base64URLEncoded(json)
        return "\(prefix)\(currentVersion).\(payload).\(checksum(of: payload))"
    }

    /// `garminfood://theme?c=<code>` for the app's URL `scheme`.
    public static func link(for code: String, scheme: String) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = linkHost
        components.queryItems = [URLQueryItem(name: linkQueryName, value: code)]
        return components.url
    }

    // MARK: - Decoding

    /// Decodes one code (surrounding whitespace ignored).
    public static func decode(_ text: String) -> Result<Import, Failure> {
        let code = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard code.utf8.count <= maximumLength else { return .failure(.tooLong) }

        let parts = code.split(separator: ".", omittingEmptySubsequences: false)
        guard let head = parts.first, head.hasPrefix(prefix) else { return .failure(.notAShareCode) }
        let digits = head.dropFirst(prefix.count)
        guard !digits.isEmpty,
              digits.allSatisfy({ $0.isASCII && $0.isNumber }),
              let version = Int(digits)
        else { return .failure(.notAShareCode) }
        guard version == currentVersion else { return .failure(.unsupportedVersion(version)) }

        guard parts.count == 3 else { return .failure(.corrupted) }
        let payload = String(parts[1])
        guard String(parts[2]).lowercased() == checksum(of: payload),
              let json = base64URLDecoded(payload),
              let object = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any],
              let rawThemeID = object["t"] as? String,
              !rawThemeID.isEmpty
        else { return .failure(.corrupted) }

        return .success(settings(from: object, themeID: rawThemeID))
    }

    /// Decodes whatever was pasted: a bare code, a `garminfood://theme`
    /// link, or the whole share message containing either.
    public static func decode(pasted text: String, scheme: String) -> Result<Import, Failure> {
        // Far beyond any share message: don't tokenize megabytes of paste.
        guard text.utf8.count <= maximumLength * 4 else { return .failure(.tooLong) }
        for token in text.split(whereSeparator: { $0.isWhitespace }) {
            let candidate = String(token)
            if let url = URL(string: candidate), let linked = Self.code(fromLink: url, scheme: scheme) {
                return decode(linked)
            }
            if candidate.hasPrefix(prefix) {
                return decode(candidate)
            }
        }
        return decode(text)
    }

    /// The code inside a `<scheme>://theme?c=<code>` link, or `nil` for any
    /// other URL.
    public static func code(fromLink url: URL, scheme: String) -> String? {
        guard url.scheme?.lowercased() == scheme.lowercased(),
              url.host?.lowercased() == linkHost,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        return components.queryItems?.first(where: { $0.name == linkQueryName })?.value
    }

    // MARK: - Payload

    private struct Payload: Encodable {
        struct Style: Encodable {
            let c: String
            let r: String
            let d: String
            let n: String
            let g: Bool
        }

        let t: String
        let p: String
        let m: String
        let a: String?
        let s: Style
    }

    /// Lenient per field (see header). `object` passed the checksum.
    private static func settings(from object: [String: Any], themeID rawThemeID: String) -> Import {
        let fallback = AppearanceSettings.default
        var warnings: [Warning] = []
        var ignored = false

        func value<E: RawRepresentable>(_ raw: Any?, _ fallbackValue: E) -> E where E.RawValue == String {
            guard let raw else { return fallbackValue }
            guard let text = raw as? String, let parsed = E(rawValue: text) else {
                ignored = true
                return fallbackValue
            }
            return parsed
        }

        let themeID: String
        if ThemeCatalog.theme(id: rawThemeID) != nil {
            themeID = rawThemeID
        } else {
            themeID = BuiltInTheme.classic.rawValue
            warnings.append(.unknownTheme(rawThemeID))
        }

        var customAccent: RGBA?
        if let rawAccent = object["a"] {
            if let text = rawAccent as? String, let accent = RGBA(hexString: text) {
                customAccent = accent.withAlpha(1)
            } else {
                ignored = true
            }
        }

        var style = fallback.style
        if let rawStyle = object["s"] {
            if let fields = rawStyle as? [String: Any] {
                style.cardStyle = value(fields["c"], fallback.style.cardStyle)
                style.cornerShape = value(fields["r"], fallback.style.cornerShape)
                style.density = value(fields["d"], fallback.style.density)
                style.numberFont = value(fields["n"], fallback.style.numberFont)
                if let rawGradient = fields["g"] {
                    if let gradient = rawGradient as? Bool {
                        style.gradientHeader = gradient
                    } else {
                        ignored = true
                    }
                }
            } else {
                ignored = true
            }
        }

        let settings = AppearanceSettings(
            themeID: themeID,
            appearance: value(object["p"], fallback.appearance),
            macroSet: value(object["m"], fallback.macroSet),
            customAccent: customAccent,
            style: style
        )
        if ignored { warnings.append(.ignoredUnknownValues) }
        return Import(settings: settings, warnings: warnings)
    }

    // MARK: - Helpers

    /// FNV-1a 32 of `text`'s UTF-8, as 8 lowercase hex digits.
    static func checksum(of text: String) -> String {
        var hash: UInt32 = 0x811C_9DC5
        for byte in text.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 0x0100_0193
        }
        return String(format: "%08x", hash)
    }

    static func base64URLEncoded(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func base64URLDecoded(_ text: String) -> Data? {
        guard !text.isEmpty,
              text.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") })
        else { return nil }
        var base64 = text
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder == 1 { return nil }
        if remainder > 0 { base64 += String(repeating: "=", count: 4 - remainder) }
        return Data(base64Encoded: base64)
    }
}
