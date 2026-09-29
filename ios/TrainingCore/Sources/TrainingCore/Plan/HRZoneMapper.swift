// HRZoneMapper.swift
//
// Heart-rate targets in the athlete's own zones (spec "The session detail
// explains the session": "<=144 bpm . Z2"). The vault publishes the zones
// (`athlete.hrZones`, `null` when unknown) and targets as bpm (`hrMax`,
// `hrMin`) and/or a zone name (`zone: "Z2"`); this maps between them:
//
//   - a zone name is matched without regard to case (`Z2`, `z2`);
//   - a ceiling (`hrMax` only) is labelled with the zone containing it, a
//     floor (`hrMin` only) likewise, a band with the zone only when both
//     ends fall in the same one;
//   - an explicit `targets.zone` wins over the derived label, since it is
//     what the plan says;
//   - no zones -> no label, the bpm still show.
//
// Pure lookup, no arithmetic on the plan: the phone never recomputes what
// the vault computed.
//
// Depended on by: TargetFormatter, StepFormatter. Tests: HRZoneMapperTests.

import Foundation

public struct HRZoneMapper: Sendable {
    public let zones: HRZones?

    public init(zones: HRZones?) {
        self.zones = zones
    }

    /// "Z2" for "z2", "Z2", " z2 "; `nil` for anything else.
    public static func zoneNumber(_ raw: String?) -> Int? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespaces).lowercased()
        guard trimmed.hasPrefix("z"), let number = Int(trimmed.dropFirst()), number > 0 else { return nil }
        return number
    }

    /// The canonical label ("Z2") of a zone name, or `nil`.
    public static func normalizedLabel(_ raw: String?) -> String? {
        zoneNumber(raw).map { "Z\($0)" }
    }

    public func zone(named raw: String?) -> HRZone? {
        guard let number = Self.zoneNumber(raw) else { return nil }
        return zones?.zone(number: number)
    }

    public func zone(containing bpm: Int) -> HRZone? {
        zones?.zones.first { $0.contains(bpm) }
    }

    /// The zone label for a heart-rate target: the explicit zone, else the
    /// zone the bpm fall in (see this file's header).
    public func label(zone raw: String?, hrMin: Int?, hrMax: Int?) -> String? {
        if let explicit = Self.normalizedLabel(raw) { return explicit }
        switch (hrMin, hrMax) {
        case let (low?, high?):
            guard let lowZone = zone(containing: low), let highZone = zone(containing: high),
                  lowZone.number == highZone.number
            else { return nil }
            return lowZone.label
        case let (nil, high?):
            return zone(containing: high)?.label
        case let (low?, nil):
            return zone(containing: low)?.label
        case (nil, nil):
            return nil
        }
    }
}
