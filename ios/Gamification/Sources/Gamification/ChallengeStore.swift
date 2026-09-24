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

        init(active: ActiveChallenge?, recentTemplateIds: [String]) {
            self.active = active
            self.recentTemplateIds = recentTemplateIds
        }

        // Optional-safe decode (add-gamification-signals): a file missing
        // `recentTemplateIds` still loads instead of being quarantined.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            active = try container.decodeIfPresent(ActiveChallenge.self, forKey: .active)
            recentTemplateIds = try container.decodeIfPresent([String].self, forKey: .recentTemplateIds) ?? []
        }
    }

    /// add-gamification-signals D11: 3 -> 8, so the weighted rotation
    /// doesn't bounce between the same few high-weight templates.
    static let maxRecentTemplateIds = 8

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
        // Unreadable (e.g. before first unlock): don't latch, retry on next
        // access; `persist()` refuses to overwrite it meanwhile.
        let result = GamificationStorage.loadPersistedJSON(Snapshot.self, from: fileURL, decoder: JSONDecoder(), category: "ChallengeStore")
        loaded = !result.isUnreadable
        snapshot = result.value ?? snapshot
    }

    private func persist() throws {
        try GamificationStorage.ensureSafeToWrite(loaded: loaded, fileURL: fileURL, category: "ChallengeStore")
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
    public func ensureActive(catalog: [ChallengeTemplate], now: Date, baselineStreakLength: Int, policy: ChallengeRotationPolicy = ChallengeRotationPolicy()) throws -> ActiveChallenge {
        loadIfNeeded()
        if let active = snapshot.active { return active }
        let template = ChallengeRotation.pickNext(from: catalog, excluding: Set(snapshot.recentTemplateIds), now: now, policy: policy)
        let activated = activate(template: template, now: now, baselineStreakLength: baselineStreakLength)
        try persist()
        return activated
    }

    /// Challenges spec's "completing a challenge... replaces it with a new
    /// one" requirement. Caller is responsible for awarding XP
    /// (`XPStore.recordChallengeCompletion`) and for having already
    /// confirmed `progress.isComplete`.
    ///
    /// 2026-09-21 bug fix: this method used to be unconditional -- no
    /// "has someone already completed THIS instance" check, unlike
    /// `DailyChallengeStore.markCompleted`/`AchievementStore.unlock`.
    /// `GamificationEngine.handleLogConfirmed` is invoked from a bare
    /// `Task { }` per confirmed log (not tied to a view's lifecycle), so
    /// logging two foods back-to-back could produce two overlapping calls
    /// that both saw the same active challenge as complete before either
    /// had rotated it away -- double-awarding XP, double-recording
    /// history, and rotating twice. The unconditional version was removed
    /// outright (not just deprecated) rather than left alongside this one,
    /// since a future caller reaching for the simpler-looking name would
    /// silently reintroduce that exact race. Since `ChallengeStore` is an
    /// actor and this method contains no `await`, it runs as one atomic
    /// unit -- only the FIRST concurrent caller to reach it still finds
    /// `templateId` active and gets a real rotation; any later overlapping
    /// caller for the SAME already-completed instance sees it already
    /// rotated away and gets `nil`.
    @discardableResult
    public func completeAndRotateIfStillActive(templateId: String, catalog: [ChallengeTemplate], now: Date, baselineStreakLength: Int, policy: ChallengeRotationPolicy = ChallengeRotationPolicy()) throws -> ActiveChallenge? {
        loadIfNeeded()
        guard snapshot.active?.templateId == templateId else { return nil }
        let template = ChallengeRotation.pickNext(from: catalog, excluding: Set(snapshot.recentTemplateIds), now: now, policy: policy)
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
        boundaryHour: Int = NutritionDayBoundary.defaultBoundaryHour,
        policy: ChallengeRotationPolicy = ChallengeRotationPolicy()
    ) throws -> Bool {
        loadIfNeeded()
        guard let active = snapshot.active,
              let template = catalog.first(where: { $0.id == active.templateId }),
              ChallengeEngine.isWindowElapsed(active: active, template: template, now: now, boundaryHour: boundaryHour)
        else { return false }

        let nextTemplate = ChallengeRotation.pickNext(from: catalog, excluding: Set(snapshot.recentTemplateIds), now: now, policy: policy)
        _ = activate(template: nextTemplate, now: now, baselineStreakLength: baselineStreakLength)
        try persist()
        return true
    }
}
