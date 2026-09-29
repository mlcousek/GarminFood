// EventSegment.swift
//
// Turns unsent events into one immutable vault file (add-training-checkins
// design D4; the architecture note's "seal, then send"): the events'
// JSONL bytes (HubEventCodec), a path inside the install's own folder, and
// a commit message, frozen together as VaultKit's `SealedFile`, so every
// retry sends exactly the same bytes and the create-only upload can tell
// "an earlier attempt already landed" from a real collision.
//
//   path     events/<deviceId>/<yyyy>/<mm>/<yyyymmddThhmmssZ>-<firstSeq>.jsonl
//            (the seal time in UTC; `yyyy/mm` of that time), which
//            `VaultPathPolicy.allowsWrite` accepts for the own device id;
//   message  "hub: ios-0000beef seq 7-9 (3)" -- distinct from the vault's
//            own "vault backup: ..." commits, so history can be filtered.
//
// At most `maxEvents` (500) per file, oldest first. A name can't collide:
// it embeds the device id, the second and the first sequence number, and a
// sequence number is never handed out twice.
//
// Depended on by: TrainingRecorder.seal. Tests: EventSegmentTests.

import Foundation
import VaultKit

public enum EventSegmentError: Error, Equatable, Sendable {
    case empty
    case invalidPath
}

public enum EventSegment {
    public static let maxEvents = 500

    /// The segment's hub-relative path; `nil` only if the id were not a
    /// valid path segment (it always is: `ios-` + 8 hex).
    public static func path(deviceID: VaultDeviceID, sealedAt: Date, firstSeq: Int) -> HubPath? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0)!
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: sealedAt)
        let year = c.year ?? 1970
        let month = c.month ?? 1
        let stamp = String(format: "%04d%02d%02dT%02d%02d%02dZ", year, month, c.day ?? 1, c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
        let folder = String(format: "%04d/%02d", year, month)
        return HubPath("\(VaultPathPolicy.eventsFolder)/\(deviceID.rawValue)/\(folder)/\(stamp)-\(firstSeq)\(VaultPathPolicy.eventFileExtension)")
    }

    public static func commitMessage(deviceID: VaultDeviceID, events: [HubEvent]) -> String {
        let seqs = events.map(\.seq)
        let first = seqs.min() ?? 0
        let last = seqs.max() ?? 0
        let range = first == last ? "\(first)" : "\(first)-\(last)"
        return "hub: \(deviceID.rawValue) seq \(range) (\(events.count))"
    }

    /// One sealed file for `events` (already this device's, oldest first).
    public static func seal(_ events: [HubEvent], deviceID: VaultDeviceID, sealedAt: Date) throws -> SealedFile {
        guard let first = events.first else { throw EventSegmentError.empty }
        guard let path = path(deviceID: deviceID, sealedAt: sealedAt, firstSeq: first.seq) else {
            throw EventSegmentError.invalidPath
        }
        return SealedFile(
            path: path,
            bytes: try HubEventCodec.jsonl(events),
            commitMessage: commitMessage(deviceID: deviceID, events: events),
            createdAt: sealedAt
        )
    }

    /// `events` in chunks of at most `maxEvents`.
    public static func chunks(_ events: [HubEvent]) -> [[HubEvent]] {
        var result: [[HubEvent]] = []
        var start = 0
        while start < events.count {
            let end = min(start + maxEvents, events.count)
            result.append(Array(events[start..<end]))
            start = end
        }
        return result
    }
}
