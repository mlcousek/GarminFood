// ChallengeHistory.swift
//
// Completed challenges, for the challenges screen's "completed" list
// (progress-screens spec). `ChallengeStore` keeps only the active challenge
// and a private list of recently used template ids for rotation, so this is
// the first place a completion is remembered with its date and reward.

import Foundation

public struct CompletedChallenge: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let templateId: String
    public let completedAt: Date
    public let xpAwarded: Int

    public init(id: UUID = UUID(), templateId: String, completedAt: Date, xpAwarded: Int) {
        self.id = id
        self.templateId = templateId
        self.completedAt = completedAt
        self.xpAwarded = xpAwarded
    }
}

public actor ChallengeHistoryStore {
    /// Bounded like the package's other stores. At one or two completions a
    /// week, 300 records is years of history -- also generous margin above
    /// the 226-template catalog (expand-gamification-depth), so the
    /// "complete every challenge" achievement's distinct-template count
    /// (derived from these records) doesn't lose a never-repeated
    /// template's only completion record to eviction before all of them
    /// are reached.
    public static let maxStoredRecords = 300

    private let fileURL: URL
    private var records: [CompletedChallenge] = [] // oldest first
    private var loaded = false

    public init(fileURL: URL = ChallengeHistoryStore.defaultFileURL()) {
        self.fileURL = fileURL
    }

    public static func defaultFileURL() -> URL {
        GamificationStorage.directory().appendingPathComponent("challenge-history.json")
    }

    /// Newest first.
    public func all() -> [CompletedChallenge] {
        loadIfNeeded()
        return records.reversed()
    }

    public func record(_ completed: CompletedChallenge) throws {
        loadIfNeeded()
        records.append(completed)
        if records.count > Self.maxStoredRecords {
            records.removeFirst(records.count - Self.maxStoredRecords)
        }
        try persist()
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        records = GamificationStorage.loadPersistedJSON([CompletedChallenge].self, from: fileURL, decoder: decoder, category: "ChallengeHistoryStore") ?? []
    }

    private func persist() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(records)
        try data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: fileURL.path
        )
    }
}
