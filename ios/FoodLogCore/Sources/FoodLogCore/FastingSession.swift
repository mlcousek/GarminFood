// FastingSession.swift
//
// RETIRED (redesign-fasting-schedule, 2026-09-23). This was the manual
// intermittent-fasting model (owner request 2026-09-22): pick a protocol,
// tap Start, tap Break Fast, tap End. The owner replaced it with a daily
// fasting window set once in Settings (`FastingSchedule`,
// FastingSchedule.swift), so nothing creates or updates sessions any more.
//
// What remains is only what the one-time migration needs
// (`FastingScheduleMigration`, task 1.3): the `FastingProtocol` and
// `FastingSession` Codable shapes -- unchanged, so an existing
// `fasting-sessions.json` still decodes -- and a READ-ONLY
// `FastingSessionStore`. The file is deliberately left on disk (never
// rewritten, never deleted): it's the owner's own record of past fasts, and
// deleting user data is not this migration's call to make.
//
// `FastingProtocol` keeps its hand-written Codable (see below) for the same
// reason it was written that way: the wire shape must not drift from what
// older builds wrote. Purely local -- Garmin's API has no fasting concept.

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

// MARK: - Session

public struct FastingSession: Codable, Sendable, Equatable, Identifiable, Hashable {
    public let id: UUID
    public var protocolKind: FastingProtocol
    public var startedAt: Date
    /// Set the moment the user taps "break fast" -- the fasting phase's
    /// REAL end, which may be earlier or later than the protocol's
    /// scheduled boundary. `nil` means still fasting (even past the
    /// scheduled boundary).
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
}

// MARK: - Store (read-only, legacy)

/// Read-only view of the legacy `fasting-sessions.json`
/// (redesign-fasting-schedule 1.3). Nothing writes this file any more and
/// nothing deletes it: `FastingScheduleMigration` reads it exactly once,
/// through `active()`/`history()`, to seed the daily schedule. Kept as an
/// actor (rather than a static function) only so `AppServices` keeps its
/// one-instance-per-process shape unchanged.
public actor FastingSessionStore {
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

    /// A missing file (never used the old flow) reads as empty.
    private func loadIfNeeded() {
        guard !loaded else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let result = FoodLogCoreStorage.loadPersistedJSON(PersistedState.self, from: fileURL, decoder: decoder, category: "FastingSessionStore")
        // Read-only store (nothing to guard on save), but an unreadable
        // file must still be retried rather than latched as "never used" --
        // `FastingScheduleMigration` would otherwise seed from nothing.
        loaded = !result.isUnreadable
        state = result.value ?? PersistedState(active: nil, history: [])
    }

    public func active() -> FastingSession? {
        loadIfNeeded()
        return state.active
    }

    public func history() -> [FastingSession] {
        loadIfNeeded()
        return state.history.sorted { $0.startedAt > $1.startedAt }
    }
}
