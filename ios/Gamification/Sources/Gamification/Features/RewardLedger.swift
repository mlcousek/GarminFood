// RewardLedger.swift
//
// Design D8: every reward a gamification feature grants is applied AT MOST
// ONCE, keyed by `RewardGrant.key` ("bingo.line.2026-W39.row0"). Features
// are re-run on every refresh and confirm and are free to re-emit the same
// grant each time; only this ledger decides whether it is new. Keys are kept
// forever (a few thousand short strings a year).
//
// XP grants are added through the existing `XPStore.recordChallengeCompletion
// (xp:)` (a generic add). Streak-freeze grants are only RECORDED here (with
// the day they were earned) -- `add-weekly-boss-and-streak-freezes` replays
// `freezeGrants()` into a balance, so a freeze earned before that change
// ships is not lost.
//
// Ordering: the key is persisted BEFORE the XP is added. A crash between the
// two loses one grant's XP; the reverse order could pay it twice on every
// later run, which is the worse failure for a game economy.
//
// Same JSON-file actor + unreadable-file contract as the other stores
// (`GamificationStorage.loadPersistedJSON`/`ensureSafeToWrite`); every
// persisted field except `key` is Optional so the format can grow.
//
// Depends on: RewardGrant (GamificationFeature.swift), XPStore,
// GamificationStorage.
// Depended on by: the app's FeatureHost; wave 3's freeze balance.

import Foundation

public actor RewardLedger {
    public struct Entry: Codable, Sendable, Equatable {
        public let key: String
        /// "xp" or "streakFreeze".
        public var kind: String?
        public var xp: Int?
        /// `yyyy-MM-dd` nutrition day the grant was applied on.
        public var day: String?
        public var appliedAt: Date?

        public init(key: String, kind: String?, xp: Int?, day: String?, appliedAt: Date?) {
            self.key = key
            self.kind = kind
            self.xp = xp
            self.day = day
            self.appliedAt = appliedAt
        }
    }

    public struct FreezeGrant: Sendable, Equatable {
        public let key: String
        public let day: String
    }

    public struct ApplyResult: Sendable, Equatable {
        /// The grants that were new (in input order); already-recorded keys
        /// and duplicates within the call are skipped.
        public let applied: [RewardGrant]
        public let xpAwarded: Int
        public let xpTotalBefore: Int?
        public let xpTotalAfter: Int?

        public static let empty = ApplyResult(applied: [], xpAwarded: 0, xpTotalBefore: nil, xpTotalAfter: nil)
    }

    private struct Snapshot: Codable {
        var entries: [Entry]?
    }

    private let fileURL: URL
    private var entries: [Entry] = []
    private var keys: Set<String> = []
    private var loaded = false

    public init(fileURL: URL = RewardLedger.defaultFileURL()) {
        self.fileURL = fileURL
    }

    public static func defaultFileURL() -> URL {
        GamificationStorage.directory().appendingPathComponent("reward-ledger.json")
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let result = GamificationStorage.loadPersistedJSON(Snapshot.self, from: fileURL, decoder: decoder, category: "RewardLedger")
        // Unreadable: don't latch; `persist()` refuses to overwrite meanwhile.
        loaded = !result.isUnreadable
        entries = result.value?.entries ?? []
        keys = Set(entries.map(\.key))
    }

    private func persist() throws {
        try GamificationStorage.ensureSafeToWrite(loaded: loaded, fileURL: fileURL, category: "RewardLedger")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(Snapshot(entries: entries))
        try data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: fileURL.path
        )
    }

    public func contains(_ key: String) -> Bool {
        loadIfNeeded()
        return keys.contains(key)
    }

    public func all() -> [Entry] {
        loadIfNeeded()
        return entries
    }

    /// Every streak-freeze grant ever recorded, oldest first.
    public func freezeGrants() -> [FreezeGrant] {
        loadIfNeeded()
        return entries.compactMap { entry in
            guard entry.kind == "streakFreeze" else { return nil }
            return FreezeGrant(key: entry.key, day: entry.day ?? "")
        }
    }

    /// Records the new grants and adds their XP to `xpStore`. Idempotent:
    /// applying the same grants again awards nothing.
    public func apply(_ grants: [RewardGrant], day: String, now: Date, xpStore: XPStore) async throws -> ApplyResult {
        loadIfNeeded()
        var fresh: [RewardGrant] = []
        var seenThisCall = Set<String>()
        for grant in grants where !keys.contains(grant.key) && !seenThisCall.contains(grant.key) {
            seenThisCall.insert(grant.key)
            fresh.append(grant)
        }
        guard !fresh.isEmpty else { return .empty }

        var xp = 0
        for grant in fresh {
            switch grant.kind {
            case .xp(let amount):
                let positive = max(0, amount)
                xp += positive
                entries.append(Entry(key: grant.key, kind: "xp", xp: positive, day: day, appliedAt: now))
            case .streakFreeze:
                entries.append(Entry(key: grant.key, kind: "streakFreeze", xp: nil, day: day, appliedAt: now))
            }
            keys.insert(grant.key)
        }
        do {
            try persist()
        } catch {
            // Roll back the in-memory state so a later run retries.
            let freshKeys = Set(fresh.map(\.key))
            entries.removeAll { freshKeys.contains($0.key) }
            keys.subtract(freshKeys)
            throw error
        }

        guard xp > 0 else {
            return ApplyResult(applied: fresh, xpAwarded: 0, xpTotalBefore: nil, xpTotalAfter: nil)
        }
        let result = try await xpStore.recordChallengeCompletion(xp: xp)
        return ApplyResult(
            applied: fresh,
            xpAwarded: xp,
            xpTotalBefore: result.totalXPBefore,
            xpTotalAfter: result.totalXPAfter
        )
    }
}
