// HubEvent.swift
//
// THE wire format of what the app writes to the vault (add-training-checkins
// design D2): one event per training action, serialised as one JSON object
// per line (JSONL) into segment files under `events/<deviceId>/`. This is
// the ONLY file that knows the envelope's field names, the type strings and
// the payload keys, so when the vault's event contract v1 (its
// `add-hub-ingest` change) settles a detail differently, the change is made
// here, and `HubEventTests` + the golden fixture
// (Tests/TrainingCoreTests/Fixtures/Events/events.v1.app.jsonl) catch any
// drift.
//
// Envelope v1 (app side, pending the vault's fixture -- tasks group 1):
//
//   {"at":"2030-10-23T04:07:31.000+02:00","deviceId":"ios-0000beef",
//    "id":"<UUIDv7>","payload":{...},"seq":7,"type":"checkin.morning","v":1}
//
//   checkin.morning  {date, light: green|amber|red, sessionId?}
//   habit.tick       {date, habitId, done}           (decision A42: on/off)
//   session.rpe      {date, sessionId, rpe: 1...10}
//   session.note     {date, sessionId, text}         (<= 2000 characters)
//
// Differences from the architecture note's section 2.4 draft, each a
// one-line change below if the contract says otherwise: `deviceId` (not
// `src.device`), `payload` (not `data`), `date` inside the payload (not a
// top-level `day`), no `tz`/`src`/`cmd`, `habit.tick {done}` (not
// `habit.done {n, part}`), `session.rpe`/`session.note` (not
// `session.rated`/`note.added`). The light uses the projection's own words
// (`day.light`), from which the option letter follows (G<->green, ...).
//
// Encoding is deterministic (sorted keys, unescaped slashes, `\n` after
// every line) because a sealed segment's bytes and git blob SHA must be the
// same on every retry (VaultKit's SealedFile). Decoding is tolerant: unknown
// fields are ignored and an unknown type is kept as `.other`, never
// encoded.
//
// Depended on by: TrainingEventLog (stores these), EventSegment (writes
// them), CheckInOverlay (folds them), TrainingRecorder. Tests:
// HubEventTests.

import Foundation

// MARK: - Types and payloads

public enum HubEventType: Hashable, Sendable {
    case morningCheckIn
    case habitTick
    case sessionRPE
    case sessionNote
    /// A type this build doesn't write (read from a newer fixture).
    case other(String)

    public init(rawValue: String) {
        switch rawValue {
        case "checkin.morning": self = .morningCheckIn
        case "habit.tick": self = .habitTick
        case "session.rpe": self = .sessionRPE
        case "session.note": self = .sessionNote
        default: self = .other(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .morningCheckIn: return "checkin.morning"
        case .habitTick: return "habit.tick"
        case .sessionRPE: return "session.rpe"
        case .sessionNote: return "session.note"
        case .other(let raw): return raw
        }
    }
}

public struct MorningCheckInPayload: Equatable, Sendable {
    /// The training day the check-in is for.
    public var date: LocalDate
    public var light: MorningLight
    /// The day's traffic-light session, when it has one.
    public var sessionId: String?

    public init(date: LocalDate, light: MorningLight, sessionId: String? = nil) {
        self.date = date
        self.light = light
        self.sessionId = sessionId
    }
}

public struct HabitTickPayload: Equatable, Sendable {
    public var date: LocalDate
    public var habitId: String
    public var done: Bool

    public init(date: LocalDate, habitId: String, done: Bool) {
        self.date = date
        self.habitId = habitId
        self.done = done
    }
}

public struct SessionRPEPayload: Equatable, Sendable {
    public static let range = 1...10

    public var date: LocalDate
    public var sessionId: String
    public var rpe: Int

    public init(date: LocalDate, sessionId: String, rpe: Int) {
        self.date = date
        self.sessionId = sessionId
        self.rpe = rpe
    }
}

public struct SessionNotePayload: Equatable, Sendable {
    public static let maxLength = 2000

    public var date: LocalDate
    public var sessionId: String
    public var text: String

    public init(date: LocalDate, sessionId: String, text: String) {
        self.date = date
        self.sessionId = sessionId
        self.text = text
    }
}

public enum HubEventPayload: Equatable, Sendable {
    case morningCheckIn(MorningCheckInPayload)
    case habitTick(HabitTickPayload)
    case sessionRPE(SessionRPEPayload)
    case sessionNote(SessionNotePayload)
    /// An unknown type, read only; `date` when its payload had one.
    case other(type: String, date: LocalDate?)

    public var type: HubEventType {
        switch self {
        case .morningCheckIn: return .morningCheckIn
        case .habitTick: return .habitTick
        case .sessionRPE: return .sessionRPE
        case .sessionNote: return .sessionNote
        case .other(let type, _): return .other(type)
        }
    }

    public var date: LocalDate? {
        switch self {
        case .morningCheckIn(let payload): return payload.date
        case .habitTick(let payload): return payload.date
        case .sessionRPE(let payload): return payload.date
        case .sessionNote(let payload): return payload.date
        case .other(_, let date): return date
        }
    }

    /// Whether this build may write it (see `HubEventError`).
    public func validate() throws {
        switch self {
        case .morningCheckIn:
            return
        case .habitTick(let payload):
            if payload.habitId.isEmpty { throw HubEventError.invalidPayload("empty habitId") }
        case .sessionRPE(let payload):
            if payload.sessionId.isEmpty { throw HubEventError.invalidPayload("empty sessionId") }
            if !SessionRPEPayload.range.contains(payload.rpe) { throw HubEventError.invalidPayload("rpe out of range") }
        case .sessionNote(let payload):
            if payload.sessionId.isEmpty { throw HubEventError.invalidPayload("empty sessionId") }
            if payload.text.count > SessionNotePayload.maxLength { throw HubEventError.invalidPayload("note too long") }
        case .other:
            throw HubEventError.unknownType
        }
    }
}

public enum HubEventError: Error, Equatable, Sendable {
    case invalidPayload(String)
    /// `.other` events are read, never written.
    case unknownType
}

// MARK: - Envelope

public struct HubEvent: Equatable, Sendable, Identifiable {
    public static let envelopeVersion = 1

    public let v: Int
    /// UUIDv7, lowercase (`UUIDv7.string`); the vault dedupes by it.
    public let id: String
    /// `ios-xxxxxxxx`, the folder the event is written into.
    public let deviceId: String
    /// Per device, monotonic, never reused.
    public let seq: Int
    /// Producer wall clock with its UTC offset (`HubEventClock`).
    public let at: String
    public let payload: HubEventPayload

    public var type: HubEventType { payload.type }

    public init(v: Int = HubEvent.envelopeVersion, id: String, deviceId: String, seq: Int, at: String, payload: HubEventPayload) {
        self.v = v
        self.id = id
        self.deviceId = deviceId
        self.seq = seq
        self.at = at
        self.payload = payload
    }
}

extension HubEvent: Codable {
    enum CodingKeys: String, CodingKey {
        case v, id, deviceId, seq, at, type, payload
    }

    enum PayloadKeys: String, CodingKey {
        case date, light, sessionId, habitId, done, rpe, text
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        v = try c.decodeIfPresent(Int.self, forKey: .v) ?? HubEvent.envelopeVersion
        id = try c.decode(String.self, forKey: .id)
        deviceId = try c.decode(String.self, forKey: .deviceId)
        seq = try c.decode(Int.self, forKey: .seq)
        at = try c.decode(String.self, forKey: .at)
        let type = HubEventType(rawValue: try c.decode(String.self, forKey: .type))

        if case .other(let raw) = type {
            let p = try? c.nestedContainer(keyedBy: PayloadKeys.self, forKey: .payload)
            let dateText = (try? p?.decodeIfPresent(String.self, forKey: .date)) ?? nil
            payload = .other(type: raw, date: dateText.flatMap { LocalDate($0) })
            return
        }

        let p = try c.nestedContainer(keyedBy: PayloadKeys.self, forKey: .payload)
        let dateText = try p.decode(String.self, forKey: .date)
        guard let date = LocalDate(dateText) else {
            throw DecodingError.dataCorruptedError(forKey: .date, in: p, debugDescription: "not a YYYY-MM-DD date")
        }
        switch type {
        case .morningCheckIn:
            let lightText = try p.decode(String.self, forKey: .light)
            guard let light = MorningLight(rawValue: lightText) else {
                throw DecodingError.dataCorruptedError(forKey: .light, in: p, debugDescription: "unknown light")
            }
            payload = .morningCheckIn(MorningCheckInPayload(date: date, light: light, sessionId: try p.decodeIfPresent(String.self, forKey: .sessionId)))
        case .habitTick:
            payload = .habitTick(HabitTickPayload(
                date: date,
                habitId: try p.decode(String.self, forKey: .habitId),
                done: try p.decode(Bool.self, forKey: .done)
            ))
        case .sessionRPE:
            payload = .sessionRPE(SessionRPEPayload(
                date: date,
                sessionId: try p.decode(String.self, forKey: .sessionId),
                rpe: try p.decode(Int.self, forKey: .rpe)
            ))
        case .sessionNote:
            payload = .sessionNote(SessionNotePayload(
                date: date,
                sessionId: try p.decode(String.self, forKey: .sessionId),
                text: try p.decode(String.self, forKey: .text)
            ))
        case .other(let raw):
            payload = .other(type: raw, date: date)
        }
    }

    public func encode(to encoder: Encoder) throws {
        if case .other = payload {
            throw EncodingError.invalidValue(type.rawValue, EncodingError.Context(codingPath: [], debugDescription: "unknown event types are never written"))
        }
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(v, forKey: .v)
        try c.encode(id, forKey: .id)
        try c.encode(deviceId, forKey: .deviceId)
        try c.encode(seq, forKey: .seq)
        try c.encode(at, forKey: .at)
        try c.encode(type.rawValue, forKey: .type)
        var p = c.nestedContainer(keyedBy: PayloadKeys.self, forKey: .payload)
        switch payload {
        case .morningCheckIn(let value):
            try p.encode(value.date.description, forKey: .date)
            try p.encode(value.light.rawValue, forKey: .light)
            try p.encodeIfPresent(value.sessionId, forKey: .sessionId)
        case .habitTick(let value):
            try p.encode(value.date.description, forKey: .date)
            try p.encode(value.habitId, forKey: .habitId)
            try p.encode(value.done, forKey: .done)
        case .sessionRPE(let value):
            try p.encode(value.date.description, forKey: .date)
            try p.encode(value.sessionId, forKey: .sessionId)
            try p.encode(value.rpe, forKey: .rpe)
        case .sessionNote(let value):
            try p.encode(value.date.description, forKey: .date)
            try p.encode(value.sessionId, forKey: .sessionId)
            try p.encode(value.text, forKey: .text)
        case .other:
            break
        }
    }
}

// MARK: - JSONL

public enum HubEventCodec {
    /// Sorted keys and unescaped slashes: the same event is always the same
    /// bytes (see this file's header).
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    /// One event as one line, without the newline.
    public static func line(_ event: HubEvent) throws -> Data {
        try makeEncoder().encode(event)
    }

    /// Events as JSONL: every line followed by `\n`.
    public static func jsonl(_ events: [HubEvent]) throws -> Data {
        var data = Data()
        for event in events {
            data.append(try line(event))
            data.append(0x0A)
        }
        return data
    }

    public struct DecodedLines: Equatable, Sendable {
        public var events: [HubEvent] = []
        /// 1-based numbers of the lines that did not decode.
        public var invalidLines: [Int] = []
    }

    /// Reads JSONL tolerantly: blank lines are skipped, a `\r` before the
    /// `\n` is ignored, and a line that doesn't decode is reported, not
    /// fatal.
    public static func decode(_ data: Data) -> DecodedLines {
        var result = DecodedLines()
        let decoder = JSONDecoder()
        let lines = data.split(separator: 0x0A, omittingEmptySubsequences: false)
        for (index, rawLine) in lines.enumerated() {
            var line = Data(rawLine)
            if line.last == 0x0D { line.removeLast() }
            if line.allSatisfy({ $0 == 0x20 || $0 == 0x09 }) { continue }
            do {
                result.events.append(try decoder.decode(HubEvent.self, from: line))
            } catch {
                result.invalidLines.append(index + 1)
            }
        }
        return result
    }
}

// MARK: - Clock

public enum HubEventClock {
    /// `2030-10-23T04:07:31.000+02:00`: local wall clock, milliseconds, the
    /// zone's offset at that instant (`Z` for UTC).
    public static func string(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"
        return formatter.string(from: date)
    }
}

// MARK: - Lights, options

public extension MorningLight {
    /// The check-in's order on screen and in the Controls: G, A, R.
    static let checkInOrder: [MorningLight] = [.greenLight, .amberLight, .redLight]
}
