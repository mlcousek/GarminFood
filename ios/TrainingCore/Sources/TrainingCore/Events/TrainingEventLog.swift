// TrainingEventLog.swift
//
// The phone's local, append-only log of the training events it produced
// (add-training-checkins design D3) -- the outbox of the architecture note:
// "every app action is an event committed locally first". `append` returns
// only after the event is on disk, so a check-in survives a crash, airplane
// mode or a dead token; delivery to the vault is a later, separate drain
// (EventSegment + VaultKit's write queue).
//
// Each entry remembers the segment it was sealed into (`segmentID`, the
// `SealedFile.id`), which is how the overlay tells "saved on phone" from
// "sent". Sealed entries are kept `sealedRetention` (21 days) after they
// were recorded -- long enough for the vault to ingest them and publish the
// result in the projection -- and then pruned; unsealed entries are never
// pruned.
//
// File: `Application Support/VaultKit/training-events.json`. Living under
// `VaultKit/` puts it inside the directory data-safety already excludes
// from backups (design D3, tasks 0.4). Loaded through GarminKit's
// `PersistedJSON`: an undecodable file is quarantined, never wiped; a file
// that exists but can't be read yet (before first unlock) is never
// overwritten.
//
// Depended on by: TrainingRecorder. Tests: TrainingEventLogTests.

import Foundation
import GarminKit
import VaultKit

public struct LoggedEvent: Codable, Equatable, Sendable, Identifiable {
    public let event: HubEvent
    public let recordedAt: Date
    /// The segment (`SealedFile.id`) this event was sealed into.
    public var segmentID: UUID?

    public var id: String { event.id }
    public var isSealed: Bool { segmentID != nil }

    public init(event: HubEvent, recordedAt: Date, segmentID: UUID? = nil) {
        self.event = event
        self.recordedAt = recordedAt
        self.segmentID = segmentID
    }
}

public actor TrainingEventLog {
    public static let fileName = "training-events.json"
    public static let sealedRetention: TimeInterval = 21 * 86_400

    private let fileURL: URL
    private var entries: [LoggedEvent] = []
    private var loaded = false

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// The app's log, next to VaultKit's other files.
    public static func make(directory: URL = VaultStorage.defaultDirectory()) -> TrainingEventLog {
        TrainingEventLog(fileURL: directory.appendingPathComponent(fileName))
    }

    // MARK: Reading

    public func all() -> [LoggedEvent] {
        loadIfNeeded()
        return entries
    }

    public func unsealed() -> [LoggedEvent] {
        loadIfNeeded()
        return entries.filter { !$0.isSealed }
    }

    // MARK: Writing

    /// Durable on return.
    public func append(_ event: HubEvent, now: Date = Date()) throws {
        loadIfNeeded()
        try write(entries + [LoggedEvent(event: event, recordedAt: now)])
    }

    /// Marks the events with `ids` as sealed into `segment`.
    public func markSealed(_ ids: [String], segment: UUID) throws {
        loadIfNeeded()
        let set = Set(ids)
        var updated = entries
        for index in updated.indices where set.contains(updated[index].event.id) && updated[index].segmentID == nil {
            updated[index].segmentID = segment
        }
        guard updated != entries else { return }
        try write(updated)
    }

    /// Drops sealed entries recorded more than `sealedRetention` ago.
    public func prune(now: Date = Date()) throws {
        loadIfNeeded()
        let cutoff = now.addingTimeInterval(-Self.sealedRetention)
        let kept = entries.filter { !($0.isSealed && $0.recordedAt < cutoff) }
        guard kept.count != entries.count else { return }
        try write(kept)
    }

    // MARK: Storage

    private static let category = "training"

    private func loadIfNeeded() {
        guard !loaded else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let result = PersistedJSON.load([LoggedEvent].self, from: fileURL, decoder: decoder, category: Self.category)
        entries = result.value ?? []
        loaded = !result.isUnreadable
    }

    private func write(_ list: [LoggedEvent]) throws {
        try PersistedJSON.ensureSafeToWrite(loaded: loaded, fileURL: fileURL, category: Self.category)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(list)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        // Same data protection as the Garmin outboxes and VaultKit's files.
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: fileURL.path
        )
        entries = list
    }
}
