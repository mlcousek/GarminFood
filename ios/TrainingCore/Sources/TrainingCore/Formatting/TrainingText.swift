// TrainingText.swift
//
// Every string TrainingCore shows, in English or Czech (design D1; the
// repository's package convention from add-localization D3). The tables
// are Resources/<lang>.lproj/Localizable.strings(dict) with the English
// text as the key.
//
// Why a lookup object rather than `String(localized:bundle: .module)`: the
// builders take the app's language as a parameter (`TrainingLanguage`), so
// the same builder can be tested in English AND Czech in one `swift test`
// run on an English CI machine. The lookup goes to the language's lproj
// sub-bundle directly, and `format` applies the language's locale, which
// is what picks the Czech plural form (one/few/many/other) from a
// `.stringsdict` entry.
//
// Keys are `TrainingKey` cases (TrainingKey.swift), never free strings, and
// `TrainingTextTests` checks that every case resolves in both tables -- the
// guard `tools/check-localizations.mjs` gives `String(localized:)` literals.
//
// Depended on by: every formatter and builder. Tests: TrainingTextTests.

import Foundation

public struct TrainingText: Sendable {
    public let language: TrainingLanguage

    public init(_ language: TrainingLanguage) {
        self.language = language
    }

    /// The text for `key` in this language (the English key if missing).
    public func callAsFunction(_ key: TrainingKey) -> String {
        Self.bundle(for: language).localizedString(forKey: key.rawValue, value: key.rawValue, table: nil)
    }

    /// `key` as a format (`%@`, `%lld`), with this language's locale, so a
    /// `.stringsdict` key picks its plural form.
    public func format(_ key: TrainingKey, _ arguments: CVarArg...) -> String {
        String(format: self(key), locale: language.locale, arguments: arguments)
    }

    /// Whether `key` exists in this language's table (tests).
    func hasEntry(_ key: TrainingKey) -> Bool {
        let missing = "\u{1}missing\u{1}"
        return Self.bundle(for: language).localizedString(forKey: key.rawValue, value: missing, table: nil) != missing
    }

    private static let englishBundle = lprojBundle("en")
    private static let czechBundle = lprojBundle("cs")

    static func bundle(for language: TrainingLanguage) -> Bundle {
        switch language {
        case .english: return englishBundle
        case .czech: return czechBundle
        }
    }

    private static func lprojBundle(_ code: String) -> Bundle {
        guard let path = Bundle.module.path(forResource: code, ofType: "lproj"), let bundle = Bundle(path: path) else {
            return Bundle.module
        }
        return bundle
    }
}

// MARK: - Numbers and amounts

/// Numbers in the language's style ("10.1" / "10,1"), no grouping, so a
/// value reads the same everywhere. Units (km, min, h, s, bpm, g) are the
/// same in English and Czech.
public enum NumberText {
    public static func decimal(_ value: Double, _ language: TrainingLanguage, maxFractionDigits: Int = 1) -> String {
        let formatter = NumberFormatter()
        formatter.locale = language.locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = maxFractionDigits
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    /// "10 km", "10.1 km".
    public static func distance(_ km: Double, _ language: TrainingLanguage) -> String {
        "\(decimal(km, language)) km"
    }

    /// "45 min", "1 h", "1 h 30 min".
    public static func duration(minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        if rest == 0 { return "\(hours) h" }
        return "\(hours) h \(rest) min"
    }

    /// Step durations may be fractional ("7.5 min").
    public static func duration(minutes: Double, _ language: TrainingLanguage) -> String {
        if minutes.rounded() == minutes, abs(minutes) < 100_000 { return duration(minutes: Int(minutes)) }
        return "\(decimal(minutes, language)) min"
    }

    /// "45 s", or "2 min" for whole minutes of 120 s and more.
    public static func seconds(_ seconds: Int) -> String {
        if seconds >= 120, seconds % 60 == 0 { return duration(minutes: seconds / 60) }
        return "\(seconds) s"
    }
}
