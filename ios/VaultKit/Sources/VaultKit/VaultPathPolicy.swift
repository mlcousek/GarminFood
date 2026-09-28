// VaultPathPolicy.swift
//
// The pure allow-lists every vault request is checked against BEFORE it is
// sent (add-vault-connection design D4, spec "The app may write only into
// its own events folder and read only its allowed files"):
//
//   write: `events/<ownDeviceId>/.../<name>.jsonl` -- this install's own
//          folder, at least one level below it, `.jsonl` only;
//   read:  `projection/<name>.json` -- the projection files, one level;
//          `events/<ownDeviceId>/...` -- the install's own folder (the
//          create-only idempotency check, design D7, reads back what it
//          wrote).
//
// Everything else is refused, including another device's folder, and every
// events path while this install has no device id yet. Paths are
// `HubPath`s, already normal (no `..`, no encoding tricks), so the check is
// plain segment comparison -- there is nothing left to normalise.
//
// It limits the app's own bugs, not a stolen token: GitHub has no per-path
// token permissions (design D4, docs/vault-connection.md). Enforced inside
// `GitHubContentsClient`, the only type that builds request URLs, and
// applied by every `VaultTransport` (the in-memory test transport too).
//
// Tests: VaultPathPolicyTests.

import Foundation

public struct VaultPathPolicy: Equatable, Sendable {
    /// This install's id, or `nil` before the first successful connection
    /// test (design D5), in which case no events path is allowed at all.
    public let ownDeviceID: VaultDeviceID?

    public init(ownDeviceID: VaultDeviceID?) {
        self.ownDeviceID = ownDeviceID
    }

    public static let projectionFolder = "projection"
    public static let eventsFolder = "events"
    public static let eventFileExtension = ".jsonl"
    public static let projectionFileExtension = ".json"

    public func allowsRead(_ path: HubPath) -> Bool {
        let segments = path.segments
        if segments.count == 2, segments[0] == Self.projectionFolder {
            return Self.hasNamedExtension(segments[1], Self.projectionFileExtension)
        }
        return isInOwnEventsFolder(segments)
    }

    public func allowsWrite(_ path: HubPath) -> Bool {
        let segments = path.segments
        guard isInOwnEventsFolder(segments), let last = segments.last else { return false }
        return Self.hasNamedExtension(last, Self.eventFileExtension)
    }

    /// `events/<ownDeviceId>/<at least one more segment>`.
    private func isInOwnEventsFolder(_ segments: [String]) -> Bool {
        guard let own = ownDeviceID else { return false }
        return segments.count >= 3
            && segments[0] == Self.eventsFolder
            && segments[1] == own.rawValue
    }

    /// `name` ends in `ext` and has something before it (`.jsonl` alone is
    /// not a file name).
    private static func hasNamedExtension(_ name: String, _ ext: String) -> Bool {
        name.hasSuffix(ext) && name.count > ext.count
    }
}
