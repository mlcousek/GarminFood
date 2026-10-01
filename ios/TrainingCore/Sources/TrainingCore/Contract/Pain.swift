// Pain.swift
//
// The morning pain score (add-checkin-pain-score design D1, D2, D4): the
// vault's contract added `pains` to `checkin.morning` and to every
// projection day on 2026-09-30 (its decision A57), additively within v1.
//
//   pains: [ { site, score, note? } ] | null
//     site   achilles-left | achilles-right | knee-left | knee-right | other
//            (any other string reads as `other`, never an error)
//     score  0-10 in steps of 0.5 (0 is an answer, not "unknown")
//     note   1-200 characters
//
// `nil` means "not asked", `[]` "asked, nothing hurts"; a site missing from
// the list is unknown, never 0. One type serves both directions: the
// projection's `day.pains` (decoded tolerantly, like every field) and the
// app's own `checkin.morning` (HubEvent.swift writes it, the only file that
// knows the event wire format).
//
// add-daily-checkin-and-pain-mode: `PainMode` is `athlete.painMode`, the
// vault's switch for every pain feature (below).
//
// Depended on by: HubEvent (MorningCheckInPayload.pains), Projection (Day),
// CheckInOverlay, PainModels. Tests: PainTests, HubEventTests,
// ProjectionDecodingTests.

import Foundation

/// A body site of the contract. Case names are the app's; raw values the
/// contract's words.
public enum PainSite: String, CaseIterable, Hashable, Sendable {
    case achillesLeft = "achilles-left"
    case achillesRight = "achilles-right"
    case kneeLeft = "knee-left"
    case kneeRight = "knee-right"
    case other

    /// The contract's rule: a site this build doesn't know is `other`.
    public init(wire: String) {
        self = PainSite(rawValue: wire) ?? .other
    }

    public var isAchilles: Bool {
        self == .achillesLeft || self == .achillesRight
    }
}

public struct PainEntry: Equatable, Sendable {
    public static let scoreRange: ClosedRange<Double> = 0...10
    public static let scoreStep = 0.5
    /// The contract's limit; the vault counts JavaScript string length
    /// (UTF-16 code units).
    public static let noteMaxLength = 200

    public var site: PainSite
    public var score: Double
    public var note: String?

    public init(site: PainSite, score: Double, note: String? = nil) {
        self.site = site
        self.score = score
        self.note = note
    }

    /// 0...10 and a multiple of 0.5 (`4.5` yes, `4.3` no).
    public static func isValidScore(_ score: Double) -> Bool {
        score.isFinite && scoreRange.contains(score) && (score * 2).rounded() == score * 2
    }

    /// Absent, or not blank and at most 200 UTF-16 code units.
    public static func isValidNote(_ note: String?) -> Bool {
        guard let note else { return true }
        if note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
        return note.utf16.count <= noteMaxLength
    }

    public var isValid: Bool {
        Self.isValidScore(score) && Self.isValidNote(note)
    }
}

extension PainEntry: Decodable {
    enum CodingKeys: String, CodingKey { case site, score, note }

    /// Tolerant (design D4): the score is the entry's identity -- without a
    /// number the entry throws and a lossy list drops it; an unknown or
    /// missing site is `other`; a missing, `null` or non-string note is none.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let score = try c.decode(Double.self, forKey: .score)
        guard score.isFinite else {
            throw DecodingError.dataCorruptedError(forKey: .score, in: c, debugDescription: "not a finite score")
        }
        self.score = score
        site = PainSite(wire: c.lenientString(.site) ?? PainSite.other.rawValue)
        note = c.lenientString(.note)
    }
}

extension PainEntry: Encodable {
    /// The contract's shape. A whole score is written as an integer (`1`,
    /// not `1.0`), a half step as `5.5`: every half step is exact, and the
    /// bytes never depend on how the platform prints a double (design D1).
    /// `note` is written, as `null` when there is none.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(site.rawValue, forKey: .site)
        if score.rounded() == score, abs(score) < 1_000 {
            try c.encode(Int(score), forKey: .score)
        } else {
            try c.encode(score, forKey: .score)
        }
        try c.encode(note, forKey: .note)
    }
}

// MARK: - Pain mode (add-daily-checkin-and-pain-mode)

/// `athlete.painMode` (the vault's semantics 14, 2026-09-30): pain
/// features appear when pain starts and stay until it is gone. The vault
/// turns it on at a check-in with a score above 0 or an amber/red check-in
/// light, and off after a run of scored mornings at 0; the phone never
/// runs those rules, it only reads the answer (and bridges the time until
/// the vault has read a new answer: `PainModeState`).
///
/// Tolerant like every field: a missing or non-boolean `active` is
/// `false`, an unknown site reads as `other`, an unknown reason is kept as
/// `.unknown`.
public struct PainMode: Equatable, Sendable, Decodable {
    public var active: Bool
    /// The first morning of the episode.
    public var since: LocalDate?
    /// The sites that scored above 0 in it.
    public var sites: [PainSite]
    public var reason: OpenEnum<PainModeReason>?
    /// The earliest morning whose check-in can end it.
    public var clearsAfter: LocalDate?

    public static let inactive = PainMode()

    public init(active: Bool = false, since: LocalDate? = nil, sites: [PainSite] = [], reason: OpenEnum<PainModeReason>? = nil, clearsAfter: LocalDate? = nil) {
        self.active = active
        self.since = since
        self.sites = sites
        self.reason = reason
        self.clearsAfter = clearsAfter
    }

    enum CodingKeys: String, CodingKey { case active, since, sites, reason, clearsAfter }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        active = c.lenientBool(.active) ?? false
        since = c.lenient(LocalDate.self, .since)
        var seen = Set<PainSite>()
        sites = c.stringList(.sites).map(PainSite.init(wire:)).filter { seen.insert($0).inserted }
        reason = c.lenient(OpenEnum<PainModeReason>.self, .reason)
        clearsAfter = c.lenient(LocalDate.self, .clearsAfter)
    }
}
