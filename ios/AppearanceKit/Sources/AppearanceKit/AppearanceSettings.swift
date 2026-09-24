// AppearanceSettings — the user's persisted look (design.md D6, D7, R7):
// theme, one global Light/Dark/System choice, macro color set, optional custom
// accent and the style options. Stored by the app as JSON `Data` under the
// `appearance.v1` preferences key.
//
// Why decoding is lenient (D7): a settings blob written by a newer build (a
// theme id or enum case this build doesn't know) or a partially written one
// must never reset the whole look. Every field falls back to its own
// default independently; unknown fields are ignored; only a blob that isn't
// a JSON object at all is reported `.undecodable`, so the app can
// quarantine it (never silently wipe it — the lesson of
// fix-silent-store-wipe) and use the defaults.
//
// Depended on by: the app's AppPreferences+Appearance / theme store, and
// PaletteResolver.resolve(settings:environment:).

import Foundation

// MARK: - Options

/// Light / Dark / follow the system. One global choice (design R7);
/// single-scheme themes override it.
public enum AppearanceMode: String, CaseIterable, Codable, Sendable {
    case system
    case light
    case dark
}

/// Which macro/state color set to draw with (D3, D4 step 2).
public enum MacroSetOption: String, CaseIterable, Codable, Sendable {
    /// Whatever the theme defines.
    case theme
    /// The shared Legible set (Classic's hues, darkened to ≥ 3:1 in light).
    case legible
    /// The shared colour-blind-safe set (Okabe-Ito hues). Also forced by the
    /// system's Differentiate Without Color setting.
    case colorBlindSafe
}

public enum CardStyleOption: String, CaseIterable, Codable, Sendable {
    case filled
    case elevated
    case outlined
    case glass
}

public enum CornerShapeOption: String, CaseIterable, Codable, Sendable {
    case sharp
    case standard
    case round
}

public enum DensityOption: String, CaseIterable, Codable, Sendable {
    case comfortable
    case compact
}

public enum NumberFontOption: String, CaseIterable, Codable, Sendable {
    case rounded
    case `default`
    case serif
    case monospaced
}

// MARK: - Style

/// The D6 style options. Defaults are today's look.
public struct AppearanceStyle: Hashable, Sendable {
    public var cardStyle: CardStyleOption
    public var cornerShape: CornerShapeOption
    public var density: DensityOption
    public var numberFont: NumberFontOption
    public var gradientHeader: Bool

    public init(
        cardStyle: CardStyleOption = .filled,
        cornerShape: CornerShapeOption = .standard,
        density: DensityOption = .comfortable,
        numberFont: NumberFontOption = .rounded,
        gradientHeader: Bool = false
    ) {
        self.cardStyle = cardStyle
        self.cornerShape = cornerShape
        self.density = density
        self.numberFont = numberFont
        self.gradientHeader = gradientHeader
    }

    public static let `default` = AppearanceStyle()
}

extension AppearanceStyle: Codable {
    enum CodingKeys: String, CodingKey {
        case cardStyle, cornerShape, density, numberFont, gradientHeader
    }

    public init(from decoder: Decoder) throws {
        let fallback = AppearanceStyle.default
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
            self = fallback
            return
        }
        cardStyle = LenientDecoding.enumValue(CardStyleOption.self, container, .cardStyle) ?? fallback.cardStyle
        cornerShape = LenientDecoding.enumValue(CornerShapeOption.self, container, .cornerShape) ?? fallback.cornerShape
        density = LenientDecoding.enumValue(DensityOption.self, container, .density) ?? fallback.density
        numberFont = LenientDecoding.enumValue(NumberFontOption.self, container, .numberFont) ?? fallback.numberFont
        gradientHeader = (try? container.decodeIfPresent(Bool.self, forKey: .gradientHeader)) ?? fallback.gradientHeader
    }
}

// MARK: - Settings

public struct AppearanceSettings: Hashable, Sendable {
    /// Schema version this value was written with; drives `AppearanceMigration`.
    public var version: Int
    /// Selected theme id. Kept verbatim even if this build doesn't know it
    /// (a newer build's theme); `PaletteResolver` falls back to the default
    /// theme for an unknown id.
    public var themeID: String
    /// Light/Dark/System, global (R7). A single-scheme theme overrides it.
    public var appearance: AppearanceMode
    public var macroSet: MacroSetOption
    /// The user's raw custom accent pick, if any. Stored unfitted; fitting
    /// to the contrast policy happens at resolve time, per scheme (D5).
    public var customAccent: RGBA?
    public var style: AppearanceStyle

    /// The theme a fresh install (or an absent/garbled field) gets.
    public static let defaultThemeID = "teal"

    public init(
        version: Int = AppearanceSchema.currentVersion,
        themeID: String = AppearanceSettings.defaultThemeID,
        appearance: AppearanceMode = .system,
        macroSet: MacroSetOption = .theme,
        customAccent: RGBA? = nil,
        style: AppearanceStyle = .default
    ) {
        self.version = version
        self.themeID = themeID
        self.appearance = appearance
        self.macroSet = macroSet
        self.customAccent = customAccent
        self.style = style
    }

    public static let `default` = AppearanceSettings()
}

extension AppearanceSettings: Codable {
    enum CodingKeys: String, CodingKey {
        case version, themeID, appearance, macroSet, customAccent, style
    }

    /// Lenient: every field independently falls back to its default. Throws
    /// only when the payload is not a JSON object at all.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = AppearanceSettings.default

        version = (try? container.decodeIfPresent(Int.self, forKey: .version)) ?? fallback.version

        if let id = try? container.decodeIfPresent(String.self, forKey: .themeID), !id.isEmpty {
            themeID = id
        } else {
            themeID = fallback.themeID
        }

        appearance = LenientDecoding.enumValue(AppearanceMode.self, container, .appearance) ?? fallback.appearance

        macroSet = LenientDecoding.enumValue(MacroSetOption.self, container, .macroSet) ?? fallback.macroSet
        // A garbled hex string decodes as "no custom accent", not a failure.
        customAccent = try? container.decodeIfPresent(RGBA.self, forKey: .customAccent)
        style = (try? container.decodeIfPresent(AppearanceStyle.self, forKey: .style)) ?? fallback.style
    }
}

// MARK: - Loading

public extension AppearanceSettings {
    enum LoadStatus: Equatable, Sendable {
        /// No stored value: defaults, nothing to report.
        case absent
        /// Decoded (possibly with some fields defaulted) and migrated.
        case loaded
        /// Stored bytes could not be read at all. The app should quarantine
        /// them, log a warning and tell the user once (D7).
        case undecodable
    }

    struct LoadResult: Equatable, Sendable {
        public let settings: AppearanceSettings
        public let status: LoadStatus
    }

    /// Decode + migrate a stored blob. Never throws.
    static func load(from data: Data?) -> LoadResult {
        guard let data else {
            return LoadResult(settings: .default, status: .absent)
        }
        guard let decoded = try? JSONDecoder().decode(AppearanceSettings.self, from: data) else {
            return LoadResult(settings: .default, status: .undecodable)
        }
        return LoadResult(settings: AppearanceMigration.migrate(decoded), status: .loaded)
    }

    /// JSON for storage (sorted keys, so identical settings give identical bytes).
    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }
}

// MARK: - Migration

/// The seam for future schema changes (D7). At v1 it only stamps the
/// current version; a v2 would add a `case 1:` step here.
public enum AppearanceMigration {
    public static func migrate(_ settings: AppearanceSettings) -> AppearanceSettings {
        var migrated = settings
        // No steps yet: v1 is the first schema. A blob from a *newer* build
        // (version > current) is kept as leniently decoded.
        migrated.version = AppearanceSchema.currentVersion
        return migrated
    }
}

// MARK: - Helpers

enum LenientDecoding {
    /// A String-backed enum value, or `nil` when absent, not a string, or an
    /// unknown raw value.
    static func enumValue<E: RawRepresentable, K: CodingKey>(
        _ type: E.Type,
        _ container: KeyedDecodingContainer<K>,
        _ key: K
    ) -> E? where E.RawValue == String {
        guard let raw = try? container.decodeIfPresent(String.self, forKey: key) else {
            return nil
        }
        return E(rawValue: raw)
    }
}
