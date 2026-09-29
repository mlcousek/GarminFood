// LocalizedText.swift
//
// Text from the plan in the app's language (spec "Text from the plan
// appears in the app's language", design D2). The contract writes
// localised text as an object of language codes -- `{ "en": ..., "cz": ... }`
// with `cz`, not `cs` -- and some fields (habit `dose` and `why`, race
// `name`, `goal`) as a plain string. Both decode here:
//
//   - Czech app: `cs`, then the vault's `cz`, then `en`, then the first
//     non-empty value;
//   - English app: `en`, then any;
//   - a plain string shows as is in every language.
//
// "First" is by sorted language code, because a JSON object's key order
// isn't preserved by `JSONDecoder`; it only matters for a language the app
// doesn't speak.
//
// `TrainingLanguage` is the app's language as the builders see it; the app
// derives it once from its bundle's preferred localization.
//
// Depended on by: every model with display text, every builder. Tests:
// ContractPrimitivesTests.

import Foundation

/// The two languages the app ships (add-localization).
public enum TrainingLanguage: String, CaseIterable, Sendable {
    case english = "en"
    case czech = "cs"

    /// The lproj folder / language code.
    public var code: String { rawValue }

    /// The locale numbers and plurals are formatted with.
    public var locale: Locale {
        switch self {
        case .english: return Locale(identifier: "en_GB")
        case .czech: return Locale(identifier: "cs_CZ")
        }
    }

    /// From a bundle's `preferredLocalizations` (the app's language, which
    /// Settings -> Language can set per app): Czech for `cs*`, else English.
    public static func from(preferredLocalizations: [String]) -> TrainingLanguage {
        guard let first = preferredLocalizations.first?.lowercased() else { return .english }
        return first.hasPrefix("cs") || first.hasPrefix("cz") ? .czech : .english
    }

    /// Language codes to try, in order, before "any non-empty value".
    var lookupOrder: [String] {
        switch self {
        case .english: return ["en"]
        case .czech: return ["cs", "cz", "en"]
        }
    }
}

public struct LocalizedText: Hashable, Sendable, Decodable {
    /// Language code -> text. A plain string is stored under `""`.
    public let values: [String: String]

    public init(_ plain: String) {
        values = ["": plain]
    }

    public init(values: [String: String]) {
        self.values = values
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let plain = try? container.decode(String.self) {
            values = ["": plain]
            return
        }
        let object = try container.decode([String: JSONValue].self)
        var result: [String: String] = [:]
        for (code, value) in object {
            if let text = value.stringValue { result[code] = text }
        }
        values = result
    }

    /// The text for `language` (see this file's header), or `""`.
    public func resolved(_ language: TrainingLanguage) -> String {
        if let plain = values[""], !plain.isEmpty { return plain }
        for code in language.lookupOrder {
            if let text = values[code], !text.isEmpty { return text }
        }
        for code in values.keys.sorted() {
            if let text = values[code], !text.isEmpty { return text }
        }
        return ""
    }

    public var isEmpty: Bool {
        values.values.allSatisfy { $0.isEmpty }
    }
}

public extension Optional where Wrapped == LocalizedText {
    /// `nil` for absent or empty text.
    func resolvedText(_ language: TrainingLanguage) -> String? {
        guard let text = self?.resolved(language), !text.isEmpty else { return nil }
        return text
    }
}
