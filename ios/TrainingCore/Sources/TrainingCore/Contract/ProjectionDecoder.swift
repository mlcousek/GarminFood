// ProjectionDecoder.swift
//
// The two-step decode of design D2: the `ProjectionHeader` first, then --
// only for `schema: "hub.projection"`, `schemaVersion: 1` -- the full v1
// model with issue collection.
//
//   | Header                          | Result                              |
//   | schema != "hub.projection"      | .invalid("not a plan projection")   |
//   | schemaVersion > 1               | .unsupportedMajor(found) -- LOUD    |
//   | schemaVersion == 1              | full decode                         |
//   | schemaVersion missing or < 1    | .invalid                            |
//
// A higher major inside the v1 file means something went wrong on the
// vault side (it writes v1 and v2 side by side during a breaking change),
// so the app says "update" loudly and keeps the last good plan. Any other
// failure of the whole document (not JSON, not an object, a top-level
// section of the wrong type) is `.invalid(reason)`.
//
// `ProjectionRejection` is also the validator's error, so its description
// is what `ConditionalFileSync` logs and reports; `init?(reportReason:)`
// reads it back (ProjectionStore).
//
// Depended on by: ProjectionStore (validator and cached decode). Tests:
// ProjectionDecodingTests, ProjectionStoreTests.

import Foundation

/// What decides whether the rest of the file is read at all.
public struct ProjectionHeader: Equatable, Sendable, Decodable {
    public static let schemaName = "hub.projection"
    public static let supportedMajor = 1

    public var schema: String?
    public var schemaVersion: Int?
    public var generatedAt: String?
    public var asOf: LocalDate?

    enum CodingKeys: String, CodingKey { case schema, schemaVersion, generatedAt, asOf }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = c.lenientString(.schema)
        schemaVersion = c.lenientInt(.schemaVersion)
        generatedAt = c.lenientString(.generatedAt)
        asOf = c.lenient(LocalDate.self, .asOf)
    }
}

/// Why a fetched projection was not accepted.
public enum ProjectionRejection: Error, Equatable, Sendable, CustomStringConvertible {
    /// A newer major than this build reads: "Update Jirka's Arc".
    case unsupportedMajor(found: Int)
    /// Anything else unreadable (English reason, for Diagnostics).
    case invalid(reason: String)

    static let majorPrefix = "unsupported schemaVersion "
    static let invalidPrefix = "invalid projection: "

    public var description: String {
        switch self {
        case .unsupportedMajor(let found): return "\(Self.majorPrefix)\(found)"
        case .invalid(let reason): return "\(Self.invalidPrefix)\(reason)"
        }
    }

    /// Reads back a `FetchReport.rejected(reason:)` produced by this
    /// validator; `nil` for any other text.
    public init?(reportReason: String) {
        if reportReason.hasPrefix(Self.majorPrefix), let found = Int(reportReason.dropFirst(Self.majorPrefix.count)) {
            self = .unsupportedMajor(found: found)
        } else if reportReason.hasPrefix(Self.invalidPrefix) {
            self = .invalid(reason: String(reportReason.dropFirst(Self.invalidPrefix.count)))
        } else {
            return nil
        }
    }

    public var isUnsupportedMajor: Bool {
        if case .unsupportedMajor = self { return true }
        return false
    }
}

/// A projection that passed the gates, with what was dropped on the way.
public struct DecodedProjection: Equatable, Sendable {
    public let projection: Projection
    public let issues: DecodeIssues

    public init(projection: Projection, issues: DecodeIssues) {
        self.projection = projection
        self.issues = issues
    }
}

public enum ProjectionDecoder {
    /// The largest file accepted (the vault's example is ~71 KB).
    public static let maxBytes = 5 * 1024 * 1024

    /// Decodes `bytes` per the table in this file's header.
    public static func decode(_ bytes: Data) -> Result<DecodedProjection, ProjectionRejection> {
        guard bytes.count <= maxBytes else {
            return .failure(.invalid(reason: "too large (\(bytes.count) bytes)"))
        }
        guard (try? JSONSerialization.jsonObject(with: bytes)) is [String: Any] else {
            return .failure(.invalid(reason: "not a JSON object"))
        }
        let header: ProjectionHeader
        do {
            header = try JSONDecoder().decode(ProjectionHeader.self, from: bytes)
        } catch {
            return .failure(.invalid(reason: "unreadable header"))
        }
        guard header.schema == ProjectionHeader.schemaName else {
            return .failure(.invalid(reason: "not a plan projection"))
        }
        guard let version = header.schemaVersion, version >= 1 else {
            return .failure(.invalid(reason: "no schemaVersion"))
        }
        guard version <= ProjectionHeader.supportedMajor else {
            return .failure(.unsupportedMajor(found: version))
        }

        let collector = DecodeIssueCollector()
        let decoder = JSONDecoder()
        decoder.userInfo[DecodeIssueCollector.userInfoKey] = collector
        do {
            let projection = try decoder.decode(Projection.self, from: bytes)
            return .success(DecodedProjection(projection: projection, issues: collector.issues))
        } catch {
            let path = DecodeIssueCollector.pathString(codingPath(of: error))
            return .failure(.invalid(reason: "malformed \(path.isEmpty ? "document" : path)"))
        }
    }

    /// The validator `ConditionalFileSync` runs before committing bytes:
    /// throws the rejection, so a bad or too-new file never replaces a
    /// good one (design D5).
    public static func validate(_ bytes: Data) throws {
        if case .failure(let rejection) = decode(bytes) {
            throw rejection
        }
    }

    private static func codingPath(of error: Error) -> [CodingKey] {
        guard let error = error as? DecodingError else { return [] }
        switch error {
        case .keyNotFound(_, let context), .valueNotFound(_, let context),
             .typeMismatch(_, let context), .dataCorrupted(let context):
            return context.codingPath
        @unknown default:
            return []
        }
    }
}
