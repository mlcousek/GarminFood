// HubPath.swift
//
// A path relative to the vault's training hub (`Sport/Training/_hub`), the
// only kind of path any VaultKit API accepts (add-vault-connection design
// D4, D9). Why a type rather than a `String`: the path allow-lists
// (`VaultPathPolicy`) are only sound if they judge the same string that ends
// up in the request URL. So a `HubPath` can only exist in NORMAL form --
// relative, `/`-separated, every segment made of ASCII letters, digits and
// `-_.` and none of them empty, `.` or `..`. Anything else (a backslash,
// percent-encoding, a control character, a leading or trailing slash,
// traversal) is refused by `init?`, never "fixed": fixing a path is how a
// traversal slips past a check.
//
// The hub root is a contract constant agreed with the vault, not a secret
// (`VaultHub.root`); the repository owner and name never appear here.
//
// Depended on by: VaultPathPolicy, GitHubContentsClient, VaultTransport,
// SealedFile, ConditionalFileSync. Tests: VaultPathPolicyTests.

import Foundation

public struct HubPath: Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: String

    /// Longest accepted path, in characters. Real hub paths are well under
    /// a hundred; the cap keeps a URL from growing without bound.
    public static let maxLength = 400

    public init?(_ rawValue: String) {
        guard Self.isNormal(rawValue) else { return nil }
        self.rawValue = rawValue
    }

    public var segments: [String] {
        rawValue.split(separator: "/").map(String.init)
    }

    public var lastSegment: String {
        segments.last ?? rawValue
    }

    public var description: String { rawValue }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let path = HubPath(raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "not a normal hub-relative path")
        }
        self = path
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    /// See this file's header for the rules.
    static func isNormal(_ path: String) -> Bool {
        guard !path.isEmpty, path.unicodeScalars.count <= maxLength else { return false }
        let segments = path.split(separator: "/", omittingEmptySubsequences: false)
        for segment in segments {
            if segment.isEmpty || segment == "." || segment == ".." { return false }
            for scalar in segment.unicodeScalars where !isAllowed(scalar) {
                return false
            }
        }
        return true
    }

    private static func isAllowed(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x30...0x39, 0x41...0x5A, 0x61...0x7A: return true // 0-9 A-Z a-z
        case 0x2D, 0x5F, 0x2E: return true // - _ .
        default: return false
        }
    }
}

/// Contract constants shared with the vault's side of the hub.
public enum VaultHub {
    /// Where the hub lives in the vault repository (design D2).
    public static let root = "Sport/Training/_hub"

    /// The one file the app reads in this change: the projection the vault
    /// generates for the phone.
    public static let projectionPath = HubPath("projection/projection.v1.json")!
}
