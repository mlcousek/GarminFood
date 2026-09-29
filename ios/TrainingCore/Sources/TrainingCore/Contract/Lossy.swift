// Lossy.swift
//
// The tolerance machinery behind reading the projection (design D2): a
// broken element of a list or map is dropped and COUNTED instead of
// failing the whole file, so one session without an `id` or a day with a
// malformed date costs that element, never the plan.
//
//   - `LossyArray<T>` / `LossyMap<T>`: decode each element through a slot
//     that never throws (so the container always advances), keep the good
//     ones and record each failure.
//   - `DecodeIssues`: what was dropped (element kind, path, reason,
//     English), collected through the decoder's `userInfo` while
//     `ProjectionDecoder` runs, and summarised into ONE Diagnostics line
//     per fetch ("session skipped x1: missing id").
//   - `JSONValue`: a value kept verbatim, for the contract's reserved
//     fields whose shape isn't fixed yet (acks, outcomes, watch, origin...).
//   - Lenient field helpers: an optional field of the wrong type reads as
//     absent (`null`, a missing key and an empty list are the same thing,
//     D4), numbers are accepted whether written as integers or decimals.
//
// Depended on by: Projection.swift, ProjectionDecoder. Tests:
// ContractPrimitivesTests, ProjectionDecodingTests.

import Foundation

// MARK: - Issues

/// One element dropped while decoding.
public struct DecodeIssue: Hashable, Sendable {
    /// "session", "day", "week", ... (see `ProjectionElement`).
    public let element: String
    /// Where it was, e.g. `plan.weeks[1].days[3].sessions[0]`.
    public let path: String
    /// "missing id", "malformed date", ... (English, for Diagnostics).
    public let reason: String

    public init(element: String, path: String, reason: String) {
        self.element = element
        self.path = path
        self.reason = reason
    }
}

public struct DecodeIssues: Hashable, Sendable {
    public var issues: [DecodeIssue]

    public init(_ issues: [DecodeIssue] = []) {
        self.issues = issues
    }

    public var isEmpty: Bool { issues.isEmpty }
    public var count: Int { issues.count }

    /// One line for Diagnostics, grouped by element and reason in the order
    /// first seen: "session skipped x1: missing id; day skipped x2:
    /// malformed date". `nil` when nothing was dropped.
    public var summary: String? {
        guard !issues.isEmpty else { return nil }
        var order: [String] = []
        var counts: [String: Int] = [:]
        for issue in issues {
            let key = "\(issue.element) skipped x%d: \(issue.reason)"
            if counts[key] == nil { order.append(key) }
            counts[key, default: 0] += 1
        }
        return order.map { key in
            key.replacingOccurrences(of: "x%d", with: "x\(counts[key] ?? 0)")
        }.joined(separator: "; ")
    }
}

/// Collects issues during one decode. Reference type so every nested
/// decoder shares it through `userInfo`; locked because `Decoder` makes no
/// threading promise.
final class DecodeIssueCollector: @unchecked Sendable {
    static let userInfoKey = CodingUserInfoKey(rawValue: "trainingcore.decodeIssues")!

    private let lock = NSLock()
    private var collected: [DecodeIssue] = []

    var issues: DecodeIssues {
        lock.lock()
        defer { lock.unlock() }
        return DecodeIssues(collected)
    }

    func append(_ issue: DecodeIssue) {
        lock.lock()
        collected.append(issue)
        lock.unlock()
    }

    static func record(_ error: Error, element: String, decoder: Decoder) {
        guard let collector = decoder.userInfo[userInfoKey] as? DecodeIssueCollector else { return }
        collector.append(DecodeIssue(element: element, path: pathString(decoder.codingPath), reason: reason(error)))
    }

    /// `plan.weeks[1].days[3]`: array indexes in brackets.
    static func pathString(_ path: [CodingKey]) -> String {
        var result = ""
        for key in path {
            if let index = key.intValue {
                result += "[\(index)]"
            } else {
                if !result.isEmpty { result += "." }
                result += key.stringValue
            }
        }
        return result
    }

    static func reason(_ error: Error) -> String {
        guard let error = error as? DecodingError else { return "unreadable" }
        switch error {
        case .keyNotFound(let key, _):
            return "missing \(key.stringValue)"
        case .valueNotFound(_, let context):
            return "missing \(context.codingPath.last.map { fieldName($0) } ?? "value")"
        case .typeMismatch(_, let context), .dataCorrupted(let context):
            return "malformed \(context.codingPath.last.map { fieldName($0) } ?? "value")"
        @unknown default:
            return "unreadable"
        }
    }

    private static func fieldName(_ key: CodingKey) -> String {
        key.intValue == nil ? key.stringValue : "element"
    }
}

/// A model that can be dropped from a list: its name in the summary.
public protocol ProjectionElement {
    static var elementName: String { get }
}

// MARK: - Lossy containers

/// Decodes one element without ever throwing, so a container always
/// advances past it; a failure is recorded.
struct DecodeSlot<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        do {
            value = try Value(from: decoder)
        } catch {
            value = nil
            let name = (Value.self as? ProjectionElement.Type)?.elementName ?? String(describing: Value.self)
            DecodeIssueCollector.record(error, element: name, decoder: decoder)
        }
    }
}

/// A list whose broken elements are dropped (and recorded).
public struct LossyArray<Element: Decodable>: Decodable {
    public let elements: [Element]

    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var result: [Element] = []
        while !container.isAtEnd {
            let slot = try container.decode(DecodeSlot<Element>.self)
            if let value = slot.value { result.append(value) }
        }
        elements = result
    }
}

/// A map whose broken values are dropped (and recorded).
public struct LossyMap<Value: Decodable>: Decodable {
    public let values: [String: Value]

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        var result: [String: Value] = [:]
        for key in container.allKeys {
            let slot = try container.decode(DecodeSlot<Value>.self, forKey: key)
            if let value = slot.value { result[key.stringValue] = value }
        }
        values = result
    }
}

/// A coding key for maps with arbitrary keys (workouts, zones, results).
public struct AnyCodingKey: CodingKey, Hashable, Sendable {
    public let stringValue: String
    public let intValue: Int?

    public init(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    public init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

// MARK: - Verbatim values

/// Any JSON value, kept as is: the contract's reserved fields (design D8)
/// have a slot now and a meaning once a later vault change fills them.
public enum JSONValue: Hashable, Sendable, Decodable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    public var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    /// A field of an object value, or `nil`.
    public subscript(key: String) -> JSONValue? {
        if case .object(let fields) = self { return fields[key] }
        return nil
    }
}

/// A value the vault may write as a string or a number (`reps: 8` and
/// `reps: "8-12"`, `load: "40 kg"`), kept as display text.
public struct ScalarText: Hashable, Sendable, Decodable, CustomStringConvertible {
    public let text: String

    public init(_ text: String) {
        self.text = text
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Int.self) {
            text = String(value)
        } else if let value = try? container.decode(Double.self) {
            text = value.rounded() == value ? String(Int(value)) : String(value)
        } else {
            text = try container.decode(String.self)
        }
    }

    public var description: String { text }
}

// MARK: - Lenient field helpers

extension KeyedDecodingContainer {
    /// An optional field: absent, `null` or of the wrong type all read as
    /// `nil` (design D4).
    func lenient<T: Decodable>(_ type: T.Type, _ key: Key) -> T? {
        guard let value = try? decodeIfPresent(type, forKey: key) else { return nil }
        return value
    }

    /// Integer minutes, counts and bpm, accepted as `45` or `45.0`.
    func lenientInt(_ key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value }
        guard let value = try? decodeIfPresent(Double.self, forKey: key), value.isFinite,
              abs(value) < Double(Int32.max)
        else { return nil }
        return Int(value.rounded())
    }

    func lenientDouble(_ key: Key) -> Double? {
        guard let value = try? decodeIfPresent(Double.self, forKey: key), value.isFinite else { return nil }
        return value
    }

    func lenientBool(_ key: Key) -> Bool? {
        lenient(Bool.self, key)
    }

    func lenientString(_ key: Key) -> String? {
        lenient(String.self, key)
    }

    /// A list; a broken element is dropped and recorded, a missing or
    /// malformed list is empty.
    func lossyList<T: Decodable>(_ type: T.Type, _ key: Key) -> [T] {
        lenient(LossyArray<T>.self, key)?.elements ?? []
    }

    /// A map; a broken value is dropped and recorded.
    func lossyMap<T: Decodable>(_ type: T.Type, _ key: Key) -> [String: T] {
        lenient(LossyMap<T>.self, key)?.values ?? [:]
    }

    /// A list of strings, non-strings skipped quietly (ids, weekday codes).
    func stringList(_ key: Key) -> [String] {
        (lenient([JSONValue].self, key) ?? []).compactMap(\.stringValue)
    }

    /// `{ key: number }`, non-numbers skipped quietly.
    func numberMap(_ key: Key) -> [String: Double]? {
        guard let raw = lenient([String: JSONValue].self, key) else { return nil }
        var result: [String: Double] = [:]
        for (name, value) in raw {
            if case .number(let number) = value { result[name] = number }
        }
        return result
    }

    /// `{ key: int }`, non-numbers skipped quietly.
    func intMap(_ key: Key) -> [String: Int]? {
        numberMap(key).map { $0.mapValues { Int($0.rounded()) } }
    }

    /// A required identity field: present, a non-empty string.
    func identity(_ key: Key) throws -> String {
        let value = try decode(String.self, forKey: key)
        guard !value.isEmpty else {
            throw DecodingError.valueNotFound(String.self, DecodingError.Context(codingPath: codingPath + [key], debugDescription: "empty identity"))
        }
        return value
    }
}
