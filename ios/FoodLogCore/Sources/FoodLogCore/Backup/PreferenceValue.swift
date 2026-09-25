// PreferenceValue.swift
//
// add-data-safety D3: the app's UserDefaults travel with every snapshot and
// export as JSON. Why typed rather than plain JSON values: UserDefaults
// holds property-list values, where Bool, Int, Double, Date and Data are
// distinct, and several are read back with `as? Bool` / `as? Int` / `as?
// Double` (AppPreferences.swift). Plain JSON would turn a Bool into 0/1 or
// a Date into a string, and a restored preference would silently read as
// its default. `{"type": "...", "value": ...}` keeps every value exact while
// staying readable in a text editor. (A property-list blob would be exact
// too, but the owner asked for JSON, and JSON is what the secret scan and a
// human can read.)
//
// `PreferencesBackup` is the pure half of reading and writing the domain:
// the app passes in `UserDefaults.persistentDomain(forName:)` and applies
// the result with `setPersistentDomain(_:forName:)`, so this stays testable
// without touching the real defaults.
//
// Depends on: BackupExclusions (which keys travel).

import Foundation

public indirect enum PreferenceValue: Equatable, Sendable {
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case date(Date)
    case data(Data)
    case array([PreferenceValue])
    case dictionary([String: PreferenceValue])

    /// Converts a property-list value as UserDefaults returns it (NSString,
    /// NSNumber, NSDate, NSData, NSArray, NSDictionary). `nil` for anything
    /// that isn't a property-list type.
    public init?(propertyListValue value: Any) {
        switch value {
        case let string as String:
            self = .string(string)
        case let date as Date:
            self = .date(date)
        case let data as Data:
            self = .data(data)
        case let number as NSNumber:
            // NSNumber can't tell Bool from 0/1 by value, only by its
            // CoreFoundation type: `true` is the kCFBooleanTrue singleton.
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else if CFNumberIsFloatType(number as CFNumber) {
                self = .double(number.doubleValue)
            } else {
                self = .int(number.intValue)
            }
        case let array as [Any]:
            var converted: [PreferenceValue] = []
            for element in array {
                guard let value = PreferenceValue(propertyListValue: element) else { return nil }
                converted.append(value)
            }
            self = .array(converted)
        case let dictionary as [String: Any]:
            var converted: [String: PreferenceValue] = [:]
            for (key, element) in dictionary {
                guard let value = PreferenceValue(propertyListValue: element) else { return nil }
                converted[key] = value
            }
            self = .dictionary(converted)
        default:
            return nil
        }
    }

    /// The value to hand back to UserDefaults.
    public var propertyListValue: Any {
        switch self {
        case .bool(let value): return value
        case .int(let value): return value
        case .double(let value): return value
        case .string(let value): return value
        case .date(let value): return value
        case .data(let value): return value
        case .array(let values): return values.map(\.propertyListValue)
        case .dictionary(let values): return values.mapValues(\.propertyListValue)
        }
    }
}

extension PreferenceValue: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "bool":
            self = .bool(try container.decode(Bool.self, forKey: .value))
        case "int":
            self = .int(try container.decode(Int.self, forKey: .value))
        case "double":
            self = .double(try container.decode(Double.self, forKey: .value))
        case "string":
            self = .string(try container.decode(String.self, forKey: .value))
        case "date":
            // Seconds since 1970 as a number: independent of whichever date
            // strategy the enclosing encoder uses.
            self = .date(Date(timeIntervalSince1970: try container.decode(Double.self, forKey: .value)))
        case "data":
            let base64 = try container.decode(String.self, forKey: .value)
            guard let data = Data(base64Encoded: base64) else {
                throw DecodingError.dataCorruptedError(forKey: .value, in: container, debugDescription: "preference data is not base64")
            }
            self = .data(data)
        case "array":
            self = .array(try container.decode([PreferenceValue].self, forKey: .value))
        case "dictionary":
            self = .dictionary(try container.decode([String: PreferenceValue].self, forKey: .value))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "unknown preference type \(type)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .bool(let value):
            try container.encode("bool", forKey: .type)
            try container.encode(value, forKey: .value)
        case .int(let value):
            try container.encode("int", forKey: .type)
            try container.encode(value, forKey: .value)
        case .double(let value):
            try container.encode("double", forKey: .type)
            try container.encode(value, forKey: .value)
        case .string(let value):
            try container.encode("string", forKey: .type)
            try container.encode(value, forKey: .value)
        case .date(let value):
            try container.encode("date", forKey: .type)
            try container.encode(value.timeIntervalSince1970, forKey: .value)
        case .data(let value):
            try container.encode("data", forKey: .type)
            try container.encode(value.base64EncodedString(), forKey: .value)
        case .array(let values):
            try container.encode("array", forKey: .type)
            try container.encode(values, forKey: .value)
        case .dictionary(let values):
            try container.encode("dictionary", forKey: .type)
            try container.encode(values, forKey: .value)
        }
    }
}

/// Reading and replacing the app's preferences for a backup, as pure
/// functions over a UserDefaults persistent domain.
public enum PreferencesBackup {
    /// The keys of `domain` that travel with a backup
    /// (`BackupExclusions.includesPreference`), converted to typed values.
    /// A value that isn't a property-list type is skipped.
    public static func capture(domain: [String: Any]) -> [String: PreferenceValue] {
        var captured: [String: PreferenceValue] = [:]
        for (key, value) in domain where BackupExclusions.includesPreference(key: key) {
            if let converted = PreferenceValue(propertyListValue: value) {
                captured[key] = converted
            }
        }
        return captured
    }

    /// The domain after restoring `backup` over `current`: every key a
    /// backup may carry is replaced by the backup's (and removed when the
    /// backup lacks it -- restore replaces, never merges), while excluded
    /// keys (`dataSafety.*`, developer switches, system keys) keep their
    /// current values. Backup keys that are excluded here are ignored too,
    /// so a crafted file cannot set them.
    public static func restoredDomain(current: [String: Any], backup: [String: PreferenceValue]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in current where !BackupExclusions.includesPreference(key: key) {
            result[key] = value
        }
        for (key, value) in backup where BackupExclusions.includesPreference(key: key) {
            result[key] = value.propertyListValue
        }
        return result
    }
}
