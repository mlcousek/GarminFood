// FastingSession.swift
//
// The intermittent-fasting domain model (owner request 2026-09-22, after a
// competitive read of Yazio found its fasting timer to be a genuine
// differentiator). Purely local -- Garmin's API has no fasting concept at
// all (config.yaml's ground-truth list doesn't mention one, and there is no
// route to probe), so unlike almost everything else in this package this
// never touches `GarminKit`/`GarminClient` and never queues anything in the
// `Outbox`. It is its own self-contained local feature end to end.
//
// `FastingProtocol` is an enum with associated values rather than a struct
// with a free-floating `(fastingHours, eatingHours)` pair, so the common
// named protocols (16:8, 18:6, 20:4, OMAD) can't drift out of sync with each
// other or be constructed with a nonsensical pairing by accident, while
// `.custom` still carries the user's own two numbers when neither preset
// fits. `FastingSession` itself only ever records what actually happened
// (`startedAt`, and `fastingEndedAt`/`eatingEndedAt` set only once the user
// actually taps "break fast"/"end window") -- the scheduled boundary is
// always DERIVED from the protocol, never stored, so a session that runs
// long or short is still represented exactly as it happened, not silently
// clamped to the plan. `currentPhase(at:)` is the one place that turns
// "what's stored" + "what time is it" into "what phase are we in right
// now", and is the single source of truth every UI surface (the Today card,
// the Fasting tab's ring, `NotificationPlanning.planFastingReminder`) reads
// from, so "fasting vs eating" and "time remaining" can never disagree
// between screens.
//
// `FastingSessionStore` mirrors `MealPresetStore`'s exact
// actor/JSON-file/loadIfNeeded/persist shape (see that file's header) --
// same local-first, zero-dependency pattern, just splitting the JSON
// document into one active session (at most one fast running at a time) and
// a history array of finished ones, rather than a single dictionary of
// independent records.

import Foundation

// MARK: - Protocol

public enum FastingProtocol: Codable, Sendable, Equatable, Hashable {
    case sixteenEight
    case eighteenSix
    case twentyFour
    case omad
    case custom(fastingHours: Double, eatingHours: Double)

    public var fastingHours: Double {
        switch self {
        case .sixteenEight: return 16
        case .eighteenSix: return 18
        case .twentyFour: return 20
        case .omad: return 23
        case .custom(let fastingHours, _): return fastingHours
        }
    }

    public var eatingHours: Double {
        switch self {
        case .sixteenEight: return 8
        case .eighteenSix: return 6
        case .twentyFour: return 4
        case .omad: return 1
        case .custom(_, let eatingHours): return eatingHours
        }
    }

    /// UI-facing label. Kept here (not in `GarminFood/`) since it's a plain
    /// fact about the protocol, not layout -- same reasoning as
    /// `MealType.displayName` living in the app layer only where a
    /// mid-sentence lowercase variant is also needed (see
    /// `NotificationPlanning.swift`'s `MealType.displayNameLowercased`);
    /// this one has no such second form.
    public var displayName: String {
        switch self {
        case .sixteenEight: return "16:8"
        case .eighteenSix: return "18:6"
        case .twentyFour: return "20:4"
        case .omad: return "OMAD (23:1)"
        case .custom: return "Custom"
        }
    }
}

extension FastingProtocol {
    // Hand-written rather than relying on the compiler's enum-with-
    // associated-values Codable synthesis -- this project can't compile
    // locally to double check the exact wire shape synthesis would produce
    // (see CLAUDE.md's "no Mac" constraint), so an explicit, obviously
    // correct encode/decode pair is the safer choice here over trusting an
    // inferred format sight-unseen.
    private enum Kind: String, Codable {
        case sixteenEight, eighteenSix, twentyFour, omad, custom
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case fastingHours
        case eatingHours
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .sixteenEight: self = .sixteenEight
        case .eighteenSix: self = .eighteenSix
        case .twentyFour: self = .twentyFour
        case .omad: self = .omad
        case .custom:
            self = .custom(
                fastingHours: try container.decode(Double.self, forKey: .fastingHours),
                eatingHours: try container.decode(Double.self, forKey: .eatingHours)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .sixteenEight: try container.encode(Kind.sixteenEight, forKey: .kind)
        case .eighteenSix: try container.encode(Kind.eighteenSix, forKey: .kind)
        case .twentyFour: try container.encode(Kind.twentyFour, forKey: .kind)
        case .omad: try container.encode(Kind.omad, forKey: .kind)
        case .custom(let fastingHours, let eatingHours):
            try container.encode(Kind.custom, forKey: .kind)
            try container.encode(fastingHours, forKey: .fastingHours)
            try container.encode(eatingHours, forKey: .eatingHours)
        }
    }
}

// MARK: - Phase

public enum FastingPhaseKind: Sendable, Equatable {
    case fasting
    case eating
}

/// The phase a session is in at a given moment -- always derived, never
/// stored (see file header). `scheduledEndAt` is the PLANNED boundary from
/// the protocol; a phase can legitimately run past it (the user hasn't
/// tapped "break fast" yet), which `isOverdue(at:)` reports rather than
/// clamping away.
public struct FastingPhase: Sendable, Equatable {
    public let kind: FastingPhaseKind
    public let startedAt: Date
    public let scheduledEndAt: Date

    public init(kind: FastingPhaseKind, startedAt: Date, scheduledEndAt: Date) {
        self.kind = kind
        self.startedAt = startedAt
        self.scheduledEndAt = scheduledEndAt
    }

    public var duration: TimeInterval { scheduledEndAt.timeIntervalSince(startedAt) }

    public func elapsed(at now: Date) -> TimeInterval { max(0, now.timeIntervalSince(startedAt)) }

    /// Can go negative once `isOverdue(at:)` is true -- callers that want a
    /// always-positive "how far over" figure use `elapsed(at:) - duration`
    /// instead.
    public func remaining(at now: Date) -> TimeInterval { scheduledEndAt.timeIntervalSince(now) }

    public func isOverdue(at now: Date) -> Bool { now > scheduledEndAt }

    /// 0...1, clamped -- straight into `ProgressRing.fraction`.
    public func fraction(at now: Date) -> Double {
        guard duration > 0 else { return 0 }
        return min(max(elapsed(at: now) / duration, 0), 1)
    }
}

// MARK: - Session

public struct FastingSession: Codable, Sendable, Equatable, Identifiable, Hashable {
    public let id: UUID
    public var protocolKind: FastingProtocol
    public var startedAt: Date
    /// Set the moment the user taps "break fast" -- the fasting phase's
    /// REAL end, which may be earlier or later than the protocol's
    /// scheduled boundary. `nil` means still fasting (even past the
    /// scheduled boundary -- see `FastingPhase.isOverdue`).
    public var fastingEndedAt: Date?
    /// Set once the whole session is closed out (a new fast started, or the
    /// user explicitly ends the eating window). `nil` while the session is
    /// still active in either phase.
    public var eatingEndedAt: Date?

    public init(
        id: UUID = UUID(),
        protocolKind: FastingProtocol,
        startedAt: Date = Date(),
        fastingEndedAt: Date? = nil,
        eatingEndedAt: Date? = nil
    ) {
        self.id = id
        self.protocolKind = protocolKind
        self.startedAt = startedAt
        self.fastingEndedAt = fastingEndedAt
        self.eatingEndedAt = eatingEndedAt
    }

    /// The phase this session is in at `now`. Reads the session's own
    /// recorded end times when present (an actual tap always wins over the
    /// schedule); falls back to the protocol's scheduled boundary
    /// otherwise. This is the ONLY place phase is computed -- every UI
    /// surface and `NotificationPlanning.planFastingReminder` call this
    /// rather than re-deriving it.
    public func currentPhase(at now: Date) -> FastingPhase {
        let scheduledFastingEnd = startedAt.addingTimeInterval(protocolKind.fastingHours * 3600)
        guard let fastingEndedAt else {
            return FastingPhase(kind: .fasting, startedAt: startedAt, scheduledEndAt: scheduledFastingEnd)
        }
        let scheduledEatingEnd = fastingEndedAt.addingTimeInterval(protocolKind.eatingHours * 3600)
        return FastingPhase(kind: .eating, startedAt: fastingEndedAt, scheduledEndAt: eatingEndedAt ?? scheduledEatingEnd)
    }

    /// True once the fast was explicitly ended AND ran at least as long as
    /// the protocol's own target -- an early break doesn't count, matching
    /// `Gamification.StreakEngine`'s own "never fudge a day that didn't
    /// actually happen" honesty (this package can't depend on Gamification
    /// -- see `NotificationPlanning.swift`'s header for why the dependency
    /// only runs the other way -- so this is FastingSession's own,
    /// independent notion of "completed").
    public var metFastingTarget: Bool {
        guard let fastingEndedAt else { return false }
        return fastingEndedAt.timeIntervalSince(startedAt) >= protocolKind.fastingHours * 3600
    }
}

// MARK: - Stats

/// Deliberately just one static function, not a full streak engine --
/// `Gamification.StreakEngine` already exists for the app's real
/// day-logging streak and fasting is a proportionately smaller feature here
/// (owner asked for "also a fasting timer", not a second gamification
/// system). "Current run" is the one streak-shaped stat that falls
/// naturally out of fasting history without forcing anything.
public enum FastingStats {
    /// Counts backward from the most recently STARTED completed session
    /// (`fastingEndedAt != nil`) while each one met its own protocol's
    /// target, stopping at the first miss. An in-progress session (no
    /// `fastingEndedAt` yet, i.e. today's active fast) is excluded rather
    /// than treated as a break -- it hasn't finished yet, so it can't be
    /// judged either way.
    public static func currentRun(history: [FastingSession]) -> Int {
        let completed = history
            .filter { $0.fastingEndedAt != nil }
            .sorted { $0.startedAt > $1.startedAt }
        var run = 0
        for session in completed {
            guard session.metFastingTarget else { break }
            run += 1
        }
        return run
    }
}

// MARK: - Store

/// JSON-file-backed, actor-isolated -- same pattern as `MealPresetStore`.
public actor FastingSessionStore {
    public enum StoreError: Error, Equatable, Sendable {
        case sessionAlreadyActive
        case noActiveSession
    }

    private struct PersistedState: Codable {
        var active: FastingSession?
        var history: [FastingSession]
    }

    private let fileURL: URL
    private var state = PersistedState(active: nil, history: [])
    private var loaded = false

    public init(fileURL: URL = FastingSessionStore.defaultFileURL()) {
        self.fileURL = fileURL
    }

    public static func defaultFileURL() -> URL {
        FoodLogCoreStorage.directory().appendingPathComponent("fasting-sessions.json")
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        state = (try? decoder.decode(PersistedState.self, from: data)) ?? PersistedState(active: nil, history: [])
    }

    private func persist() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(state)
        try data.write(to: fileURL, options: .atomic)
    }

    public func active() -> FastingSession? {
        loadIfNeeded()
        return state.active
    }

    public func history() -> [FastingSession] {
        loadIfNeeded()
        return state.history.sorted { $0.startedAt > $1.startedAt }
    }

    /// Starts a new fast. Throws rather than silently replacing an existing
    /// one -- there is only ever meant to be one fast running at a time, and
    /// a caller that got here anyway (a UI bug, or two taps racing) should
    /// find out rather than quietly lose the session already in progress.
    @discardableResult
    public func start(_ session: FastingSession) throws -> FastingSession {
        loadIfNeeded()
        guard state.active == nil else { throw StoreError.sessionAlreadyActive }
        state.active = session
        try persist()
        return session
    }

    /// Ends the fasting phase (moves the active session into eating),
    /// leaving it active. Idempotent: a session already past this point is
    /// left untouched rather than throwing, since two near-simultaneous
    /// "break fast" taps are a UI race, not a real error.
    public func endFastingPhase(at date: Date) throws {
        loadIfNeeded()
        guard var session = state.active else { throw StoreError.noActiveSession }
        guard session.fastingEndedAt == nil else { return }
        session.fastingEndedAt = date
        state.active = session
        try persist()
    }

    /// Closes out the active session entirely and archives it to history.
    /// If the fasting phase was never explicitly ended (the user went
    /// straight from "fasting" to "end session"), this ends it at the same
    /// moment too, so a completed session never leaves `fastingEndedAt` nil
    /// in history -- which would otherwise make `metFastingTarget` always
    /// false for a fast the user genuinely intended to finish.
    @discardableResult
    public func endActiveSession(at date: Date) throws -> FastingSession {
        loadIfNeeded()
        guard var session = state.active else { throw StoreError.noActiveSession }
        if session.fastingEndedAt == nil { session.fastingEndedAt = date }
        session.eatingEndedAt = date
        state.history.append(session)
        state.active = nil
        try persist()
        return session
    }

    /// Discards the active session without archiving it -- for "I started
    /// this by mistake", not a normal end. Never touches history, so it
    /// never counts towards or breaks `FastingStats.currentRun`.
    public func cancelActiveSession() throws {
        loadIfNeeded()
        guard state.active != nil else { throw StoreError.noActiveSession }
        state.active = nil
        try persist()
    }

    public func deleteFromHistory(id: UUID) throws {
        loadIfNeeded()
        state.history.removeAll { $0.id == id }
        try persist()
    }
}
