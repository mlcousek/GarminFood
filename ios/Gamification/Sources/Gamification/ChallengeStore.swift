import Foundation

// ChallengeStore.swift
//
// Persists WHICH challenge is active and WHEN it started (challenges spec's
// "one or two active challenges... selected from a fixed set" requirement,
// design.md D4, task 25.2). This is genuinely required state, unlike
// streaks/levels: "which template is active right now" is a choice made at
// one point in time (activation or rotation), not something re-derivable
// from usage history alone. Same JSON-file-actor pattern as the other
// stores in this package.
//
// V1 keeps exactly ONE slot active at a time (the spec allows "one or two";
// this phase ships the simpler single-slot version -- a second concurrent
// slot is a natural, cheap future add-on per D4's own framing, not a
// correctness requirement here).
public actor ChallengeStore {
    private struct Snapshot: Codable {
        var active: ActiveChallenge?
        /// The last few template ids used (most-recent first), so
        /// rotation avoids repeating the immediately preceding challenge.
        /// Small and bounded -- purely an anti-repetition nicety, not
        /// correctness-critical.
        var recentTemplateIds: [String]
    }

    private static let maxRecentTemplateIds = 3

    private let fileURL: URL
    private var snapshot = Snapshot(active: nil, recentTemplateIds: [])
    private var loaded = false

    public init(fileURL: URL = ChallengeStore.defaultFileURL()) {
        self.fileURL = fileURL
    }

    public static func defaultFileURL() -> URL {
        GamificationStorage.directory().appendingPathComponent("challenge-state.json")
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: fileURL) else { return }
        snapshot = (try? JSONDecoder().decode(Snapshot.self, from: data)) ?? snapshot
    }

    private func persist() throws {
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: fileURL.path
        )
    }

    private func activate(template: ChallengeTemplate, now: Date, baselineStreakLength: Int) -> ActiveChallenge {
        let challenge = ActiveChallenge(templateId: template.id, startedAt: now, baselineStreakLength: baselineStreakLength)
        snapshot.active = challenge
        snapshot.recentTemplateIds.insert(template.id, at: 0)
        if snapshot.recentTemplateIds.count > Self.maxRecentTemplateIds {
            snapshot.recentTemplateIds.removeLast(snapshot.recentTemplateIds.count - Self.maxRecentTemplateIds)
        }
        return challenge
    }

    public func current() -> ActiveChallenge? {
        loadIfNeeded()
        return snapshot.active
    }

    /// Challenges spec's "no active challenge -> a new one is selected and
    /// activated". Returns the already-active challenge unchanged if one
    /// exists.
    @discardableResult
    public func ensureActive(catalog: [ChallengeTemplate], now: Date, baselineStreakLength: Int) throws -> ActiveChallenge {
        loadIfNeeded()
        if let active = snapshot.active { return active }
        let template = ChallengeRotation.pickNext(from: catalog, excluding: Set(snapshot.recentTemplateIds), now: now)
        let activated = activate(template: template, now: now, baselineStreakLength: baselineStreakLength)
        try persist()
        return activated
    }

    /// Challenges spec's "completing a challenge... replaces it with a new
    /// one" requirement. Caller is responsible for awarding XP
    /// (`XPStore.recordChallengeCompletion`) and for having already
    /// confirmed `progress.isComplete` -- this method only performs the
    /// rotation itself.
    @discardableResult
    public func completeAndRotate(catalog: [ChallengeTemplate], now: Date, baselineStreakLength: Int) throws -> ActiveChallenge {
        loadIfNeeded()
        let template = ChallengeRotation.pickNext(from: catalog, excluding: Set(snapshot.recentTemplateIds), now: now)
        let activated = activate(template: template, now: now, baselineStreakLength: baselineStreakLength)
        try persist()
        return activated
    }

    /// Challenges spec's "a challenge also rotates after a time window
    /// without completion" requirement -- no XP awarded, per that
    /// requirement's own scenario ("without awarding completion XP").
    @discardableResult
    public func rotateIfWindowElapsed(
        catalog: [ChallengeTemplate],
        now: Date,
        baselineStreakLength: Int,
        boundaryHour: Int = NutritionDayBoundary.defaultBoundaryHour
    ) throws -> Bool {
        loadIfNeeded()
        guard let active = snapshot.active,
              let template = catalog.first(where: { $0.id == active.templateId }),
              ChallengeEngine.isWindowElapsed(active: active, template: template, now: now, boundaryHour: boundaryHour)
        else { return false }

        let nextTemplate = ChallengeRotation.pickNext(from: catalog, excluding: Set(snapshot.recentTemplateIds), now: now)
        _ = activate(template: nextTemplate, now: now, baselineStreakLength: baselineStreakLength)
        try persist()
        return true
    }
}
