import Foundation

// AchievementStore.swift
//
// Persists which achievements are unlocked, and when -- achievements
// spec's "permanently record an achievement as unlocked... SHALL NOT be
// re-evaluated or revoked afterward" requirement. Same JSON-file-actor
// pattern as every other store in this package.
public actor AchievementStore {
    private struct Snapshot: Codable {
        /// id -> unlock date.
        var unlockedAt: [String: Date] = [:]
    }

    private let fileURL: URL
    private var snapshot = Snapshot()
    private var loaded = false

    public init(fileURL: URL = AchievementStore.defaultFileURL()) {
        self.fileURL = fileURL
    }

    public static func defaultFileURL() -> URL {
        GamificationStorage.directory().appendingPathComponent("achievements.json")
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        // Unreadable (e.g. before first unlock): don't latch, retry on next
        // access; `persist()` refuses to overwrite it meanwhile.
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let result = GamificationStorage.loadPersistedJSON(Snapshot.self, from: fileURL, decoder: decoder, category: "AchievementStore")
        loaded = !result.isUnreadable
        snapshot = result.value ?? snapshot
    }

    private func persist() throws {
        try GamificationStorage.ensureSafeToWrite(loaded: loaded, fileURL: fileURL, category: "AchievementStore")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: fileURL.path
        )
    }

    public func unlockedIds() -> Set<String> {
        loadIfNeeded()
        return Set(snapshot.unlockedAt.keys)
    }

    public func unlockDate(for id: String) -> Date? {
        loadIfNeeded()
        return snapshot.unlockedAt[id]
    }

    /// Every unlock, id -> date, for display (achievements spec's "showing
    /// the unlock date for each unlocked achievement").
    public func all() -> [String: Date] {
        loadIfNeeded()
        return snapshot.unlockedAt
    }

    /// Records each of `ids` as unlocked at `now`, skipping any already
    /// recorded (permanence: never overwritten, never revoked). Returns
    /// only the ids that were newly recorded by this call.
    @discardableResult
    public func unlock(ids: [String], now: Date) throws -> [String] {
        loadIfNeeded()
        var newlyUnlocked: [String] = []
        for id in ids where snapshot.unlockedAt[id] == nil {
            snapshot.unlockedAt[id] = now
            newlyUnlocked.append(id)
        }
        if !newlyUnlocked.isEmpty {
            try persist()
        }
        return newlyUnlocked
    }
}
